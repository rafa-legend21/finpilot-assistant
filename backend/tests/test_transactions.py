from collections.abc import Iterator
from datetime import date
from decimal import Decimal

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import Session
from sqlalchemy.pool import StaticPool

from app.db.base import Base
from app.db.dependencies import get_db_session
from app.main import app
from app.models.transaction import Transaction
from app.schemas.financial_draft import (
    DraftEventDisposition,
    FinancialDraftCreateRequest,
    FinancialDraftEventUpdate,
)
from app.schemas.story_parser import (
    AmountMention,
    AmountRole,
    CurrencyCode,
    ExpenseCategory,
    PayerType,
    SpendingEvent,
    StoryParseResponse,
)
from app.services.financial_draft_service import FinancialDraftService


@pytest.fixture
def api_session() -> Iterator[Session]:
    engine = create_engine(
        "sqlite+pysqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine)
    with Session(engine) as session:
        yield session
    engine.dispose()


@pytest.fixture
def client(api_session: Session) -> Iterator[TestClient]:
    def override_session() -> Iterator[Session]:
        yield api_session

    app.dependency_overrides[get_db_session] = override_session
    try:
        with TestClient(app) as test_client:
            yield test_client
    finally:
        app.dependency_overrides.pop(get_db_session, None)


def test_empty_ledger_has_explicit_empty_results(client: TestClient) -> None:
    assert client.get("/api/v1/transactions").json() == {
        "transactions": [],
        "total_count": 0,
    }
    assert client.get("/api/v1/transactions/summary").json() == {
        "totals_by_currency": {},
        "by_date": [],
        "by_category": [],
    }


def test_list_and_summary_keep_currencies_separate_and_filter_dates(
    client: TestClient, api_session: Session
) -> None:
    api_session.add_all(
        [
            Transaction(
                amount=Decimal("80.00"),
                currency="CAD",
                category="dining",
                transaction_date=date(2026, 8, 8),
                merchant="Cafe",
            ),
            Transaction(
                amount=Decimal("30.00"),
                currency="USD",
                category="dining",
                transaction_date=date(2026, 8, 8),
                merchant="Bistro",
            ),
            Transaction(
                amount=Decimal("20.00"),
                currency="CAD",
                category="grocery",
                transaction_date=date(2026, 8, 9),
                merchant=None,
            ),
            Transaction(
                amount=Decimal("5.50"),
                currency="CAD",
                category="dining",
                transaction_date=date(2026, 8, 8),
                merchant="Bakery",
            ),
        ]
    )
    api_session.commit()

    listed = client.get("/api/v1/transactions?limit=2")
    assert listed.status_code == 200
    assert listed.json()["total_count"] == 4
    assert [item["amount"] for item in listed.json()["transactions"]] == ["20.00", "5.50"]
    assert listed.json()["transactions"][0]["merchant"] is None

    page = client.get("/api/v1/transactions?currency=CAD&offset=1&limit=1")
    assert page.status_code == 200
    assert page.json()["total_count"] == 3
    assert page.json()["transactions"][0]["amount"] == "5.50"

    summary = client.get("/api/v1/transactions/summary").json()
    assert summary["totals_by_currency"] == {"CAD": "105.50", "USD": "30.00"}
    assert summary["by_date"] == [
        {"date": "2026-08-08", "currency": "CAD", "amount": "85.50"},
        {"date": "2026-08-08", "currency": "USD", "amount": "30.00"},
        {"date": "2026-08-09", "currency": "CAD", "amount": "20.00"},
    ]
    assert summary["by_category"] == [
        {"category": "dining", "currency": "CAD", "amount": "85.50"},
        {"category": "dining", "currency": "USD", "amount": "30.00"},
        {"category": "grocery", "currency": "CAD", "amount": "20.00"},
    ]

    filtered = client.get("/api/v1/transactions/summary?start_date=2026-08-09&end_date=2026-08-09")
    assert filtered.json()["totals_by_currency"] == {"CAD": "20.00"}
    assert client.get("/api/v1/transactions?end_date=2026-08-08").json()["total_count"] == 3


@pytest.mark.parametrize(
    "query",
    ["start_date=2026-08-10&end_date=2026-08-08", "limit=0", "limit=101", "offset=-1"],
)
def test_invalid_list_filters_are_rejected(client: TestClient, query: str) -> None:
    assert client.get(f"/api/v1/transactions?{query}").status_code == 422


def test_invalid_summary_date_range_is_rejected(client: TestClient) -> None:
    assert (
        client.get(
            "/api/v1/transactions/summary?start_date=2026-08-10&end_date=2026-08-08"
        ).status_code
        == 422
    )


def test_reviewed_event_appears_only_after_confirmation(
    client: TestClient, api_session: Session
) -> None:
    event = SpendingEvent(
        title="Coffee beans",
        category=ExpenseCategory.GROCERY,
        event_date=date(2026, 8, 10),
        payer_type=PayerType.USER,
        user_net_amount=Decimal("18.00"),
        currency=CurrencyCode.CAD,
        amount_mentions=[
            AmountMention(
                amount=Decimal("18.00"),
                currency=CurrencyCode.CAD,
                role=AmountRole.USER_NET_EXPENSE,
                counted_in_user_total=True,
                source_text="18 CAD",
                confidence=1,
                explanation="Paid by user.",
            )
        ],
        source_text="I bought coffee beans for 18 CAD.",
        confidence=1,
    )
    parsed = StoryParseResponse(
        summary="Coffee beans bought.",
        spending_events=[event],
        total_user_expense=Decimal("18.00"),
        total_paid_by_others=Decimal(0),
        total_saved_decisions=Decimal(0),
        parser_confidence=1,
    )
    service = FinancialDraftService(api_session)
    draft = service.create(
        FinancialDraftCreateRequest.model_validate(
            {"story_parse_response": parsed.model_dump(mode="json")}
        )
    )
    assert client.get("/api/v1/transactions").json()["transactions"] == []
    api_session.rollback()

    reviewed = service.update_event(
        draft.id,
        draft.events[0].id,
        FinancialDraftEventUpdate(
            expected_version=draft.version,
            disposition=DraftEventDisposition.INCLUDE,
            event=event,
        ),
    )
    assert client.get("/api/v1/transactions/summary").json()["totals_by_currency"] == {}
    api_session.rollback()

    service.confirm(reviewed.id, reviewed.version)
    transactions = client.get("/api/v1/transactions").json()["transactions"]
    assert len(transactions) == 1
    assert transactions[0]["amount"] == "18.00"
    assert transactions[0]["source_draft_id"] == str(draft.id)
    assert transactions[0]["source_event_id"] == str(draft.events[0].id)


def test_correction_and_void_preserve_history_and_change_summary(
    client: TestClient, api_session: Session
) -> None:
    row = Transaction(
        amount=Decimal("18.00"),
        currency="CAD",
        category="dining",
        transaction_date=date(2026, 8, 10),
        merchant="Cafe",
    )
    api_session.add(row)
    api_session.commit()

    edited = client.patch(
        f"/api/v1/transactions/{row.id}",
        json={
            "expected_version": 1,
            "reason": "Receipt showed a different total",
            "amount": "12.50",
            "currency": "USD",
            "category": "grocery",
            "transaction_date": "2026-08-11",
            "merchant": "Market",
            "note": "Corrected from receipt",
        },
    )
    assert edited.status_code == 200
    assert edited.json()["version"] == 2
    assert client.get("/api/v1/transactions/summary").json()["totals_by_currency"] == {
        "USD": "12.50"
    }
    assert client.get("/api/v1/transactions/summary").json()["by_category"] == [
        {"category": "grocery", "currency": "USD", "amount": "12.50"}
    ]
    assert (
        client.patch(
            f"/api/v1/transactions/{row.id}",
            json={
                "expected_version": 1,
                "reason": "Stale edit",
                "amount": "99.00",
                "currency": "CAD",
                "category": "dining",
                "transaction_date": "2026-08-10",
            },
        ).status_code
        == 409
    )

    voided = client.post(
        f"/api/v1/transactions/{row.id}/void",
        json={"expected_version": 2, "reason": "This was paid by a friend"},
    )
    assert voided.status_code == 200
    assert voided.json()["version"] == 3
    assert voided.json()["voided_at"] is not None
    assert client.get("/api/v1/transactions").json()["total_count"] == 0
    assert client.get("/api/v1/transactions/summary").json()["totals_by_currency"] == {}
    assert client.get("/api/v1/transactions?include_voided=true").json()["total_count"] == 1
    assert client.get(f"/api/v1/transactions/{row.id}").status_code == 200
    history = client.get(f"/api/v1/transactions/{row.id}/corrections").json()
    assert [entry["action"] for entry in history] == ["edit", "void"]
    assert history[0]["before_state"]["amount"] == "18.00"
    assert history[0]["after_state"]["amount"] == "12.50"
    assert history[1]["reason"] == "This was paid by a friend"
    assert history[1]["after_state"]["voided_at"] is not None
    assert (
        client.post(
            f"/api/v1/transactions/{row.id}/void",
            json={"expected_version": 3, "reason": "Double void"},
        ).status_code
        == 409
    )


def test_invalid_corrections_do_not_change_record(client: TestClient, api_session: Session) -> None:
    row = Transaction(
        amount=Decimal("18.00"),
        currency="CAD",
        category="dining",
        transaction_date=date(2026, 8, 10),
    )
    api_session.add(row)
    api_session.commit()
    for amount in ("0", "-5", "1.234"):
        response = client.patch(
            f"/api/v1/transactions/{row.id}",
            json={
                "expected_version": 1,
                "reason": "A valid reason",
                "amount": amount,
                "currency": "CAD",
                "category": "dining",
                "transaction_date": "2026-08-10",
            },
        )
        assert response.status_code == 422
    assert (
        client.patch(
            f"/api/v1/transactions/{row.id}",
            json={
                "expected_version": 1,
                "reason": "Wrong transaction type",
                "amount": "18.00",
                "currency": "CAD",
                "category": "transfer",
                "transaction_date": "2026-08-10",
            },
        ).status_code
        == 422
    )
    assert (
        client.post(
            f"/api/v1/transactions/{row.id}/void",
            json={"expected_version": 1, "reason": "   "},
        ).status_code
        == 422
    )
    assert client.get(f"/api/v1/transactions/{row.id}").json()["version"] == 1
    assert client.get(f"/api/v1/transactions/{row.id}/corrections").json() == []
