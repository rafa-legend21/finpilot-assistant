# AGENTS.md

# FinPilot Assistant

This document defines the engineering rules for all AI coding agents working on this repository.

---

# Project Vision

FinPilot is an AI-powered personal finance companion.

The goal is NOT to build a traditional bookkeeping application.

The goal is to build an AI that understands human stories, extracts financial events accurately, and helps users build healthy financial habits.

Accuracy is always more important than automation.

---

# Core Principles

## Story First

Always understand the entire story before extracting transactions.

Never assume every number is money.

---

## Financial Accuracy

Never double count expenses.

Included item prices must not be counted twice when an overall total exists.

Example:

Dinner: $80

Drink: $33

User expense = $80

NOT $113.

---

## Payment Responsibility

Only include expenses actually paid by the user.

Examples:

- Mother paid → NOT user's expense.
- Friend paid → NOT user's expense.
- Employer reimbursed → NOT user's expense.

---

## Quantities

Measurements are NOT money.

Examples:

- 6 ounces
- 3 kilograms
- 2 hours
- 10 items

must never be interpreted as currency.

---

## Ambiguity

If financial responsibility is unclear,

generate a confirmation question instead of making assumptions.

---

## Emotion

Users may express multiple emotions simultaneously.

Never force a single emotion.

Example:

"I was exhausted but very happy."

Both emotions should be preserved.

---

# Engineering Principles

- Python 3.13
- FastAPI
- Pydantic v2
- SQLAlchemy 2.x
- PostgreSQL
- Docker Compose

Use strict typing whenever practical.

Keep functions focused and readable.

Avoid unnecessary abstractions.

---

# Repository Rules

Never modify unrelated files.

Never rename folders without approval.

Do not introduce breaking API changes unless requested.

Keep commits small and reviewable.

---

# Secrets

Never read, print, expose, or commit:

- .env
- API keys
- passwords
- tokens

Use .env.example only as a template.

---

# Database

Do not delete or recreate production tables.

Database migrations should be explicit.

Never destroy user data.

---

# Git

Work on feature branches.

Use Conventional Commit messages.

Never force push unless explicitly requested.

Never delete Git history.

---

# Testing

Before considering a task complete:

- run tests
- check imports
- verify formatting
- explain modified files

---

# UI Philosophy

The interface should feel like talking to a trusted financial companion.

Never overwhelm users with numbers.

Present financial insights in a calm and encouraging way.

---

# When Unsure

Do not guess.

Explain assumptions.

Ask for clarification when financial accuracy may change.

---

# AI Agent Behavior

Before modifying code:

1. Read the existing architecture.
2. Understand the intent before editing.
3. Prefer minimal, reviewable changes.
4. Preserve backward compatibility unless explicitly instructed.
5. Never modify unrelated files.
6. Explain important design decisions.
7. Run relevant tests before considering the task complete.
8. Never sacrifice financial correctness for convenience.
9. When requirements are ambiguous, ask instead of guessing.
10. Treat AGENTS.md as the highest-priority project guideline.