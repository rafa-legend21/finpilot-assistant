# Milestone 1 acceptance checklist

- [x] Repository structure created.
- [x] FastAPI application has root and health endpoints.
- [x] Automated backend tests included.
- [x] PostgreSQL service included through Docker Compose.
- [x] Flutter application skeleton included.
- [x] Home screen shows budget and pay-allocation placeholders.
- [x] Environment template and secret-handling rules included.
- [x] Architecture note included.

## User verification

1. Install Docker Desktop.
2. Run `docker compose up --build` from the project root.
3. Open `http://localhost:8000/docs`.
4. Confirm `GET /api/v1/health` returns status `ok`.
5. Install Flutter, then run `flutter pub get` and `flutter run` inside `mobile/`.
