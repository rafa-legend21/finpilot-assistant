# Roadmap

This is a proposed order of work, not a release schedule. The [project README](../README.md) describes what currently runs.

## Current foundation

- Story parsing into structured financial drafts
- Required clarification and user review before expense ledger writes
- PostgreSQL migrations and automated backend and mobile tests
- Flutter home screen with example figures

## Next: trustworthy records and a real overview

1. Tighten shared-payment and repayment amount/date handling, with regression cases from real wording.
2. Add transaction read and correction flows, then deterministic summaries by date, category, and currency.
3. Replace home-screen example figures with sourced values, freshness labels, and clear unknown states.
4. Add user identity and data access boundaries before using real users' financial histories.

## After that: decisions and habits

1. Model income, refunds, transfers, obligations, and budgets without mixing them into expense totals.
2. Offer an optional purchase-intent flow with context, a pause option, and gentle reminders.
3. Evaluate whether reminders help users before attempting personalized impulse-spending prediction.

Email ingestion, automatic categorization, and payroll planning remain possible later stages. Each should preserve reviewability, privacy, and deterministic financial calculations.
