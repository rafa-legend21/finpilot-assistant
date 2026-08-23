from pathlib import Path

import pytest
from sqlalchemy import create_engine, text

from scripts.run_migrations import (
    MigrationError,
    MigrationRunner,
    discover_migrations,
    run_configured_migrations,
)


def write_migration(directory: Path, filename: str, sql: str) -> None:
    (directory / filename).write_text(sql, encoding="utf-8")


def test_first_run_applies_migration_and_second_run_skips(tmp_path: Path) -> None:
    write_migration(tmp_path, "001_create_example.sql", "CREATE TABLE example (id INTEGER)")
    engine = create_engine("sqlite+pysqlite:///:memory:")
    runner = MigrationRunner(engine, tmp_path, use_advisory_lock=False)

    assert runner.run() == ["001_create_example.sql"]
    assert runner.run() == []

    with engine.connect() as connection:
        count = connection.scalar(text("SELECT COUNT(*) FROM schema_migrations"))
    assert count == 1


def test_checksum_mismatch_for_applied_migration_fails(tmp_path: Path) -> None:
    path = tmp_path / "001_create_example.sql"
    path.write_text("CREATE TABLE example (id INTEGER)", encoding="utf-8")
    engine = create_engine("sqlite+pysqlite:///:memory:")
    runner = MigrationRunner(engine, tmp_path, use_advisory_lock=False)
    runner.run()
    path.write_text("CREATE TABLE changed (id INTEGER)", encoding="utf-8")

    with pytest.raises(MigrationError, match="has changed"):
        runner.run()


@pytest.mark.parametrize("filename", ["bad.sql", "01_bad.sql", "001-BAD.sql"])
def test_malformed_migration_version_fails(tmp_path: Path, filename: str) -> None:
    write_migration(tmp_path, filename, "SELECT 1")
    with pytest.raises(MigrationError, match="Malformed"):
        discover_migrations(tmp_path)


def test_duplicate_migration_version_fails(tmp_path: Path) -> None:
    write_migration(tmp_path, "001_first.sql", "SELECT 1")
    write_migration(tmp_path, "001_second.sql", "SELECT 1")
    with pytest.raises(MigrationError, match="Duplicate"):
        discover_migrations(tmp_path)


def test_failed_migration_is_rolled_back_and_not_recorded(tmp_path: Path) -> None:
    write_migration(tmp_path, "001_broken.sql", "THIS IS NOT SQL")
    engine = create_engine("sqlite+pysqlite:///:memory:")
    runner = MigrationRunner(engine, tmp_path, use_advisory_lock=False)

    with pytest.raises(Exception, match="syntax"):
        runner.run()

    with engine.connect() as connection:
        count = connection.scalar(text("SELECT COUNT(*) FROM schema_migrations"))
    assert count == 0


def test_non_postgresql_database_url_is_rejected() -> None:
    with pytest.raises(MigrationError, match="PostgreSQL"):
        run_configured_migrations("sqlite+pysqlite:///:memory:")
