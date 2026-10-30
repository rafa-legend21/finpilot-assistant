"""Run a local-only API with an isolated database for synthetic user tests."""

import argparse
import os
from pathlib import Path

import uvicorn
from sqlalchemy import Engine, inspect


def upgrade_local_ledger(engine: Engine) -> None:
    """Add correction columns to older disposable SQLite previews without dropping rows."""
    inspector = inspect(engine)
    if "transactions" not in inspector.get_table_names():
        return
    columns = {column["name"] for column in inspector.get_columns("transactions")}
    with engine.begin() as connection:
        if "version" not in columns:
            connection.exec_driver_sql(
                "ALTER TABLE transactions ADD COLUMN version INTEGER NOT NULL DEFAULT 1"
            )
        if "voided_at" not in columns:
            connection.exec_driver_sql("ALTER TABLE transactions ADD COLUMN voided_at DATETIME")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--database-name", default="finpilot.db")
    parser.add_argument("--host", default="127.0.0.1")
    args = parser.parse_args()
    if Path(args.database_name).name != args.database_name or not args.database_name.endswith(
        ".db"
    ):
        parser.error("--database-name must be a .db filename")
    backend_root = Path(__file__).resolve().parents[1]
    (backend_root / ".simulated-test").mkdir(exist_ok=True)
    os.chdir(backend_root)
    os.environ["DATABASE_URL"] = f"sqlite+pysqlite:///./.simulated-test/{args.database_name}"

    from app.db.base import Base
    from app.db.session import engine
    from app.models import financial_draft, transaction  # noqa: F401

    upgrade_local_ledger(engine)
    Base.metadata.create_all(engine)
    print(f"Simulated FinPilot API ready at http://{args.host}:8000/docs")
    uvicorn.run("app.main:app", host=args.host, port=8000)


if __name__ == "__main__":
    main()
