from datetime import date
from decimal import Decimal

import pytest
from sqlalchemy import create_engine, func, select
from sqlalchemy.orm import Session

from app.db.base import Base
from app.models.transaction import Transaction
from app.schemas.financial_draft import (
    ClarificationAnswer,
    ClarificationAnswersRequest,
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
    SettlementStatus,
    SpendingEvent,
    StoryParseResponse,
    TransactionType,
)
from app.services.clarification_service import ClarificationService
from app.services.financial_draft_service import (
    FinancialDraftConflictError,
    FinancialDraftService,
)


@pytest.fixture
def session() -> Session:
    engine = create_engine("sqlite+pysqlite:///:memory:")
    Base.metadata.create_all(engine)
    with Session(engine) as database_session:
        yield database_session


def spending_event(
    amount: str,
    *,
    currency: CurrencyCode = CurrencyCode.CAD,
    needs_confirmation: bool = False,
    transaction_type: TransactionType = TransactionType.EXPENSE,
    payer_type: PayerType = PayerType.USER,
    merchant: str | None = "Cafe",
    event_date: date | None = date(2026, 8, 8),
) -> SpendingEvent:
    return SpendingEvent(
        title="Test purchase",
        category=ExpenseCategory.DINING,
        transaction_type=transaction_type,
        event_date=event_date,
        merchant=merchant,
        payer_type=payer_type,
        user_net_amount=Decimal(amount),
        currency=currency,
        amount_mentions=[
            AmountMention(
                amount=Decimal(amount),
                currency=currency,
                role=AmountRole.USER_NET_EXPENSE,
                counted_in_user_total=True,
                source_text=amount,
                confidence=1,
                explanation="Test amount.",
            )
        ],
        source_text="Test source.",
        confidence=1,
        needs_confirmation=needs_confirmation,
    )


def create_request(events: list[SpendingEvent]) -> FinancialDraftCreateRequest:
    return FinancialDraftCreateRequest.model_validate(
        {
            "story_parse_response": {
                "summary": "Original summary",
                "spending_events": [event.model_dump(mode="json") for event in events],
                "moods": [],
                "life_events": [],
                "confirmation_questions": [],
                "total_user_expense": "999.00",
                "total_paid_by_others": "999.00",
                "total_saved_decisions": "999.00",
                "parser_confidence": 1,
                "draft_only": True,
            }
        }
    )


def include_event(
    service: FinancialDraftService,
    draft,
    position: int,
    event: SpendingEvent,
):
    return service.update_event(
        draft.id,
        draft.events[position].id,
        FinancialDraftEventUpdate(
            expected_version=draft.version,
            disposition=DraftEventDisposition.INCLUDE,
            event=event,
        ),
    )


def test_create_is_draft_only_and_preserves_original_snapshot(session: Session) -> None:
    service = FinancialDraftService(session)
    original_event = spending_event("80")
    draft = service.create(create_request([original_event]))

    assert draft.status == "draft"
    assert draft.events[0].disposition == DraftEventDisposition.PENDING
    assert draft.totals_by_currency == {}
    assert draft.original_snapshot["total_user_expense"] == "999.00"
    assert session.scalar(select(func.count()).select_from(Transaction)) == 0
    session.rollback()

    edited_event = spending_event("70")
    updated = include_event(service, draft, 0, edited_event)
    assert updated.original_snapshot["spending_events"][0]["user_net_amount"] == "80"
    assert updated.events[0].event.user_net_amount == Decimal(70)


def test_totals_are_deterministic_and_grouped_by_currency(session: Session) -> None:
    service = FinancialDraftService(session)
    cad = spending_event("80", currency=CurrencyCode.CAD)
    usd = spending_event("25", currency=CurrencyCode.USD)
    draft = service.create(create_request([cad, usd]))
    draft = include_event(service, draft, 0, cad)
    draft = include_event(service, draft, 1, usd)

    assert draft.totals_by_currency == {
        CurrencyCode.CAD: Decimal(80),
        CurrencyCode.USD: Decimal(25),
    }


def test_pending_and_ambiguous_included_events_block_confirmation(session: Session) -> None:
    service = FinancialDraftService(session)
    ambiguous = spending_event("20", needs_confirmation=True)
    draft = service.create(create_request([ambiguous]))

    with pytest.raises(FinancialDraftConflictError, match="included or excluded"):
        service.confirm(draft.id, draft.version)

    draft = include_event(service, draft, 0, ambiguous)
    with pytest.raises(FinancialDraftConflictError, match="requiring confirmation"):
        service.confirm(draft.id, draft.version)


def test_excluded_ambiguous_event_can_be_confirmed_without_ledger_write(
    session: Session,
) -> None:
    service = FinancialDraftService(session)
    ambiguous = spending_event("20", needs_confirmation=True)
    draft = service.create(create_request([ambiguous]))
    draft = service.update_event(
        draft.id,
        draft.events[0].id,
        FinancialDraftEventUpdate(
            expected_version=draft.version,
            disposition=DraftEventDisposition.EXCLUDE,
            event=ambiguous,
        ),
    )

    confirmed = service.confirm(draft.id, draft.version)

    assert confirmed.transaction_ids == []
    assert confirmed.draft.status == "confirmed"


@pytest.mark.parametrize(
    "transaction_type,payer_type",
    [
        (TransactionType.INCOME, PayerType.USER),
        (TransactionType.TRANSFER, PayerType.USER),
        (TransactionType.REFUND, PayerType.USER),
        (TransactionType.REIMBURSEMENT, PayerType.USER),
    ],
)
def test_unsupported_included_events_are_rejected(
    session: Session,
    transaction_type: TransactionType,
    payer_type: PayerType,
) -> None:
    service = FinancialDraftService(session)
    event = spending_event("10", transaction_type=transaction_type, payer_type=payer_type)
    draft = service.create(create_request([event]))
    draft = include_event(service, draft, 0, event)

    with pytest.raises(FinancialDraftConflictError):
        service.confirm(draft.id, draft.version)


def test_confirmation_is_atomic_has_provenance_and_cannot_repeat(session: Session) -> None:
    service = FinancialDraftService(session)
    valid = spending_event("80")
    invalid = spending_event("20", merchant=None)
    draft = service.create(create_request([valid, invalid]))
    draft = include_event(service, draft, 0, valid)
    draft = include_event(service, draft, 1, invalid)

    with pytest.raises(FinancialDraftConflictError, match="merchant"):
        service.confirm(draft.id, draft.version)
    assert session.scalar(select(func.count()).select_from(Transaction)) == 0
    session.rollback()

    draft = service.update_event(
        draft.id,
        draft.events[1].id,
        FinancialDraftEventUpdate(
            expected_version=draft.version,
            disposition=DraftEventDisposition.EXCLUDE,
            event=invalid,
        ),
    )
    confirmed = service.confirm(draft.id, draft.version)
    transaction = session.get(Transaction, confirmed.transaction_ids[0])

    assert transaction is not None
    assert transaction.amount == Decimal(80)
    assert transaction.source_draft_id == draft.id
    assert transaction.source_event_id == draft.events[0].id
    session.commit()

    with pytest.raises(FinancialDraftConflictError, match="immutable"):
        service.confirm(draft.id, confirmed.draft.version)
    assert session.scalar(select(func.count()).select_from(Transaction)) == 1


def test_stale_edits_and_cancelled_drafts_are_immutable(session: Session) -> None:
    service = FinancialDraftService(session)
    event = spending_event("10")
    draft = service.create(create_request([event]))

    with pytest.raises(FinancialDraftConflictError, match="stale"):
        service.update_event(
            draft.id,
            draft.events[0].id,
            FinancialDraftEventUpdate(
                expected_version=999,
                disposition=DraftEventDisposition.EXCLUDE,
                event=event,
            ),
        )

    cancelled = service.cancel(draft.id, draft.version)
    with pytest.raises(FinancialDraftConflictError, match="immutable"):
        service.update_event(
            draft.id,
            draft.events[0].id,
            FinancialDraftEventUpdate(
                expected_version=cancelled.version,
                disposition=DraftEventDisposition.EXCLUDE,
                event=event,
            ),
        )


def test_repaid_third_party_event_survives_review_and_creates_ledger_transaction(
    session: Session,
) -> None:
    parsed = StoryParseResponse(
        summary="Mother initially paid for coffee beans.",
        spending_events=[
            SpendingEvent(
                title="Coffee beans",
                category=ExpenseCategory.GROCERY,
                event_date=date(2026, 8, 8),
                merchant="Coffee shop",
                payer_type=PayerType.OTHER_PERSON,
                paid_by_name="mother",
                user_net_amount=Decimal(0),
                currency=CurrencyCode.CAD,
                amount_mentions=[
                    AmountMention(
                        amount=Decimal(18),
                        currency=CurrencyCode.CAD,
                        role=AmountRole.PAID_BY_OTHER,
                        counted_in_user_total=False,
                        source_text="18 CAD",
                        confidence=1,
                        explanation="Mother initially paid.",
                    )
                ],
                source_text="I bought coffee beans for 18 CAD, but my mother paid for them.",
                confidence=1,
            )
        ],
        confirmation_questions=[],
        total_user_expense=Decimal(0),
        total_paid_by_others=Decimal(18),
        total_saved_decisions=Decimal(0),
        parser_confidence=1,
    )
    clarification_service = ClarificationService(session)
    initial = clarification_service.create_from_parse(
        "I bought coffee beans for 18 CAD, but my mother paid for them.",
        parsed,
    )
    canonical_question = next(
        item for item in initial.clarifications if item.status == "open"
    )
    clarified = clarification_service.answer(
        initial.draft.id,
        ClarificationAnswersRequest(
            expected_version=initial.draft.version,
            answers=[
                ClarificationAnswer(
                    question_id=canonical_question.id,
                    option_key="repaid_by_user",
                )
            ],
        ),
    )
    clarified_event = clarified.draft.events[0]
    assert clarified_event.event.user_net_amount == Decimal(18)

    draft_service = FinancialDraftService(session)
    reviewed = draft_service.update_event(
        clarified.draft.id,
        clarified_event.id,
        FinancialDraftEventUpdate(
            expected_version=clarified.draft.version,
            disposition=DraftEventDisposition.INCLUDE,
            event=clarified_event.event,
        ),
    )

    assert reviewed.events[0].event.payer_type == PayerType.OTHER_PERSON
    assert reviewed.events[0].event.paid_by_name == "mother"
    assert reviewed.events[0].event.settlement_status == SettlementStatus.REPAID_BY_USER
    assert reviewed.events[0].event.user_net_amount == Decimal(18)
    assert reviewed.totals_by_currency == {CurrencyCode.CAD: Decimal(18)}
    assert reviewed.model_dump(mode="json")["totals_by_currency"] == {"CAD": "18"}

    confirmed = draft_service.confirm(reviewed.id, reviewed.version)
    assert len(confirmed.transaction_ids) == 1
    transaction = session.get(Transaction, confirmed.transaction_ids[0])
    assert transaction is not None
    assert transaction.amount == Decimal(18)


@pytest.mark.parametrize(
    ("option_key", "settlement_status"),
    [
        ("paid_by_other", SettlementStatus.COVERED_BY_OTHER),
        ("repayment_due", SettlementStatus.REPAYMENT_DUE),
    ],
)
def test_non_realized_third_party_settlement_stays_excluded(
    session: Session,
    option_key: str,
    settlement_status: SettlementStatus,
) -> None:
    parsed = StoryParseResponse(
        summary="Mother initially paid for coffee beans.",
        spending_events=[
            SpendingEvent(
                title="Coffee beans",
                category=ExpenseCategory.GROCERY,
                payer_type=PayerType.OTHER_PERSON,
                paid_by_name="mother",
                user_net_amount=Decimal(0),
                currency=CurrencyCode.CAD,
                amount_mentions=[
                    AmountMention(
                        amount=Decimal(18),
                        currency=CurrencyCode.CAD,
                        role=AmountRole.PAID_BY_OTHER,
                        counted_in_user_total=False,
                        source_text="18 CAD",
                        confidence=1,
                        explanation="Mother initially paid.",
                    )
                ],
                source_text="I bought coffee beans for 18 CAD, but my mother paid for them.",
                confidence=1,
            )
        ],
        confirmation_questions=[],
        total_user_expense=Decimal(0),
        total_paid_by_others=Decimal(18),
        total_saved_decisions=Decimal(0),
        parser_confidence=1,
    )
    clarification_service = ClarificationService(session)
    initial = clarification_service.create_from_parse(
        "I bought coffee beans for 18 CAD, but my mother paid for them.",
        parsed,
    )
    question = next(item for item in initial.clarifications if item.status == "open")
    clarified = clarification_service.answer(
        initial.draft.id,
        ClarificationAnswersRequest(
            expected_version=initial.draft.version,
            answers=[
                ClarificationAnswer(question_id=question.id, option_key=option_key)
            ],
        ),
    )
    event = clarified.draft.events[0]

    assert event.event.settlement_status == settlement_status
    assert event.disposition == DraftEventDisposition.EXCLUDE

    draft_service = FinancialDraftService(session)
    with pytest.raises(FinancialDraftConflictError, match="excluded"):
        draft_service.update_event(
            clarified.draft.id,
            event.id,
            FinancialDraftEventUpdate(
                expected_version=clarified.draft.version,
                disposition=DraftEventDisposition.INCLUDE,
                event=event.event,
            ),
        )

    confirmed = draft_service.confirm(clarified.draft.id, clarified.draft.version)
    assert confirmed.transaction_ids == []
    assert session.scalar(select(func.count()).select_from(Transaction)) == 0


def test_event_review_cannot_change_resolved_third_party_settlement(
    session: Session,
) -> None:
    parsed = StoryParseResponse(
        summary="Mother initially paid.",
        spending_events=[
            SpendingEvent(
                title="Coffee beans",
                category=ExpenseCategory.GROCERY,
                payer_type=PayerType.OTHER_PERSON,
                paid_by_name="mother",
                user_net_amount=Decimal(0),
                currency=CurrencyCode.CAD,
                amount_mentions=[
                    AmountMention(
                        amount=Decimal(18),
                        currency=CurrencyCode.CAD,
                        role=AmountRole.PAID_BY_OTHER,
                        counted_in_user_total=False,
                        source_text="18 CAD",
                        confidence=1,
                        explanation="Mother paid.",
                    )
                ],
                source_text="Mother paid 18 CAD for coffee beans.",
                confidence=1,
            )
        ],
        confirmation_questions=[],
        total_user_expense=Decimal(0),
        total_paid_by_others=Decimal(18),
        total_saved_decisions=Decimal(0),
        parser_confidence=1,
    )
    clarification_service = ClarificationService(session)
    initial = clarification_service.create_from_parse("Mother paid for coffee.", parsed)
    question = next(item for item in initial.clarifications if item.status == "open")
    clarified = clarification_service.answer(
        initial.draft.id,
        ClarificationAnswersRequest(
            expected_version=initial.draft.version,
            answers=[
                ClarificationAnswer(
                    question_id=question.id,
                    option_key="repaid_by_user",
                )
            ],
        ),
    )
    event = clarified.draft.events[0]
    tampered_payload = event.event.model_dump(mode="json")
    tampered_payload.update(
        {
            "settlement_status": SettlementStatus.COVERED_BY_OTHER.value,
            "user_net_amount": "0",
            "amount_mentions": [],
        }
    )
    tampered_event = SpendingEvent.model_validate(tampered_payload)

    with pytest.raises(FinancialDraftConflictError, match="settlement"):
        FinancialDraftService(session).update_event(
            clarified.draft.id,
            event.id,
            FinancialDraftEventUpdate(
                expected_version=clarified.draft.version,
                disposition=DraftEventDisposition.EXCLUDE,
                event=tampered_event,
            ),
        )
