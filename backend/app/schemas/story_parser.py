from __future__ import annotations

from datetime import date
from decimal import Decimal
from enum import StrEnum
from typing import Annotated

from pydantic import BaseModel, Field, model_validator


MoneyAmount = Annotated[
    Decimal,
    Field(
        ge=Decimal("0"),
        max_digits=12,
        decimal_places=2,
    ),
]

Confidence = Annotated[
    float,
    Field(ge=0.0, le=1.0),
]


class CurrencyCode(StrEnum):
    CAD = "CAD"
    USD = "USD"
    CNY = "CNY"
    GBP = "GBP"
    EUR = "EUR"
    UNKNOWN = "UNKNOWN"


class ExpenseCategory(StrEnum):
    GROCERY = "grocery"
    DINING = "dining"
    TRANSPORTATION = "transportation"
    SHOPPING = "shopping"
    ENTERTAINMENT = "entertainment"
    HOUSING = "housing"
    UTILITIES = "utilities"
    HEALTHCARE = "healthcare"
    TRAVEL = "travel"
    EDUCATION = "education"
    SUBSCRIPTION = "subscription"
    INVESTMENT = "investment"
    TRANSFER = "transfer"
    INCOME = "income"
    OTHER = "other"


class TransactionType(StrEnum):
    EXPENSE = "expense"
    INCOME = "income"
    TRANSFER = "transfer"
    REFUND = "refund"
    REIMBURSEMENT = "reimbursement"


class PayerType(StrEnum):
    USER = "user"
    OTHER_PERSON = "other_person"
    SHARED = "shared"
    EMPLOYER = "employer"
    UNKNOWN = "unknown"


class AmountRole(StrEnum):
    # The amount actually counted toward the user's finances.
    USER_NET_EXPENSE = "user_net_expense"

    # Total price for one complete spending event.
    EVENT_TOTAL = "event_total"

    # A component already included in the event total.
    INCLUDED_DETAIL = "included_detail"

    # An item price mentioned for emphasis or commentary.
    COMMENTARY_PRICE = "commentary_price"

    # A quoted price where no purchase was confirmed.
    QUOTED_PRICE = "quoted_price"

    # A planned or considered future expense.
    PLANNED_EXPENSE = "planned_expense"

    # A purchase the user intentionally avoided.
    SAVED_DECISION = "saved_decision"

    # An amount paid by another person.
    PAID_BY_OTHER = "paid_by_other"

    # An amount refunded or reimbursed.
    REFUND_OR_REIMBURSEMENT = "refund_or_reimbursement"

    # The role cannot yet be determined.
    UNKNOWN = "unknown"


class MoodType(StrEnum):
    HAPPY = "happy"
    EXCITED = "excited"
    RELAXED = "relaxed"
    TIRED = "tired"
    STRESSED = "stressed"
    ANXIOUS = "anxious"
    SAD = "sad"
    FRUSTRATED = "frustrated"
    NEUTRAL = "neutral"
    MIXED = "mixed"


class LifeEventType(StrEnum):
    EXAM = "exam"
    HIGH_WORKLOAD = "high_workload"
    TRAVEL = "travel"
    SOCIAL_EVENT = "social_event"
    HEALTH_EVENT = "health_event"
    MOVING = "moving"
    NEW_JOB = "new_job"
    CELEBRATION = "celebration"
    OTHER = "other"


class QuantityMention(BaseModel):
    """A non-financial quantity, such as 6 ounces or 2 apples."""

    value: Decimal = Field(gt=0)
    unit: str = Field(min_length=1, max_length=40)
    item: str | None = Field(default=None, max_length=150)
    source_text: str = Field(min_length=1)

    model_config = {
        "str_strip_whitespace": True,
    }


class AmountMention(BaseModel):
    """One monetary amount mentioned inside a larger life event."""

    amount: MoneyAmount
    currency: CurrencyCode = CurrencyCode.CAD
    role: AmountRole
    counted_in_user_total: bool
    source_text: str = Field(min_length=1)
    confidence: Confidence
    explanation: str = Field(min_length=1, max_length=500)

    model_config = {
        "str_strip_whitespace": True,
    }


class MoodObservation(BaseModel):
    mood: MoodType
    confidence: Confidence
    evidence: str = Field(min_length=1, max_length=500)
    intensity: int = Field(ge=1, le=5)


class LifeEvent(BaseModel):
    event_type: LifeEventType
    title: str = Field(min_length=1, max_length=150)
    description: str = Field(min_length=1, max_length=1000)
    expected_financial_impact: str | None = Field(
        default=None,
        max_length=500,
    )
    confidence: Confidence


class SpendingEvent(BaseModel):
    """
    One complete financial event.

    An event can contain several amount mentions, but only the user's
    validated net amount is counted toward budgets.
    """

    title: str = Field(min_length=1, max_length=150)
    category: ExpenseCategory
    transaction_type: TransactionType = TransactionType.EXPENSE
    event_date: date | None = None

    merchant: str | None = Field(default=None, max_length=150)
    payer_type: PayerType = PayerType.UNKNOWN
    paid_by_name: str | None = Field(default=None, max_length=100)

    user_net_amount: MoneyAmount
    currency: CurrencyCode = CurrencyCode.CAD

    amount_mentions: list[AmountMention] = Field(default_factory=list)
    quantities: list[QuantityMention] = Field(default_factory=list)

    source_text: str = Field(min_length=1)
    confidence: Confidence
    needs_confirmation: bool = False

    @model_validator(mode="after")
    def validate_counted_amounts(self) -> SpendingEvent:
        """
        Prevent accidental double counting.

        The counted amount mentions may not exceed the user's final net
        amount unless the event is explicitly awaiting confirmation.
        """
        counted_total = sum(
            (
                mention.amount
                for mention in self.amount_mentions
                if mention.counted_in_user_total
            ),
            start=Decimal("0"),
        )

        if (
            not self.needs_confirmation
            and counted_total != self.user_net_amount
        ):
            raise ValueError(
                "Counted amount mentions must equal user_net_amount "
                "for a confirmed spending event."
            )

        return self


class ConfirmationQuestion(BaseModel):
    question: str = Field(min_length=1, max_length=500)
    reason: str = Field(min_length=1, max_length=500)
    related_source_text: str = Field(min_length=1)
    required_for_financial_accuracy: bool = True


class StoryParseRequest(BaseModel):
    text: str = Field(
        min_length=1,
        max_length=10_000,
        description="Natural-language journal or conversation text.",
    )
    default_currency: CurrencyCode = CurrencyCode.CAD
    reference_date: date | None = None

    model_config = {
        "str_strip_whitespace": True,
        "json_schema_extra": {
            "examples": [
                {
                    "text": (
                        "晚饭一共花了80块，里面那杯饮料居然33块，"
                        "太贵了。朋友请我喝奶茶，我没有付钱。"
                    ),
                    "default_currency": "CAD",
                }
            ]
        },
    }


class StoryParseResponse(BaseModel):
    summary: str
    spending_events: list[SpendingEvent] = Field(default_factory=list)
    moods: list[MoodObservation] = Field(default_factory=list)
    life_events: list[LifeEvent] = Field(default_factory=list)
    confirmation_questions: list[ConfirmationQuestion] = Field(
        default_factory=list
    )

    total_user_expense: MoneyAmount
    total_paid_by_others: MoneyAmount
    total_saved_decisions: MoneyAmount

    parser_confidence: Confidence
    draft_only: bool = True

    @model_validator(mode="after")
    def validate_total_user_expense(self) -> StoryParseResponse:
        calculated_total = sum(
            (
                event.user_net_amount
                for event in self.spending_events
                if event.transaction_type == TransactionType.EXPENSE
                and event.payer_type
                in {PayerType.USER, PayerType.SHARED}
            ),
            start=Decimal("0"),
        )

        confirmed_events = [
            event
            for event in self.spending_events
            if not event.needs_confirmation
        ]

        if confirmed_events and calculated_total != self.total_user_expense:
            raise ValueError(
                "total_user_expense must equal the sum of the user's "
                "confirmed expense events."
            )

        return self