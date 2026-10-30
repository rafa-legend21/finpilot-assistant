from __future__ import annotations

import hashlib
import os
import re
import shutil
from collections.abc import Iterator
from dataclasses import dataclass
from pathlib import Path
from uuid import uuid4

import pytest
from sqlalchemy import Connection, Engine, create_engine, text
from sqlalchemy.exc import IntegrityError, OperationalError, SQLAlchemyError

from scripts.run_migrations import (
    MigrationRunner,
    default_migration_directory,
    discover_migrations,
)

MIGRATION_DIRECTORY = default_migration_directory()
EXPECTED_MIGRATION_CHECKSUMS = {
    1: "5fd14801f256494bf39a4e5e586e155d00cadbcb7eb67abb6550af3a2c5e956a",
    2: "41a090fdc08e1c6673fa381865f84c3498789c8d4370dcd2cc9a6c46a54ea756",
    3: "98a9474f41fd98879ddd9aa3f9a5cb7e01b6732ef65d8093900f7c3f7c330058",
    4: "b99fa0efda24f354ecc16d5848e4fb65fb0a8eea4e4a2ba7cbf7a72684205a22",
    5: "d6807d16c88071708df511c5be23f09638963b9f92c828e973e50d1236925ac3",
}
EXPECTED_ROUND_EXPRESSION = "((round_number >= 1) AND (round_number <= 3))"
TEST_SCHEMA_PATTERN = re.compile(r"^test_schema_repair_[0-9a-f]{32}$")
CREATE_EXTENSION_PATTERN = re.compile(
    r'\bCREATE\s+EXTENSION\s+(?:IF\s+NOT\s+EXISTS\s+)?'
    r'(?:(?:"([^"]+)")|([a-z_][a-z0-9_$]*))',
    re.IGNORECASE,
)
UNSUPPORTED_DATABASE_GLOBAL_PATTERN = re.compile(
    r"\b(?:CREATE|ALTER|DROP)\s+(?:DATABASE|ROLE|USER|TABLESPACE)\b"
    r"|\bALTER\s+SYSTEM\b"
    r"|\b(?:ALTER|DROP)\s+EXTENSION\b",
    re.IGNORECASE,
)
DRAFT_ID = "10000000-0000-0000-0000-000000000001"
EVENT_ID = "20000000-0000-0000-0000-000000000001"
CLARIFICATION_ID_1 = "30000000-0000-0000-0000-000000000001"
CLARIFICATION_ID_2 = "30000000-0000-0000-0000-000000000002"


@dataclass(frozen=True)
class IsolatedPostgres:
    engine: Engine
    schema: str


def _public_evidence(engine: Engine) -> tuple[object, ...]:
    with engine.connect() as connection:
        migration_table = connection.scalar(text("SELECT to_regclass('public.schema_migrations')"))
        clarification_table = connection.scalar(
            text("SELECT to_regclass('public.financial_draft_clarifications')")
        )
        transaction_table = connection.scalar(text("SELECT to_regclass('public.transactions')"))

        migrations = (
            tuple(
                connection.execute(
                    text(
                        "SELECT version, filename, checksum, applied_at "
                        "FROM public.schema_migrations ORDER BY version"
                    )
                ).all()
            )
            if migration_table is not None
            else None
        )
        clarification_count = (
            connection.scalar(
                text("SELECT COUNT(*) FROM public.financial_draft_clarifications")
            )
            if clarification_table is not None
            else None
        )
        transaction_count = (
            connection.scalar(text("SELECT COUNT(*) FROM public.transactions"))
            if transaction_table is not None
            else None
        )
        extensions = tuple(
            connection.execute(
                text(
                    "SELECT extension.extname, extension.extversion, namespace.nspname "
                    "FROM pg_extension extension "
                    "JOIN pg_namespace namespace "
                    "ON namespace.oid = extension.extnamespace "
                    "ORDER BY extension.extname"
                )
            ).all()
        )
    return migrations, clarification_count, transaction_count, extensions


def _migration_global_requirements() -> tuple[frozenset[str], tuple[str, ...]]:
    required_extensions: set[str] = set()
    unsupported_operations: list[str] = []
    for migration in discover_migrations(MIGRATION_DIRECTORY):
        for match in CREATE_EXTENSION_PATTERN.finditer(migration.sql):
            required_extensions.add(match.group(1) or match.group(2))
        unsupported_operations.extend(
            match.group(0)
            for match in UNSUPPORTED_DATABASE_GLOBAL_PATTERN.finditer(migration.sql)
        )
    return frozenset(required_extensions), tuple(unsupported_operations)


def _assert_required_extensions_exist(
    engine: Engine,
    required_extensions: frozenset[str],
) -> None:
    if not required_extensions:
        return
    with engine.connect() as connection:
        installed_extensions = frozenset(
            connection.execute(text("SELECT extname FROM pg_extension")).scalars()
        )
    missing_extensions = sorted(required_extensions - installed_extensions)
    if missing_extensions:
        pytest.skip(
            "Required PostgreSQL extension(s) must be installed before migration tests: "
            + ", ".join(missing_extensions)
        )


def _assert_test_objects_are_isolated(engine: Engine, schema: str) -> None:
    expected_relations = {
        "schema_migrations",
        "financial_drafts",
        "financial_draft_events",
        "financial_draft_clarifications",
        "transactions",
    }
    with engine.connect() as connection:
        assert connection.scalar(text("SELECT current_schema()")) == schema
        assert connection.scalar(text("SHOW search_path")) == schema
        rows = connection.execute(
            text(
                "SELECT requested.name, namespace.nspname "
                "FROM unnest(CAST(:relation_names AS TEXT[])) requested(name) "
                "JOIN pg_class relation ON relation.oid = to_regclass(requested.name) "
                "JOIN pg_namespace namespace ON namespace.oid = relation.relnamespace "
                "WHERE relation.relkind IN ('r', 'p')"
            ),
            {"relation_names": sorted(expected_relations)},
        ).all()
    assert all(relation_schema == schema for _, relation_schema in rows)


@pytest.fixture
def isolated_postgres() -> Iterator[IsolatedPostgres]:
    database_url = os.environ.get("TEST_DATABASE_URL")
    if not database_url:
        pytest.skip("PostgreSQL TEST_DATABASE_URL is required for schema repair integration tests")

    admin_engine = create_engine(database_url, pool_pre_ping=True)
    try:
        try:
            with admin_engine.connect() as connection:
                connection.execute(text("SELECT 1"))
        except OperationalError as exc:
            pytest.skip(f"PostgreSQL TEST_DATABASE_URL is unavailable: {exc}")

        required_extensions, unsupported_operations = _migration_global_requirements()
        if unsupported_operations:
            pytest.fail(
                "Migrations contain unsupported database-global operation(s): "
                + ", ".join(unsupported_operations)
            )
        _assert_required_extensions_exist(admin_engine, required_extensions)
        before_public = _public_evidence(admin_engine)
        schema = f"test_schema_repair_{uuid4().hex}"
        assert TEST_SCHEMA_PATTERN.fullmatch(schema)

        with admin_engine.begin() as connection:
            connection.exec_driver_sql(f'CREATE SCHEMA "{schema}"')

        isolated_engine = create_engine(
            database_url,
            pool_pre_ping=True,
            connect_args={"options": f"-csearch_path={schema}"},
        )
        try:
            with isolated_engine.begin() as connection:
                assert connection.scalar(text("SELECT current_schema()")) == schema
                assert connection.scalar(text("SHOW search_path")) == schema
                connection.exec_driver_sql("CREATE TABLE isolation_probe (id INTEGER)")
                probe_schema = connection.scalar(
                    text(
                        "SELECT namespace.nspname "
                        "FROM pg_class relation "
                        "JOIN pg_namespace namespace ON namespace.oid = relation.relnamespace "
                        "WHERE relation.oid = 'isolation_probe'::regclass"
                    )
                )
                assert probe_schema == schema
                connection.exec_driver_sql("DROP TABLE isolation_probe")

            yield IsolatedPostgres(engine=isolated_engine, schema=schema)
        finally:
            try:
                _assert_test_objects_are_isolated(isolated_engine, schema)
            finally:
                isolated_engine.dispose()
                try:
                    if not TEST_SCHEMA_PATTERN.fullmatch(schema):
                        pytest.fail(f"Refusing to drop unexpected schema name: {schema}")
                    with admin_engine.begin() as connection:
                        connection.exec_driver_sql(f'DROP SCHEMA "{schema}" CASCADE')
                finally:
                    after_public = _public_evidence(admin_engine)
                    assert after_public == before_public, (
                        "Public schema or PostgreSQL extension state changed during an "
                        "isolated migration test"
                    )
    finally:
        admin_engine.dispose()


def test_migrations_have_no_database_global_operations() -> None:
    required_extensions, unsupported_operations = _migration_global_requirements()

    assert required_extensions == frozenset()
    assert unsupported_operations == ()


def test_migration_files_are_lf_only_with_expected_checksums() -> None:
    migrations = discover_migrations(MIGRATION_DIRECTORY)

    assert {migration.version for migration in migrations} == set(
        EXPECTED_MIGRATION_CHECKSUMS
    )

    for migration in migrations:
        raw = (MIGRATION_DIRECTORY / migration.filename).read_bytes()
        crlf_count = raw.count(b"\r\n")
        lone_cr_count = raw.replace(b"\r\n", b"").count(b"\r")

        assert crlf_count == 0, (
            f"{migration.filename} contains {crlf_count} CRLF line ending(s)"
        )
        assert lone_cr_count == 0, (
            f"{migration.filename} contains {lone_cr_count} lone CR byte(s)"
        )
        assert raw.endswith(b"\n"), f"{migration.filename} must end with one LF newline"
        assert migration.sql.encode("utf-8") == raw
        assert migration.checksum == hashlib.sha256(raw).hexdigest()
        assert migration.checksum == EXPECTED_MIGRATION_CHECKSUMS[migration.version]


def _copy_migrations(directory: Path, versions: tuple[int, ...]) -> Path:
    directory.mkdir()
    migrations = {item.version: item for item in discover_migrations(MIGRATION_DIRECTORY)}
    for version in versions:
        migration = migrations[version]
        shutil.copyfile(MIGRATION_DIRECTORY / migration.filename, directory / migration.filename)
    return directory


def _apply_001_and_002(engine: Engine, tmp_path: Path) -> None:
    directory = _copy_migrations(tmp_path / "base_migrations", (1, 2))
    assert MigrationRunner(engine, directory, use_advisory_lock=False).run() == [
        "001_financial_drafts.sql",
        "002_draft_clarifications.sql",
    ]


def _make_schema_drifted(engine: Engine, tmp_path: Path) -> None:
    _apply_001_and_002(engine, tmp_path)
    with engine.begin() as connection:
        connection.exec_driver_sql(
            """
            ALTER TABLE financial_draft_clarifications
                DROP CONSTRAINT uq_draft_clarification_sequence,
                DROP CONSTRAINT uq_draft_clarification_semantic_key,
                DROP CONSTRAINT ck_draft_clarification_round,
                ALTER COLUMN id DROP DEFAULT,
                ALTER COLUMN status DROP DEFAULT,
                ALTER COLUMN options_payload TYPE JSON USING options_payload::JSON,
                ALTER COLUMN answer_payload TYPE JSON USING answer_payload::JSON;

            ALTER TABLE transactions
                ALTER COLUMN currency DROP DEFAULT,
                ALTER COLUMN category DROP DEFAULT;
            """
        )


def _insert_base_data(engine: Engine) -> None:
    with engine.begin() as connection:
        connection.execute(
            text(
                """
                INSERT INTO financial_drafts (
                    id, original_snapshot, working_metadata, original_journal
                ) VALUES (
                    CAST(:draft_id AS UUID), CAST(:snapshot AS JSONB),
                    CAST(:metadata AS JSONB), :journal
                )
                """
            ),
            {
                "draft_id": DRAFT_ID,
                "snapshot": '{"total_user_expense": "18"}',
                "metadata": '{"summary": "Coffee beans"}',
                "journal": "I bought coffee beans for 18 CAD, but my mother paid for them.",
            },
        )
        connection.execute(
            text(
                """
                INSERT INTO financial_draft_events (
                    id, draft_id, position, event_payload
                ) VALUES (
                    CAST(:event_id AS UUID), CAST(:draft_id AS UUID), 0,
                    CAST(:payload AS JSONB)
                )
                """
            ),
            {
                "event_id": EVENT_ID,
                "draft_id": DRAFT_ID,
                "payload": '{"user_net_amount": "18", "currency": "CAD"}',
            },
        )
        _insert_clarification(
            connection,
            clarification_id=CLARIFICATION_ID_1,
            sequence=1,
            semantic_key="settlement:coffee",
            round_number=1,
            answer_payload=None,
        )
        _insert_clarification(
            connection,
            clarification_id=CLARIFICATION_ID_2,
            sequence=2,
            semantic_key="history:coffee",
            round_number=2,
            answer_payload='{"option_key": "repaid_by_user"}',
        )
        connection.execute(
            text(
                """
                INSERT INTO transactions (
                    merchant, amount, currency, category, transaction_date,
                    source_draft_id, source_event_id
                ) VALUES (
                    'Coffee shop', 18.00, 'CAD', 'Other', DATE '2026-08-23',
                    CAST(:draft_id AS UUID), CAST(:event_id AS UUID)
                )
                """
            ),
            {"draft_id": DRAFT_ID, "event_id": EVENT_ID},
        )


def _insert_clarification(
    connection: Connection,
    *,
    clarification_id: str,
    sequence: int,
    semantic_key: str,
    round_number: int,
    answer_payload: str | None,
) -> None:
    connection.execute(
        text(
            """
            INSERT INTO financial_draft_clarifications (
                id, draft_id, sequence, round_number, semantic_key,
                requirement, issue_type, status, question, reason,
                related_event_id, related_source_text, options_payload,
                answer_payload
            ) VALUES (
                CAST(:id AS UUID), CAST(:draft_id AS UUID), :sequence,
                :round_number, :semantic_key, 'required',
                'payer_responsibility', 'open', 'What happened?',
                'Settlement determines responsibility.', CAST(:event_id AS UUID),
                'Mother paid for coffee beans.', CAST(:options AS JSON),
                CAST(:answer AS JSON)
            )
            """
        ),
        {
            "id": clarification_id,
            "draft_id": DRAFT_ID,
            "sequence": sequence,
            "round_number": round_number,
            "semantic_key": semantic_key,
            "event_id": EVENT_ID,
            "options": '[{"option_key": "repaid_by_user"}]',
            "answer": answer_payload,
        },
    )


def _column_details(engine: Engine, table: str, column: str) -> tuple[str, str | None]:
    with engine.connect() as connection:
        row = connection.execute(
            text(
                """
                SELECT data_type, column_default
                FROM information_schema.columns
                WHERE table_schema = current_schema()
                  AND table_name = :table
                  AND column_name = :column
                """
            ),
            {"table": table, "column": column},
        ).one()
    return row.data_type, row.column_default


def _transaction_column_definitions(engine: Engine) -> dict[str, tuple[object, ...]]:
    with engine.connect() as connection:
        rows = connection.execute(
            text(
                """
                SELECT
                    column_name,
                    data_type,
                    character_maximum_length,
                    is_nullable,
                    column_default
                FROM information_schema.columns
                WHERE table_schema = current_schema()
                  AND table_name = 'transactions'
                ORDER BY ordinal_position
                """
            )
        ).mappings()
        return {
            row["column_name"]: (
                row["data_type"],
                row["character_maximum_length"],
                row["is_nullable"],
                row["column_default"],
            )
            for row in rows
        }


def _transaction_constraint_definitions(engine: Engine) -> tuple[tuple[object, ...], ...]:
    with engine.connect() as connection:
        return tuple(
            connection.execute(
                text(
                    """
                    SELECT
                        constraint_row.conname,
                        constraint_row.contype,
                        constraint_row.convalidated,
                        pg_get_constraintdef(constraint_row.oid)
                    FROM pg_constraint AS constraint_row
                    WHERE constraint_row.conrelid = 'transactions'::REGCLASS
                    ORDER BY constraint_row.conname
                    """
                )
            ).all()
        )


def _transaction_index_definitions(engine: Engine) -> tuple[tuple[str, str], ...]:
    with engine.connect() as connection:
        return tuple(
            connection.execute(
                text(
                    """
                    SELECT index_relation.relname, pg_get_indexdef(index_relation.oid)
                    FROM pg_index AS index_row
                    JOIN pg_class AS index_relation
                      ON index_relation.oid = index_row.indexrelid
                    WHERE index_row.indrelid = 'transactions'::REGCLASS
                    ORDER BY index_relation.relname
                    """
                )
            ).tuples()
        )


def _table_digest(engine: Engine, table: str) -> str:
    if table not in {"financial_draft_clarifications", "transactions"}:
        raise ValueError(f"Unsupported digest table: {table}")
    with engine.connect() as connection:
        digest = connection.scalar(
            text(
                f"""
                SELECT md5(
                    COALESCE(
                        jsonb_agg(to_jsonb(snapshot) ORDER BY snapshot.id)::TEXT,
                        '[]'
                    )
                )
                FROM (SELECT * FROM {table}) AS snapshot
                """
            )
        )
    assert digest is not None
    return digest


def _assert_nullable_merchant_policy(engine: Engine) -> None:
    columns = _transaction_column_definitions(engine)
    assert columns["merchant"] == ("character varying", 150, "YES", None)
    assert columns["transaction_date"] == ("date", None, "NO", None)


def _constraint_details(engine: Engine) -> dict[str, dict[str, object]]:
    with engine.connect() as connection:
        rows = connection.execute(
            text(
                """
                SELECT
                    constraint_row.conname,
                    constraint_row.contype,
                    constraint_row.convalidated,
                    constraint_row.condeferrable,
                    constraint_row.condeferred,
                    constraint_row.connoinherit,
                    ARRAY(
                        SELECT attribute.attname
                        FROM unnest(constraint_row.conkey) WITH ORDINALITY keys(attnum, ordering)
                        JOIN pg_attribute attribute
                          ON attribute.attrelid = constraint_row.conrelid
                         AND attribute.attnum = keys.attnum
                        ORDER BY keys.ordering
                    ) AS columns,
                    pg_get_expr(constraint_row.conbin, constraint_row.conrelid) AS expression
                FROM pg_constraint constraint_row
                WHERE constraint_row.conrelid =
                    'financial_draft_clarifications'::regclass
                  AND constraint_row.conname IN (
                    'uq_draft_clarification_sequence',
                    'uq_draft_clarification_semantic_key',
                    'ck_draft_clarification_round'
                  )
                """
            )
        ).mappings()
        return {row["conname"]: dict(row) for row in rows}


def _assert_repaired_constraints(engine: Engine) -> None:
    constraints = _constraint_details(engine)
    assert constraints["uq_draft_clarification_sequence"] == {
        "conname": "uq_draft_clarification_sequence",
        "contype": "u",
        "convalidated": True,
        "condeferrable": False,
        "condeferred": False,
        "connoinherit": True,
        "columns": ["draft_id", "sequence"],
        "expression": None,
    }
    assert constraints["uq_draft_clarification_semantic_key"] == {
        "conname": "uq_draft_clarification_semantic_key",
        "contype": "u",
        "convalidated": True,
        "condeferrable": False,
        "condeferred": False,
        "connoinherit": True,
        "columns": ["draft_id", "semantic_key"],
        "expression": None,
    }
    assert constraints["ck_draft_clarification_round"] == {
        "conname": "ck_draft_clarification_round",
        "contype": "c",
        "convalidated": True,
        "condeferrable": False,
        "condeferred": False,
        "connoinherit": False,
        "columns": ["round_number"],
        "expression": EXPECTED_ROUND_EXPRESSION,
    }


def test_repairs_drifted_schema_and_preserves_rows(
    isolated_postgres: IsolatedPostgres,
    tmp_path: Path,
) -> None:
    engine = isolated_postgres.engine
    _make_schema_drifted(engine, tmp_path)
    _insert_base_data(engine)

    with engine.connect() as connection:
        before_clarifications = connection.execute(
            text(
                "SELECT id, sequence, semantic_key, options_payload, answer_payload "
                "FROM financial_draft_clarifications ORDER BY sequence"
            )
        ).mappings().all()
        before_transactions = connection.execute(
            text(
                "SELECT id, amount, currency, category, source_draft_id, source_event_id "
                "FROM transactions ORDER BY id"
            )
        ).all()

    through_004 = _copy_migrations(tmp_path / "through_004", (1, 2, 3, 4))
    runner = MigrationRunner(engine, through_004, use_advisory_lock=False)
    assert runner.run() == [
        "003_repair_schema_drift.sql",
        "004_allow_unknown_transaction_merchant.sql",
    ]
    assert runner.run() == []

    with engine.connect() as connection:
        after_clarifications = connection.execute(
            text(
                "SELECT id, sequence, semantic_key, options_payload, answer_payload "
                "FROM financial_draft_clarifications ORDER BY sequence"
            )
        ).mappings().all()
        after_transactions = connection.execute(
            text(
                "SELECT id, amount, currency, category, source_draft_id, source_event_id "
                "FROM transactions ORDER BY id"
            )
        ).all()

    assert after_clarifications == before_clarifications
    assert after_clarifications[0]["answer_payload"] is None
    assert after_clarifications[1]["answer_payload"] == {"option_key": "repaid_by_user"}
    assert after_transactions == before_transactions
    assert _column_details(engine, "financial_draft_clarifications", "options_payload")[0] == "jsonb"
    assert _column_details(engine, "financial_draft_clarifications", "answer_payload")[0] == "jsonb"
    _assert_repaired_constraints(engine)
    _assert_nullable_merchant_policy(engine)

    migration = discover_migrations(MIGRATION_DIRECTORY)[2]
    with engine.connect() as connection:
        recorded = connection.execute(
            text(
                "SELECT version, filename, checksum FROM schema_migrations WHERE version = 3"
            )
        ).one()
    assert recorded == (3, migration.filename, migration.checksum)


def test_fresh_schema_applies_all_migrations_and_remains_correct(
    isolated_postgres: IsolatedPostgres,
) -> None:
    runner = MigrationRunner(
        isolated_postgres.engine,
        MIGRATION_DIRECTORY,
        use_advisory_lock=False,
    )
    assert runner.run() == [
        "001_financial_drafts.sql",
        "002_draft_clarifications.sql",
        "003_repair_schema_drift.sql",
        "004_allow_unknown_transaction_merchant.sql",
        "005_transaction_corrections.sql",
    ]
    assert runner.run() == []
    _assert_repaired_constraints(isolated_postgres.engine)
    _assert_nullable_merchant_policy(isolated_postgres.engine)


def test_transaction_correction_migration_preserves_existing_expenses(
    isolated_postgres: IsolatedPostgres,
    tmp_path: Path,
) -> None:
    engine = isolated_postgres.engine
    through_004 = _copy_migrations(tmp_path / "through_004", (1, 2, 3, 4))
    MigrationRunner(engine, through_004, use_advisory_lock=False).run()
    _insert_base_data(engine)
    with engine.connect() as connection:
        before = connection.execute(
            text(
                "SELECT id, amount, currency, category, source_draft_id, source_event_id "
                "FROM transactions ORDER BY id"
            )
        ).all()

    runner = MigrationRunner(engine, MIGRATION_DIRECTORY, use_advisory_lock=False)
    assert runner.run() == ["005_transaction_corrections.sql"]
    assert runner.run() == []
    with engine.connect() as connection:
        after = connection.execute(
            text(
                "SELECT id, amount, currency, category, source_draft_id, source_event_id "
                "FROM transactions ORDER BY id"
            )
        ).all()
        version_and_void = connection.execute(
            text("SELECT version, voided_at FROM transactions ORDER BY id")
        ).all()
        correction_count = connection.scalar(text("SELECT COUNT(*) FROM transaction_corrections"))
    assert after == before
    assert all(version == 1 and voided_at is None for version, voided_at in version_and_void)
    assert correction_count == 0


def test_nullable_merchant_migration_upgrades_003_schema_without_data_loss(
    isolated_postgres: IsolatedPostgres,
    tmp_path: Path,
) -> None:
    engine = isolated_postgres.engine
    through_003 = _copy_migrations(tmp_path / "through_003", (1, 2, 3))
    assert MigrationRunner(engine, through_003, use_advisory_lock=False).run() == [
        "001_financial_drafts.sql",
        "002_draft_clarifications.sql",
        "003_repair_schema_drift.sql",
    ]
    _insert_base_data(engine)
    with engine.begin() as connection:
        connection.exec_driver_sql(
            """
            CREATE INDEX ix_transactions_id ON transactions (id);
            CREATE INDEX ix_transactions_merchant ON transactions (merchant);
            CREATE INDEX ix_transactions_category ON transactions (category);
            CREATE INDEX ix_transactions_transaction_date
                ON transactions (transaction_date);
            """
        )

    with engine.connect() as connection:
        before_clarifications = connection.execute(
            text("SELECT * FROM financial_draft_clarifications ORDER BY id")
        ).mappings().all()
        before_transactions = connection.execute(
            text("SELECT * FROM transactions ORDER BY id")
        ).mappings().all()
    before_digests = {
        "clarifications": _table_digest(engine, "financial_draft_clarifications"),
        "transactions": _table_digest(engine, "transactions"),
    }
    before_columns = _transaction_column_definitions(engine)
    before_constraints = _transaction_constraint_definitions(engine)
    before_indexes = _transaction_index_definitions(engine)
    assert before_columns["merchant"] == ("character varying", 150, "NO", None)
    assert {
        "ix_transactions_id",
        "ix_transactions_merchant",
        "ix_transactions_category",
        "ix_transactions_transaction_date",
    }.issubset({name for name, _ in before_indexes})

    through_004 = _copy_migrations(tmp_path / "through_004", (1, 2, 3, 4))
    runner = MigrationRunner(engine, through_004, use_advisory_lock=False)
    assert runner.run() == ["004_allow_unknown_transaction_merchant.sql"]
    assert runner.run() == []

    with engine.connect() as connection:
        after_clarifications = connection.execute(
            text("SELECT * FROM financial_draft_clarifications ORDER BY id")
        ).mappings().all()
        after_transactions = connection.execute(
            text("SELECT * FROM transactions ORDER BY id")
        ).mappings().all()
    assert after_clarifications == before_clarifications
    assert after_transactions == before_transactions
    assert {
        "clarifications": _table_digest(engine, "financial_draft_clarifications"),
        "transactions": _table_digest(engine, "transactions"),
    } == before_digests

    expected_columns = dict(before_columns)
    merchant_definition = list(expected_columns["merchant"])
    merchant_definition[2] = "YES"
    expected_columns["merchant"] = tuple(merchant_definition)
    assert _transaction_column_definitions(engine) == expected_columns
    assert _transaction_constraint_definitions(engine) == before_constraints
    assert _transaction_index_definitions(engine) == before_indexes
    _assert_nullable_merchant_policy(engine)

    migration = next(
        item for item in discover_migrations(MIGRATION_DIRECTORY) if item.version == 4
    )
    with engine.connect() as connection:
        recorded = connection.execute(
            text(
                "SELECT version, filename, checksum "
                "FROM schema_migrations WHERE version = 4"
            )
        ).one()
    assert recorded == (4, migration.filename, migration.checksum)


def test_nullable_merchant_is_allowed_but_transaction_date_remains_required(
    isolated_postgres: IsolatedPostgres,
) -> None:
    engine = isolated_postgres.engine
    MigrationRunner(engine, MIGRATION_DIRECTORY, use_advisory_lock=False).run()

    with engine.begin() as connection:
        inserted = connection.execute(
            text(
                """
                INSERT INTO transactions (amount, transaction_date)
                VALUES (4.50, DATE '2026-08-24')
                RETURNING merchant, transaction_date
                """
            )
        ).one()
    assert inserted.merchant is None
    assert inserted.transaction_date.isoformat() == "2026-08-24"

    with pytest.raises(IntegrityError), engine.begin() as connection:
        connection.execute(
            text("INSERT INTO transactions (merchant, amount) VALUES (NULL, 5.00)")
        )

    with engine.connect() as connection:
        assert connection.scalar(text("SELECT COUNT(*) FROM transactions")) == 1
    _assert_nullable_merchant_policy(engine)


def test_restored_defaults_and_constraints_are_enforced(
    isolated_postgres: IsolatedPostgres,
    tmp_path: Path,
) -> None:
    engine = isolated_postgres.engine
    _make_schema_drifted(engine, tmp_path)
    _insert_base_data(engine)
    MigrationRunner(engine, MIGRATION_DIRECTORY, use_advisory_lock=False).run()

    with engine.begin() as connection:
        generated = connection.execute(
            text(
                """
                INSERT INTO financial_draft_clarifications (
                    draft_id, sequence, round_number, semantic_key, requirement,
                    issue_type, question, reason, related_source_text, options_payload
                ) VALUES (
                    CAST(:draft_id AS UUID), 3, 3, 'default:test', 'required',
                    'other', 'Question', 'Reason', 'Source', CAST('[]' AS JSONB)
                )
                RETURNING id, status
                """
            ),
            {"draft_id": DRAFT_ID},
        ).one()
        transaction = connection.execute(
            text(
                """
                INSERT INTO transactions (merchant, amount, transaction_date)
                VALUES ('Direct insert', 1.25, DATE '2026-08-23')
                RETURNING currency, category
                """
            )
        ).one()
    assert generated.id is not None
    assert generated.status == "open"
    assert transaction == ("CAD", "Other")

    invalid_rows = (
        (4, "settlement:coffee", 1),
        (1, "new:semantic", 1),
        (5, "round:zero", 0),
        (6, "round:four", 4),
    )
    for sequence, semantic_key, round_number in invalid_rows:
        with pytest.raises(IntegrityError), engine.begin() as connection:
            _insert_clarification(
                connection,
                clarification_id=str(uuid4()),
                sequence=sequence,
                semantic_key=semantic_key,
                round_number=round_number,
                answer_payload=None,
            )


@pytest.mark.parametrize(
    ("bad_data", "message"),
    [
        ("sequence", "uq_draft_clarification_sequence"),
        ("semantic", "uq_draft_clarification_semantic_key"),
        ("round", "ck_draft_clarification_round"),
    ],
)
def test_invalid_existing_data_rejects_and_rolls_back_migration(
    isolated_postgres: IsolatedPostgres,
    tmp_path: Path,
    bad_data: str,
    message: str,
) -> None:
    engine = isolated_postgres.engine
    _make_schema_drifted(engine, tmp_path)
    _insert_base_data(engine)
    values = {
        "sequence": (1, "duplicate:sequence", 1),
        "semantic": (3, "settlement:coffee", 1),
        "round": (3, "invalid:round", 0),
    }
    sequence, semantic_key, round_number = values[bad_data]
    with engine.begin() as connection:
        _insert_clarification(
            connection,
            clarification_id=str(uuid4()),
            sequence=sequence,
            semantic_key=semantic_key,
            round_number=round_number,
            answer_payload=None,
        )

    with pytest.raises(SQLAlchemyError, match=message):
        MigrationRunner(engine, MIGRATION_DIRECTORY, use_advisory_lock=False).run()

    assert _column_details(engine, "financial_draft_clarifications", "options_payload") == (
        "json",
        None,
    )
    assert _column_details(engine, "financial_draft_clarifications", "id")[1] is None
    with engine.connect() as connection:
        assert connection.scalar(
            text("SELECT COUNT(*) FROM schema_migrations WHERE version = 3")
        ) == 0


@pytest.mark.parametrize(
    ("constraint_sql", "message"),
    [
        (
            (
                "ALTER TABLE financial_draft_clarifications "
                "ADD CONSTRAINT uq_draft_clarification_sequence "
                "UNIQUE (draft_id, semantic_key)"
            ),
            "uq_draft_clarification_sequence.*incompatible",
        ),
        (
            (
                "ALTER TABLE financial_draft_clarifications "
                "ADD CONSTRAINT uq_draft_clarification_semantic_key "
                "UNIQUE (draft_id, sequence)"
            ),
            "uq_draft_clarification_semantic_key.*incompatible",
        ),
        (
            (
                "ALTER TABLE financial_draft_clarifications "
                "ADD CONSTRAINT ck_draft_clarification_round "
                "CHECK (round_number BETWEEN 0 AND 3)"
            ),
            "ck_draft_clarification_round.*incompatible",
        ),
    ],
)
def test_same_named_incompatible_constraint_is_rejected_without_replacement(
    isolated_postgres: IsolatedPostgres,
    tmp_path: Path,
    constraint_sql: str,
    message: str,
) -> None:
    engine = isolated_postgres.engine
    _make_schema_drifted(engine, tmp_path)
    with engine.begin() as connection:
        connection.exec_driver_sql(constraint_sql)
        before = connection.scalar(
            text(
                "SELECT pg_get_constraintdef(oid) FROM pg_constraint "
                "WHERE conrelid = 'financial_draft_clarifications'::regclass "
                "AND conname = split_part(:message, '.', 1)"
            ),
            {"message": message},
        )

    with pytest.raises(SQLAlchemyError, match=message):
        MigrationRunner(engine, MIGRATION_DIRECTORY, use_advisory_lock=False).run()

    with engine.connect() as connection:
        after = connection.scalar(
            text(
                "SELECT pg_get_constraintdef(oid) FROM pg_constraint "
                "WHERE conrelid = 'financial_draft_clarifications'::regclass "
                "AND conname = split_part(:message, '.', 1)"
            ),
            {"message": message},
        )
        assert connection.scalar(
            text("SELECT COUNT(*) FROM schema_migrations WHERE version = 3")
        ) == 0
    assert after == before
    assert _column_details(engine, "financial_draft_clarifications", "options_payload")[0] == "json"


def test_correct_unvalidated_round_constraint_is_validated(
    isolated_postgres: IsolatedPostgres,
    tmp_path: Path,
) -> None:
    engine = isolated_postgres.engine
    _make_schema_drifted(engine, tmp_path)
    with engine.begin() as connection:
        connection.exec_driver_sql(
            "ALTER TABLE financial_draft_clarifications "
            "ADD CONSTRAINT ck_draft_clarification_round "
            "CHECK (round_number BETWEEN 1 AND 3) NOT VALID"
        )

    MigrationRunner(engine, MIGRATION_DIRECTORY, use_advisory_lock=False).run()
    _assert_repaired_constraints(engine)


@pytest.mark.parametrize("column", ["options_payload", "answer_payload"])
@pytest.mark.parametrize("failure", ["missing", "unexpected_type"])
def test_missing_or_unexpected_json_column_fails_clearly(
    isolated_postgres: IsolatedPostgres,
    tmp_path: Path,
    column: str,
    failure: str,
) -> None:
    engine = isolated_postgres.engine
    _make_schema_drifted(engine, tmp_path)
    with engine.begin() as connection:
        if failure == "missing":
            connection.exec_driver_sql(
                f"ALTER TABLE financial_draft_clarifications DROP COLUMN {column}"
            )
            expected = f"{column} is missing"
        else:
            connection.exec_driver_sql(
                f"ALTER TABLE financial_draft_clarifications "
                f"ALTER COLUMN {column} TYPE TEXT USING {column}::TEXT"
            )
            expected = f"{column} to be JSON or JSONB"

    with pytest.raises(SQLAlchemyError, match=expected):
        MigrationRunner(engine, MIGRATION_DIRECTORY, use_advisory_lock=False).run()

    with engine.connect() as connection:
        assert connection.scalar(
            text("SELECT COUNT(*) FROM schema_migrations WHERE version = 3")
        ) == 0
