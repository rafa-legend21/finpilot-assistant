# Architecture

## Implemented flow

```text
Flutter journal entry
    -> FastAPI story parser
    -> PostgreSQL financial draft
    -> required clarification, if needed
    -> user review of each event
    -> confirmed expense transactions
```

The parser proposes events and preserves source text, amount roles, payment responsibility, quantities, and multiple moods. Clarification and review happen before ledger writes. The backend recalculates draft totals by currency and uses draft versions to reject stale updates. Confirmed transactions retain draft and event IDs for provenance.

The API also supports direct story parsing and direct draft creation. The mobile app uses the combined journal-to-draft route for its main flow. See `backend/app/api/router.py` for active routes and `backend/app/services/` for financial rules.

## Storage and local runtime

- PostgreSQL is the Docker development database. Numbered SQL files in `database/migrations/` are applied explicitly with `backend/scripts/run_migrations.py`.
- SQLite is the backend default when `DATABASE_URL` is absent; tests create their own schemas.
- The home screen uses example values and does not read financial summaries from the API.

## Planned components

Transaction history and correction, income and refund handling, a deterministic budget engine, live summaries, and purchase-intent support are future work. Email ingestion and automatic categorization are also possible later stages. They should feed the reviewed financial flow only after accuracy and privacy boundaries are defined.

User identity, per-user access control, encryption for stored journal content, and retention controls are not implemented yet. These are prerequisites for real user data. The current code stores draft journal text and snapshots.
