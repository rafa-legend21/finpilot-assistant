# Data model

## Persisted today

| Entity | Purpose | Key fields |
| --- | --- | --- |
| `financial_drafts` | One journal-derived proposal and its review state | `id`, `status`, `version`, `original_journal`, `original_snapshot`, `working_metadata`, `clarification_state` |
| `financial_draft_events` | Proposed events within a draft | `id`, `draft_id`, `position`, `disposition`, `event_payload` |
| `financial_draft_clarifications` | Questions, options, answers, and resolution state | `id`, `draft_id`, `related_event_id`, `issue_type`, `status`, `options_payload`, `answer_payload` |
| `transactions` | Confirmed expense records | `id`, `amount`, `currency`, `category`, `transaction_date`, `merchant`, `source_draft_id`, `source_event_id` |

`event_payload` contains a structured `SpendingEvent`: transaction type, amount mentions, quantities, payer, settlement status, source text, and a candidate user net amount. A draft event is not a ledger transaction. Only included events that pass confirmation checks create `transactions` rows. A unique draft/event source pair prevents duplicate records for the same event.

The ledger currently records confirmed **expenses only**. `SpendingEvent` can describe income, refunds, transfers, and reimbursements, but confirmation does not yet persist those types. There is no persisted budget, account balance, or user identity model.

## Planned concepts

The roadmap calls for transaction history, corrections, budget limits, income and refund handling, and user-owned data. Their schema and migration details remain to be designed. Avoid calculating a safe-to-spend amount until the required income, obligations, and balance inputs exist and their freshness is known.

The SQL files in `database/migrations/` are the PostgreSQL schema history. The SQLAlchemy models in `backend/app/models/` describe the application's ORM view. Schema changes require explicit migrations.
