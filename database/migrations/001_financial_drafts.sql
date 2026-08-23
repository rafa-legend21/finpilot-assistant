CREATE TABLE IF NOT EXISTS financial_drafts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    status VARCHAR(20) NOT NULL DEFAULT 'draft',
    original_snapshot JSONB NOT NULL,
    working_metadata JSONB NOT NULL,
    version INTEGER NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    confirmed_at TIMESTAMPTZ,
    cancelled_at TIMESTAMPTZ,
    CONSTRAINT ck_financial_drafts_status
        CHECK (status IN ('draft', 'confirmed', 'cancelled'))
);

CREATE INDEX IF NOT EXISTS ix_financial_drafts_status ON financial_drafts (status);

CREATE TABLE IF NOT EXISTS financial_draft_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    draft_id UUID NOT NULL REFERENCES financial_drafts(id) ON DELETE CASCADE,
    position INTEGER NOT NULL,
    disposition VARCHAR(20) NOT NULL DEFAULT 'pending',
    event_payload JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_financial_draft_event_position UNIQUE (draft_id, position),
    CONSTRAINT ck_financial_draft_event_disposition
        CHECK (disposition IN ('pending', 'include', 'exclude'))
);

CREATE INDEX IF NOT EXISTS ix_financial_draft_events_draft_id
    ON financial_draft_events (draft_id);

CREATE TABLE IF NOT EXISTS transactions (
    id SERIAL PRIMARY KEY,
    merchant VARCHAR(150) NOT NULL,
    amount NUMERIC(12, 2) NOT NULL,
    currency VARCHAR(3) NOT NULL DEFAULT 'CAD',
    category VARCHAR(50) NOT NULL DEFAULT 'Other',
    transaction_date DATE NOT NULL,
    bank VARCHAR(50),
    account_last4 VARCHAR(4),
    note VARCHAR(500),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE transactions
    ADD COLUMN IF NOT EXISTS source_draft_id UUID REFERENCES financial_drafts(id),
    ADD COLUMN IF NOT EXISTS source_event_id UUID REFERENCES financial_draft_events(id);

ALTER TABLE transactions
    DROP CONSTRAINT IF EXISTS ck_transactions_draft_provenance;
ALTER TABLE transactions
    ADD CONSTRAINT ck_transactions_draft_provenance CHECK (
        (source_draft_id IS NULL AND source_event_id IS NULL)
        OR (source_draft_id IS NOT NULL AND source_event_id IS NOT NULL)
    );

CREATE UNIQUE INDEX IF NOT EXISTS uq_transactions_draft_event
    ON transactions (source_draft_id, source_event_id)
    WHERE source_draft_id IS NOT NULL AND source_event_id IS NOT NULL;
