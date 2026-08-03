# FinPilot Assistant

FinPilot Assistant is a privacy-conscious personal budgeting application that will turn bank transaction emails into categorized spending records, monthly budgets, pay allocation guidance, and explainable financial insights.

## Milestone 1 status

This repository contains the initial working architecture:

- Flutter mobile app shell
- FastAPI backend
- PostgreSQL development database
- Docker Compose local environment
- Health endpoint and backend tests
- Initial home dashboard

## Repository layout

```text
finpilot-assistant/
├── backend/       FastAPI API and tests
├── mobile/        Flutter application
├── database/      Database bootstrap scripts
├── docs/          Architecture and acceptance criteria
└── docker-compose.yml
```

## Quick start: backend and database

Requirements: Docker Desktop.

```bash
docker compose up --build
```

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
# Windows: .venv\\Scripts\\activate
# macOS/Linux: source .venv/bin/activate
python -m pip install -e ".[dev]"
pytest
uvicorn app.main:app --reload
```

SQLite is used automatically when `DATABASE_URL` is not provided.

## Run the Flutter app

Requirements: Flutter SDK and an iOS Simulator, Android Emulator, or physical device.

```bash
cd mobile
flutter pub get
flutter test
flutter run --dart-define=API_BASE_URL=http://localhost:8000
```

For Android Emulator, the host computer is commonly reached through `http://10.0.2.2:8000`.

## Security boundaries

- Never request or store online-banking passwords.
- Use OAuth for Gmail access.
- Store only card/account last four digits.
- Encrypt OAuth tokens and sensitive financial records.
- Keep deterministic financial calculations separate from AI-generated explanations.

## Next milestone

Milestone 2 adds the transaction domain:

- transaction database model
- create, list, edit, and delete APIs
- category management
- monthly spending summaries
- connected mobile transaction screens
