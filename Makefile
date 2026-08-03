.PHONY: up down logs test backend-install backend-run

up:
	docker compose up --build

down:
	docker compose down

logs:
	docker compose logs -f

test:
	cd backend && pytest

backend-install:
	cd backend && python -m pip install -e ".[dev]"

backend-run:
	cd backend && uvicorn app.main:app --reload
