from datetime import date
from decimal import Decimal

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import Session

from app.db.base import Base
from app.schemas.financial_draft import (
    ClarificationAnswer,
    ClarificationAnswersRequest,
    ClarificationIssueType,
    ClarificationOperation,
    ClarificationResolution,
    DraftEventDisposition,
    FinancialDraftEventUpdate,
)
from app.schemas.story_parser import (
    AmountMention,
    AmountRole,
    ConfirmationQuestion,
    CurrencyCode,
    ExpenseCategory,
    PayerType,
    SettlementStatus,
    SpendingEvent,
    StoryParseResponse,
)
from app.services.clarification_service import (
    MAX_REQUIRED_CLARIFICATION_ROUNDS,
    ClarificationService,
)
from app.services.financial_draft_service import (
    FinancialDraftConflictError,
    FinancialDraftService,
    FinancialDraftValidationError,
)


@pytest.mark.parametrize(
    ("language", "expected"),
    [("zh", "我仍需还款"), ("en", "I still owe them"), ("fr", "Je dois encore la rembourser")],
)
def test_settlement_options_use_selected_language(language: str, expected: str) -> None:
    options = ClarificationService._options(
        ClarificationIssueType.PAYER_RESPONSIBILITY,
        has_event=True,
        language=language,
    )
    assert next(option for option in options if option["option_key"] == "repayment_due")[
        "label"
    ] == expected


@pytest.fixture
def session() -> Session:
    engine = create_engine("sqlite+pysqlite:///:memory:")
    Base.metadata.create_all(engine)
    with Session(engine) as value:
        yield value


def parsed_story() -> StoryParseResponse:
    event = SpendingEvent(
        title="Coffee beans",
        category=ExpenseCategory.GROCERY,
        payer_type=PayerType.UNKNOWN,
        user_net_amount=Decimal(18),
        currency=CurrencyCode.CAD,
        amount_mentions=[
            AmountMention(
                amount=Decimal(18),
                currency=CurrencyCode.CAD,
                role=AmountRole.USER_NET_EXPENSE,
                counted_in_user_total=True,
                source_text="18 dollars",
                confidence=0.7,
                explanation="Payment responsibility is unclear.",
            )
        ],
        source_text="Mother bought 18 dollars of coffee beans",
        confidence=0.7,
        needs_confirmation=True,
    )
    return StoryParseResponse(
        summary="Coffee purchase needs clarification.",
        spending_events=[event],
        confirmation_questions=[
            ConfirmationQuestion(
                question="Who ultimately paid for the coffee beans?",
                reason="The payer changes the user's expense.",
                related_source_text="Mother bought 18 dollars of coffee beans",
            )
        ],
        total_user_expense=Decimal(0),
        total_paid_by_others=Decimal(0),
        total_saved_decisions=Decimal(0),
        parser_confidence=0.7,
    )


def answer_request(draft, question, option: str) -> ClarificationAnswersRequest:
    return ClarificationAnswersRequest(
        expected_version=draft.draft.version,
        answers=[ClarificationAnswer(question_id=question.id, option_key=option)],
    )


def test_journal_snapshot_and_question_are_persisted(session: Session) -> None:
    result = ClarificationService(session).create_from_parse("original journal", parsed_story())

    assert result.clarification_state == "awaiting_required"
    assert "needs clarification" in result.draft.summary
    assert len(result.clarifications) == 1
    assert result.clarifications[0].round_number == 1
    assert result.draft.original_snapshot["summary"] == "Coffee purchase needs clarification."


def test_unknown_option_is_rejected_and_not_recorded(session: Session) -> None:
    service = ClarificationService(session)
    draft = service.create_from_parse("journal", parsed_story())
    question = draft.clarifications[0]

    with pytest.raises(FinancialDraftValidationError, match="not valid"):
        service.answer(draft.draft.id, answer_request(draft, question, "arbitrary_patch"))

    current = service.get(draft.draft.id)
    assert current.clarifications[0].status == "open"
    assert current.draft.version == draft.draft.version


def test_persisted_option_resolves_question_deterministically(session: Session) -> None:
    service = ClarificationService(session)
    draft = service.create_from_parse("journal", parsed_story())
    question = draft.clarifications[0]

    updated = service.answer(
        draft.draft.id,
        answer_request(draft, question, "paid_by_other"),
    )

    assert updated.clarification_state == "ready_for_review"
    assert updated.clarifications[0].status == "answered"
    assert updated.draft.events[0].disposition == DraftEventDisposition.EXCLUDE
    assert updated.draft.events[0].event.user_net_amount == Decimal(0)
    assert updated.draft.original_snapshot["spending_events"][0]["user_net_amount"] == "18"

    with pytest.raises(FinancialDraftConflictError, match="already answered"):
        service.answer(
            draft.draft.id,
            ClarificationAnswersRequest(
                expected_version=updated.draft.version,
                answers=[ClarificationAnswer(question_id=question.id, option_key="paid_by_other")],
            ),
        )


def test_required_question_blocks_ledger_confirmation(session: Session) -> None:
    draft = ClarificationService(session).create_from_parse("journal", parsed_story())

    with pytest.raises(FinancialDraftConflictError, match="clarifications"):
        FinancialDraftService(session).confirm(draft.draft.id, draft.draft.version)


def test_required_question_cannot_be_bypassed_by_event_edit(session: Session) -> None:
    draft = ClarificationService(session).create_from_parse("journal", parsed_story())
    draft_event = draft.draft.events[0]

    with pytest.raises(FinancialDraftConflictError, match="required clarification"):
        FinancialDraftService(session).update_event(
            draft.draft.id,
            draft_event.id,
            FinancialDraftEventUpdate(
                expected_version=draft.draft.version,
                disposition=DraftEventDisposition.INCLUDE,
                event=draft_event.event.model_copy(update={"needs_confirmation": False}),
            ),
        )


class WrongQuestionResolver:
    def resolve(self, context: dict) -> ClarificationResolution:
        return ClarificationResolution(
            question_id="00000000-0000-0000-0000-000000000000",
            operation=ClarificationOperation.EXCLUDE_EVENT,
            explanation="Wrong target.",
        )


def test_free_text_proposal_is_validated_before_application(session: Session) -> None:
    service = ClarificationService(session, resolver=WrongQuestionResolver())
    draft = service.create_from_parse("journal", parsed_story())
    question = draft.clarifications[0]

    with pytest.raises(FinancialDraftValidationError, match="wrong question"):
        service.answer(
            draft.draft.id,
            ClarificationAnswersRequest(
                expected_version=draft.draft.version,
                answers=[ClarificationAnswer(question_id=question.id, free_text="My mother paid")],
            ),
        )

    assert service.get(draft.draft.id).clarifications[0].status == "open"


def test_required_round_limit_is_explicit() -> None:
    assert MAX_REQUIRED_CLARIFICATION_ROUNDS == 3


def test_duplicate_semantic_questions_are_not_repeated(session: Session) -> None:
    parsed = parsed_story()
    parsed.confirmation_questions.append(parsed.confirmation_questions[0].model_copy())

    result = ClarificationService(session).create_from_parse("journal", parsed)

    assert len(result.clarifications) == 1


@pytest.mark.parametrize("language", ["en", "zh", "fr"])
def test_third_party_payment_without_settlement_is_normalized_and_questioned(
    session: Session,
    language: str,
) -> None:
    parsed = StoryParseResponse(
        summary="Coffee beans purchased for 18 CAD, paid by mother; user owes 0.",
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
                        confidence=0.9,
                        explanation="Mother initially paid.",
                    )
                ],
                source_text="I bought coffee beans for 18 CAD, but my mother paid for them.",
                confidence=0.9,
            )
        ],
        confirmation_questions=[
            ConfirmationQuestion(
                question=(
                    "Did your mother cover the 18 CAD coffee beans as a treat "
                    "(so you owe nothing), or will you reimburse her?"
                ),
                reason=(
                    "This determines whether the 18 CAD should be included in your "
                    "expense total or marked as covered by another person."
                ),
                related_source_text="but my mother paid for them",
            )
        ],
        total_user_expense=Decimal(0),
        total_paid_by_others=Decimal(18),
        total_saved_decisions=Decimal(0),
        parser_confidence=0.9,
    )

    result = ClarificationService(session).create_from_parse(
        "I bought coffee beans for 18 CAD, but my mother paid for them.",
        parsed,
        response_language=language,
    )

    event = result.draft.events[0].event
    assert result.clarification_state == "awaiting_required"
    if language == "en":
        assert "needs clarification" in result.draft.summary
    assert len(result.clarifications) == 2
    assert result.clarifications[0].status == "superseded"
    clarification = result.clarifications[1]
    assert clarification.requirement == "required"
    assert clarification.issue_type == "payer_responsibility"
    if language == "en":
        assert clarification.question == (
            "Your mother paid 18 CAD for coffee beans. What happened afterward?"
        )
        assert clarification.reason == (
            "This helps FinPilot determine whether the 18 CAD is actually your expense."
        )
        assert [(option.option_key, option.label) for option in clarification.options] == [
            ("paid_by_other", "They paid for me — I owe nothing"),
            ("repaid_by_user", "I already paid them back"),
            ("repayment_due", "I still owe them"),
        ]
    else:
        assert "18 CAD" in clarification.question
        assert clarification.options[2].label == {
            "zh": "我仍需还款",
            "fr": "Je dois encore la rembourser",
        }[language]
    assert all(option.option_key != "confirm_as_parsed" for option in clarification.options)
    assert event.settlement_status == SettlementStatus.UNRESOLVED
    assert event.user_net_amount == Decimal(18)
    assert event.needs_confirmation is True
    assert result.draft.original_snapshot["spending_events"][0]["user_net_amount"] == "0"


@pytest.mark.parametrize(
    ("share_role", "parsed_amount", "expected_amount"),
    [
        (AmountRole.USER_NET_EXPENSE, Decimal(0), Decimal(40)),
        (AmountRole.USER_NET_EXPENSE, Decimal(40), Decimal(40)),
        (AmountRole.UNKNOWN, Decimal(0), Decimal(0)),
        (AmountRole.UNKNOWN, Decimal(80), Decimal(0)),
    ],
)
def test_third_party_total_does_not_become_user_share(
    session: Session,
    share_role: AmountRole,
    parsed_amount: Decimal,
    expected_amount: Decimal,
) -> None:
    source = "A friend paid 80 CAD for dinner; my possible share was 40 CAD."
    parsed = StoryParseResponse(
        summary="The friend's payment needs clarification.",
        spending_events=[
            SpendingEvent(
                title="Dinner",
                category=ExpenseCategory.DINING,
                event_date=date(2026, 8, 8),
                payer_type=PayerType.OTHER_PERSON,
                paid_by_name="friend",
                user_net_amount=parsed_amount,
                currency=CurrencyCode.CAD,
                amount_mentions=[
                    AmountMention(
                        amount=Decimal(80),
                        currency=CurrencyCode.CAD,
                        role=AmountRole.PAID_BY_OTHER,
                        counted_in_user_total=False,
                        source_text="80 CAD",
                        confidence=1,
                        explanation="The friend paid the dinner total.",
                    ),
                    AmountMention(
                        amount=Decimal(40),
                        currency=CurrencyCode.CAD,
                        role=share_role,
                        counted_in_user_total=False,
                        source_text="40 CAD",
                        confidence=0.8,
                        explanation="Possible user share.",
                    ),
                ],
                source_text=source,
                confidence=0.8,
                needs_confirmation=True,
            )
        ],
        total_user_expense=Decimal(0),
        total_paid_by_others=Decimal(80),
        total_saved_decisions=Decimal(0),
        parser_confidence=0.8,
    )
    service = ClarificationService(session)
    draft = service.create_from_parse(source, parsed)
    event = draft.draft.events[0].event
    question = next(item for item in draft.clarifications if item.status == "open")

    assert event.user_net_amount == expected_amount
    assert "paid 80 CAD" in question.question
    if expected_amount == 0:
        assert "Confirm your amount during review" in question.question
    else:
        assert "your share 40 CAD" in question.question

    clarified = service.answer(
        draft.draft.id,
        answer_request(draft, question, "repaid_by_user"),
    )
    assert clarified.draft.events[0].event.user_net_amount == expected_amount
    assert clarified.draft.events[0].event.event_date is None


def test_mismatched_parser_settlement_question_is_superseded_for_canonical_event(
    session: Session,
) -> None:
    parser_question = ConfirmationQuestion(
        question=(
            "Was this a treat from your mother (you owe nothing), or do you plan "
            "to reimburse her for the 18 CAD?"
        ),
        reason="The answer determines whether this is the user's expense.",
        related_source_text="mother covered coffee",
    )
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
                        confidence=0.9,
                        explanation="Mother initially paid.",
                    )
                ],
                source_text="I bought coffee beans for 18 CAD, but my mother paid.",
                confidence=0.9,
            )
        ],
        confirmation_questions=[parser_question],
        total_user_expense=Decimal(0),
        total_paid_by_others=Decimal(18),
        total_saved_decisions=Decimal(0),
        parser_confidence=0.9,
    )
    service = ClarificationService(session)

    initial = service.create_from_parse("My mother paid for my coffee beans.", parsed)

    open_questions = [item for item in initial.clarifications if item.status == "open"]
    superseded_questions = [item for item in initial.clarifications if item.status == "superseded"]
    assert len(open_questions) == 1
    assert len(superseded_questions) == 1
    canonical = open_questions[0]
    redundant = superseded_questions[0]
    assert canonical.related_event_id == initial.draft.events[0].id
    assert canonical.question == (
        "Your mother paid 18 CAD for coffee beans. What happened afterward?"
    )
    assert redundant.question == parser_question.question
    assert redundant.reason == parser_question.reason
    assert redundant.related_source_text == parser_question.related_source_text
    assert redundant.answer is None

    without_parser_question = service.create_from_parse(
        "My mother paid for my coffee beans.",
        parsed.model_copy(update={"confirmation_questions": []}),
    )
    assert len(without_parser_question.clarifications) == 1
    assert without_parser_question.clarifications[0].status == "open"
    assert (
        without_parser_question.clarifications[0].related_event_id
        == without_parser_question.draft.events[0].id
    )

    updated = service.answer(
        initial.draft.id,
        answer_request(initial, canonical, "paid_by_other"),
    )

    assert updated.clarification_state == "ready_for_review"
    assert [item.status for item in updated.clarifications] == ["superseded", "answered"]
    event = updated.draft.events[0]
    assert event.event.settlement_status == SettlementStatus.COVERED_BY_OTHER
    assert event.event.user_net_amount == Decimal(0)
    assert event.disposition == DraftEventDisposition.EXCLUDE

    with pytest.raises(FinancialDraftConflictError, match="stale or already answered"):
        service.answer(
            initial.draft.id,
            ClarificationAnswersRequest(
                expected_version=updated.draft.version,
                answers=[
                    ClarificationAnswer(
                        question_id=redundant.id,
                        option_key="keep_unresolved",
                    )
                ],
            ),
        )


@pytest.mark.parametrize(
    ("option", "settlement", "amount", "disposition"),
    [
        ("paid_by_other", SettlementStatus.COVERED_BY_OTHER, Decimal(0), "exclude"),
        ("repaid_by_user", SettlementStatus.REPAID_BY_USER, Decimal(18), "pending"),
        ("repayment_due", SettlementStatus.REPAYMENT_DUE, Decimal(18), "exclude"),
    ],
)
def test_settlement_options_apply_deterministically(
    session: Session,
    option: str,
    settlement: SettlementStatus,
    amount: Decimal,
    disposition: str,
) -> None:
    service = ClarificationService(session)
    initial = service.create_from_parse("journal", parsed_story())

    updated = service.answer(
        initial.draft.id,
        answer_request(initial, initial.clarifications[0], option),
    )

    event = updated.draft.events[0]
    assert event.event.settlement_status == settlement
    assert event.event.user_net_amount == amount
    assert event.event.needs_confirmation is False
    assert event.disposition == disposition
