from decimal import Decimal

import pytest
from pydantic import ValidationError

from app.schemas.story_parser import (
    AmountMention,
    AmountRole,
    CurrencyCode,
    ExpenseCategory,
    MoodObservation,
    MoodType,
    PayerType,
    QuantityMention,
    SpendingEvent,
    StoryParseResponse,
)


def amount(
    value: str,
    role: AmountRole,
    *,
    counted: bool = False,
    currency: CurrencyCode = CurrencyCode.CAD,
) -> AmountMention:
    return AmountMention(
        amount=Decimal(value),
        currency=currency,
        role=role,
        counted_in_user_total=counted,
        source_text=value,
        confidence=1.0,
        explanation="Test amount.",
    )


def event(
    value: str,
    *,
    payer: PayerType = PayerType.USER,
    needs_confirmation: bool = False,
    mentions: list[AmountMention] | None = None,
    quantities: list[QuantityMention] | None = None,
    currency: CurrencyCode = CurrencyCode.CAD,
) -> SpendingEvent:
    return SpendingEvent(
        title="Test event",
        category=ExpenseCategory.DINING,
        payer_type=payer,
        user_net_amount=Decimal(value),
        currency=currency,
        amount_mentions=mentions
        if mentions is not None
        else [amount(value, AmountRole.EVENT_TOTAL, counted=True, currency=currency)],
        quantities=quantities or [],
        source_text="Test event source.",
        confidence=1.0,
        needs_confirmation=needs_confirmation,
    )


def response(
    events: list[SpendingEvent],
    total_user_expense: str,
    *,
    moods: list[MoodObservation] | None = None,
) -> StoryParseResponse:
    return StoryParseResponse(
        summary="Test response.",
        spending_events=events,
        moods=moods or [],
        total_user_expense=Decimal(total_user_expense),
        total_paid_by_others=Decimal(999),
        total_saved_decisions=Decimal(999),
        parser_confidence=1.0,
    )


def test_dinner_total_does_not_double_count_included_drink() -> None:
    dinner = event(
        "80",
        mentions=[
            amount("80", AmountRole.EVENT_TOTAL, counted=True),
            amount("33", AmountRole.INCLUDED_DETAIL),
        ],
    )

    result = response([dinner], "80")

    assert result.total_user_expense == Decimal(80)
    assert result.total_paid_by_others == Decimal(0)
    assert result.total_saved_decisions == Decimal(0)


def test_six_ounces_is_a_quantity_not_money() -> None:
    coffee = event(
        "0",
        payer=PayerType.OTHER_PERSON,
        mentions=[],
        quantities=[
            QuantityMention(
                value=Decimal(6),
                unit="ounces",
                item="coffee beans",
                source_text="6 ounces of coffee beans",
            )
        ],
    )

    result = response([coffee], "0")

    assert coffee.amount_mentions == []
    assert coffee.quantities[0].value == Decimal(6)
    assert result.total_user_expense == Decimal(0)


@pytest.mark.parametrize("value,payer_name", [("18", "mother"), ("8", "friend")])
def test_amount_paid_by_someone_else_is_not_user_expense(
    value: str,
    payer_name: str,
) -> None:
    paid_by_other = event(
        "0",
        payer=PayerType.OTHER_PERSON,
        mentions=[amount(value, AmountRole.PAID_BY_OTHER)],
    )
    paid_by_other.paid_by_name = payer_name

    result = response([paid_by_other], "0")

    assert result.total_user_expense == Decimal(0)
    assert result.total_paid_by_others == Decimal(value)


def test_ambiguous_payment_is_excluded_from_confirmed_total() -> None:
    confirmed = event("80")
    ambiguous = event("25", needs_confirmation=True)

    result = response([confirmed, ambiguous], "80")

    assert result.total_user_expense == Decimal(80)


def test_confirmed_cad_and_usd_expenses_cannot_be_summed() -> None:
    with pytest.raises(ValidationError, match="multiple currencies"):
        response(
            [event("10"), event("12", currency=CurrencyCode.USD)],
            "22",
        )


@pytest.mark.parametrize(
    "role",
    [AmountRole.PAID_BY_OTHER, AmountRole.INCLUDED_DETAIL],
)
def test_non_user_amount_cannot_be_counted_in_user_total(role: AmountRole) -> None:
    with pytest.raises(ValidationError, match="cannot count toward user totals"):
        amount("18", role, counted=True)


def test_tired_and_happy_moods_can_coexist() -> None:
    moods = [
        MoodObservation(mood=MoodType.TIRED, confidence=0.9, evidence="tired", intensity=4),
        MoodObservation(mood=MoodType.HAPPY, confidence=0.9, evidence="happy", intensity=4),
    ]

    result = response([], "0", moods=moods)

    assert {observation.mood for observation in result.moods} == {
        MoodType.TIRED,
        MoodType.HAPPY,
    }
