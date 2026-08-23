ALTER TABLE financial_drafts
    ADD COLUMN IF NOT EXISTS original_journal VARCHAR(10000),
    ADD COLUMN IF NOT EXISTS clarification_state VARCHAR(30) NOT NULL DEFAULT 'ready_for_review';

CREATE TABLE IF NOT EXISTS financial_draft_clarifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    draft_id UUID NOT NULL REFERENCES financial_drafts(id) ON DELETE CASCADE,
    sequence INTEGER NOT NULL,
    round_number INTEGER NOT NULL,
    semantic_key VARCHAR(255) NOT NULL,
    requirement VARCHAR(30) NOT NULL,
    issue_type VARCHAR(50) NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'open',
    question VARCHAR(500) NOT NULL,
    reason VARCHAR(500) NOT NULL,
    related_event_id UUID REFERENCES financial_draft_events(id) ON DELETE SET NULL,
    related_source_text VARCHAR(10000) NOT NULL,
    options_payload JSONB NOT NULL,
    answer_payload JSONB,
    resolution_method VARCHAR(30),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    answered_at TIMESTAMPTZ,
    CONSTRAINT uq_draft_clarification_sequence UNIQUE (draft_id, sequence),
    CONSTRAINT uq_draft_clarification_semantic_key UNIQUE (draft_id, semantic_key),
    CONSTRAINT ck_draft_clarification_round CHECK (round_number BETWEEN 1 AND 3)
);

CREATE INDEX IF NOT EXISTS ix_financial_draft_clarifications_draft_id
    ON financial_draft_clarifications (draft_id);
