from sqlalchemy import create_engine, text

from scripts.run_simulated_test import upgrade_local_ledger


def test_local_preview_upgrade_preserves_existing_transaction(tmp_path) -> None:
    engine = create_engine(f"sqlite+pysqlite:///{tmp_path / 'preview.db'}")
    with engine.begin() as connection:
        connection.exec_driver_sql(
            "CREATE TABLE transactions (id INTEGER PRIMARY KEY, amount NUMERIC NOT NULL)"
        )
        connection.exec_driver_sql("INSERT INTO transactions (id, amount) VALUES (7, 18.00)")

    upgrade_local_ledger(engine)
    upgrade_local_ledger(engine)
    with engine.connect() as connection:
        row = connection.execute(
            text("SELECT id, amount, version, voided_at FROM transactions WHERE id = 7")
        ).one()
    assert row == (7, 18, 1, None)
    engine.dispose()
