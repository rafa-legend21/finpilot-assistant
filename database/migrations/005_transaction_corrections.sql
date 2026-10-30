-- Preserve every confirmed expense correction without deleting source records.
ALTER TABLE transactions
    ADD COLUMN IF NOT EXISTS version INTEGER NOT NULL DEFAULT 1,
    ADD COLUMN IF NOT EXISTS voided_at TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS transaction_corrections (
    id SERIAL PRIMARY KEY,
    transaction_id INTEGER NOT NULL REFERENCES transactions(id) ON DELETE RESTRICT,
    version_before INTEGER NOT NULL,
    version_after INTEGER NOT NULL,
    action VARCHAR(10) NOT NULL,
    reason VARCHAR(500) NOT NULL,
    before_state JSONB NOT NULL,
    after_state JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT ck_transaction_corrections_action CHECK (action IN ('edit', 'void')),
    CONSTRAINT ck_transaction_corrections_version CHECK (version_after = version_before + 1)
);

CREATE INDEX IF NOT EXISTS ix_transaction_corrections_transaction_id
    ON transaction_corrections (transaction_id);
