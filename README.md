# FinPilot Assistant

FinPilot is an AI personal finance companion. It helps users understand the stories behind their spending, review financial events before recording them, and make more deliberate money decisions. Financial accuracy takes priority over automation.

## Current status

The active application currently includes:

- A Flutter journal, clarification, and event-review flow.
- A FastAPI story parser and financial draft workflow. Confirmed expense events are saved with links to their source draft.
- A PostgreSQL development database, explicit SQL migrations, Docker Compose, and automated tests.
- Read-only transaction history and deterministic expense summaries by date, category, and currency.
- A home screen with **example figures**, not live financial summaries.

Transaction correction, budget calculations, live insights, and impulse-spending support are planned. See the [roadmap](docs/roadmap.md).

## Repository layout

```text
finpilot-assistant/
├── backend/                    FastAPI API and tests
├── mobile/                     Flutter application and widget tests
├── database/                   Bootstrap SQL and numbered migrations
├── docs/                       Product and engineering documentation
└── docker-compose.yml
```

Start with the [documentation guide](docs/README.md) to find the current architecture, data model, and product notes.

## Quick start: backend and database

Requirements: Docker Desktop and a local `.env` made from `.env.example`. Set `OPENAI_API_KEY` there to use story parsing; never commit it.

```bash
docker compose up --build -d
docker compose run --rm api python scripts/run_migrations.py
```

Migrations are an explicit step; `docker compose up` does not apply them.

Then open:

- API documentation: `http://localhost:8000/docs`
- Health endpoint: `http://localhost:8000/api/v1/health`

Expected response:

```json
{
  "status": "ok",
  "service": "FinPilot Assistant API",
  "environment": "development",
  "version": "0.1.0"
}
```

## Run backend without Docker

```bash
cd backend
python -m venv .venv
# Windows PowerShell: .venv\Scripts\Activate.ps1
# macOS/Linux: source .venv/bin/activate
python -m pip install -e ".[dev]"
pytest
ruff check .
uvicorn app.main:app --reload
```

SQLite is the default when `DATABASE_URL` is not provided. It is useful for local development and tests; the Docker/PostgreSQL setup above is the supported path for the full database-backed flow. PostgreSQL migration integration tests require a separate `TEST_DATABASE_URL` and otherwise skip.

## Verify Chinese, English, and French parsing

The local parser is configured for `gpt-5`. Keep `OPENAI_API_KEY` only in the repository-root `.env`; the application loads it without printing it, and Git ignores the file.

Run the synthetic multilingual acceptance check from the backend directory:

```powershell
cd backend
..\.venv\Scripts\python.exe scripts\test_multilingual_acceptance.py
```

The check covers included prices, third-party payments, quantities, mixed emotions, and purchases the user decided not to make. Use `--case 3` or `--language zh` to limit a rerun. See the [acceptance record](docs/multilingual-acceptance.md) for the expected and latest verified results.

## Run the Flutter app

Requirements: Flutter SDK and an iOS Simulator, Android Emulator, physical device, or Edge for the browser preview.

```bash
cd mobile
flutter pub get
flutter test
flutter run --dart-define=API_BASE_URL=http://localhost:8000
```

For Android Emulator, the host computer is commonly reached through `http://10.0.2.2:8000`.

On Windows, use the [simulated user test guide](docs/simulated-user-test.md) to run the same Flutter journal and review flow in Edge with an isolated local database.

## Review recorded expenses

`GET /api/v1/transactions` lists confirmed ledger entries, newest first. It accepts optional `start_date`, `end_date`, and `currency` filters, plus `limit` (1–100, default 50) and `offset`. The response includes `total_count` for pagination and source draft/event IDs for traceability.

`GET /api/v1/transactions/summary` uses the same optional filters and returns totals grouped by currency, date, and category. Amounts are calculated from stored transactions, with each currency kept separate. An empty ledger returns empty lists and totals. These endpoints are for local development until user identity and data access controls are added.

## Financial and privacy boundaries

- Never request or store online-banking passwords.
- Only reviewed events are written to the transaction ledger.
- Calculate financial totals in application code, not from AI explanations.
- Add user accounts, access control, encryption for stored journals, and a retention policy before handling real users' data.

## Next work

Priorities are financial-accuracy edge cases, transaction correction, and a live overview based on known data. See the [roadmap](docs/roadmap.md) for the proposed sequence.
