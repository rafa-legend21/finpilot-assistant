"""Run a local-only API with an isolated database for synthetic user tests."""

import os
from pathlib import Path

import uvicorn


def main() -> None:
    backend_root = Path(__file__).resolve().parents[1]
    (backend_root / ".simulated-test").mkdir(exist_ok=True)
    os.chdir(backend_root)
    os.environ["DATABASE_URL"] = "sqlite+pysqlite:///./.simulated-test/finpilot.db"

    from app.db.base import Base
    from app.db.session import engine
    from app.models import financial_draft, transaction  # noqa: F401

    Base.metadata.create_all(engine)
    print("Simulated FinPilot API ready at http://127.0.0.1:8000/docs")
    uvicorn.run("app.main:app", host="127.0.0.1", port=8000)


if __name__ == "__main__":
    main()
