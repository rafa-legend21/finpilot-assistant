# ADR-001: Transaction types

**Decision:** The transaction ledger should distinguish expenses, income, transfers, refunds, and reimbursements with an explicit `transaction_type`.

**Status:** Accepted as a design direction; ledger implementation pending.

## Rationale

These events have different effects on spending, balances, and budgets. Treating them all as expenses would produce misleading totals.

## Current implementation

`SpendingEvent` has a `transaction_type` in the parser and draft schemas. The persisted `transactions` model does not yet have this column, and the confirmation service currently records expense events only. Add the column through an explicit migration when the ledger supports the remaining event types.
