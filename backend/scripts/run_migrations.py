from __future__ import annotations

import hashlib
import os
import re
import sys
from dataclasses import dataclass
from pathlib import Path

from sqlalchemy import Engine, create_engine, text
from sqlalchemy.engine import make_url
from sqlalchemy.exc import SQLAlchemyError

MIGRATION_PATTERN = re.compile(r"^(?P<version>\d{3})_[a-z0-9_]+\.sql$")
ADVISORY_LOCK_ID = 4_607_050_105


class MigrationError(RuntimeError):
    pass


@dataclass(frozen=True)
class Migration:
    version: int
    filename: str
    checksum: str
    sql: str


def discover_migrations(directory: Path) -> list[Migration]:
    migrations: list[Migration] = []
    versions: set[int] = set()
    for path in sorted(directory.glob("*.sql")):
        match = MIGRATION_PATTERN.fullmatch(path.name)
        if match is None:
            raise MigrationError(f"Malformed migration filename: {path.name}")
        version = int(match.group("version"))
        if version in versions:
            raise MigrationError(f"Duplicate migration version: {version:03d}")
        versions.add(version)
        raw = path.read_bytes()
        migrations.append(
            Migration(
                version=version,
                filename=path.name,
                checksum=hashlib.sha256(raw).hexdigest(),
                sql=raw.decode("utf-8"),
            )
        )
    return sorted(migrations, key=lambda item: item.version)


class MigrationRunner:
    def __init__(self, engine: Engine, directory: Path, *, use_advisory_lock: bool = True) -> None:
        self.engine = engine
        self.directory = directory
        self.use_advisory_lock = use_advisory_lock

    def run(self) -> list[str]:
        migrations = discover_migrations(self.directory)
        applied_now: list[str] = []

        with self.engine.connect() as connection:
            lock_acquired = False
            try:
                if self.use_advisory_lock:
                    connection.execute(
                        text("SELECT pg_advisory_lock(:lock_id)"),
                        {"lock_id": ADVISORY_LOCK_ID},
                    )
                    connection.commit()
                    lock_acquired = True

                with connection.begin():
                    connection.exec_driver_sql(
                        """
                        CREATE TABLE IF NOT EXISTS schema_migrations (
                            version INTEGER PRIMARY KEY,
                            filename TEXT NOT NULL,
                            checksum TEXT NOT NULL,
                            applied_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
                        )
                        """
                    )

                applied_rows = connection.execute(
                    text("SELECT version, filename, checksum FROM schema_migrations")
                ).mappings()
                applied = {row["version"]: row for row in applied_rows}
                connection.commit()

                for migration in migrations:
                    existing = applied.get(migration.version)
                    if existing is not None:
                        if (
                            existing["filename"] != migration.filename
                            or existing["checksum"] != migration.checksum
                        ):
                            raise MigrationError(
                                f"Applied migration {migration.version:03d} has changed."
                            )
                        continue

                    with connection.begin():
                        connection.exec_driver_sql(migration.sql)
                        connection.execute(
                            text(
                                "INSERT INTO schema_migrations "
                                "(version, filename, checksum) "
                                "VALUES (:version, :filename, :checksum)"
                            ),
                            {
                                "version": migration.version,
                                "filename": migration.filename,
                                "checksum": migration.checksum,
                            },
                        )
                    applied_now.append(migration.filename)
            finally:
                if lock_acquired:
                    connection.execute(
                        text("SELECT pg_advisory_unlock(:lock_id)"),
                        {"lock_id": ADVISORY_LOCK_ID},
                    )
                    connection.commit()

        return applied_now


def default_migration_directory() -> Path:
    container_path = Path("/app/migrations")
    if container_path.is_dir():
        return container_path
    return Path(__file__).resolve().parents[2] / "database" / "migrations"


def run_configured_migrations(database_url: str | None = None) -> list[str]:
    database_url = database_url or os.environ.get("DATABASE_URL", "")
    if not database_url:
        raise MigrationError("DATABASE_URL is required.")
    if make_url(database_url).get_backend_name() != "postgresql":
        raise MigrationError("Migrations require a PostgreSQL DATABASE_URL.")
    engine = create_engine(database_url, pool_pre_ping=True)
    try:
        return MigrationRunner(engine, default_migration_directory()).run()
    finally:
        engine.dispose()


def main() -> int:
    try:
        applied = run_configured_migrations()
    except (MigrationError, SQLAlchemyError, OSError, UnicodeError) as exc:
        print(f"Migration failed: {exc}", file=sys.stderr)
        return 1

    if applied:
        for filename in applied:
            print(f"Applied {filename}")
    else:
        print("No pending migrations.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
