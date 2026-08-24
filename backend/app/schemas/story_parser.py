from __future__ import annotations

from datetime import date
from decimal import Decimal
from enum import StrEnum
from typing import Annotated

from pydantic import BaseModel, Field, field_validator, model_validator

MoneyAmount = Annotated[
    Decimal,
    Field(
        ge=Decimal(0),
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


class SettlementStatus(StrEnum):
    COVERED_BY_OTHER = "covered_by_other"
    REPAID_BY_USER = "repaid_by_user"
    REPAYMENT_DUE = "repayment_due"
    UNRESOLVED = "unresolved"
    NOT_APPLICABLE = "not_applicable"


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

    @model_validator(mode="after")
    def validate_user_total_role(self) -> AmountMention:
        roles_excluded_from_user_total = {
            AmountRole.INCLUDED_DETAIL,
            AmountRole.COMMENTARY_PRICE,
            AmountRole.QUOTED_PRICE,
            AmountRole.PLANNED_EXPENSE,
            AmountRole.PAID_BY_OTHER,
        }
        if self.counted_in_user_total and self.role in roles_excluded_from_user_total:
            raise ValueError(
                f"Amounts with role {self.role.value} cannot count toward user totals."
            )
        return self


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
    settlement_status: SettlementStatus = SettlementStatus.NOT_APPLICABLE

    user_net_amount: MoneyAmount
    currency: CurrencyCode = CurrencyCode.CAD

    amount_mentions: list[AmountMention] = Field(default_factory=list)
    quantities: list[QuantityMention] = Field(default_factory=list)

    source_text: str = Field(min_length=1)
    confidence: Confidence
    needs_confirmation: bool = False

    @field_validator("merchant", mode="before")
    @classmethod
    def normalize_unknown_merchant(cls, value: object) -> object:
        if isinstance(value, str) and not value.strip():
            return None
        return value

    @model_validator(mode="after")
    def validate_counted_amounts(self) -> SpendingEvent:
        """
        Prevent accidental double counting.

        The counted amount mentions may not exceed the user's final net
        amount unless the event is explicitly awaiting confirmation.
        """
        counted_total = sum(
            (mention.amount for mention in self.amount_mentions if mention.counted_in_user_total),
            start=Decimal(0),
        )

        counted_currencies = {
            mention.currency for mention in self.amount_mentions if mention.counted_in_user_total
        }
        if counted_currencies and counted_currencies != {self.currency}:
            raise ValueError("Counted amount mentions must use the spending event currency.")

        if (
            not self.needs_confirmation
            and self.settlement_status != SettlementStatus.REPAYMENT_DUE
            and counted_total != self.user_net_amount
        ):
            raise ValueError(
                "Counted amount mentions must equal user_net_amount for a confirmed spending event."
            )

        if self.settlement_status == SettlementStatus.UNRESOLVED and not self.needs_confirmation:
            raise ValueError("Unresolved settlement responsibility requires confirmation.")
        if (
            self.settlement_status == SettlementStatus.COVERED_BY_OTHER
            and (self.user_net_amount != 0 or counted_total != 0)
        ):
            raise ValueError("An expense covered by another person cannot count toward the user.")
        if self.settlement_status == SettlementStatus.REPAYMENT_DUE and counted_total != 0:
            raise ValueError("A repayment that is still due cannot count as completed cash outflow.")
        if self.payer_type != PayerType.OTHER_PERSON and self.settlement_status in {
            SettlementStatus.COVERED_BY_OTHER,
            SettlementStatus.REPAID_BY_USER,
            SettlementStatus.REPAYMENT_DUE,
            SettlementStatus.UNRESOLVED,
        }:
            raise ValueError("Third-party settlement states require another person as initial payer.")

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
    confirmation_questions: list[ConfirmationQuestion] = Field(default_factory=list)

    total_user_expense: MoneyAmount
    total_paid_by_others: MoneyAmount
    total_saved_decisions: MoneyAmount

    parser_confidence: Confidence
    draft_only: bool = True

    @model_validator(mode="after")
    def validate_financial_totals(self) -> StoryParseResponse:
        confirmed_user_expenses = [
            event
            for event in self.spending_events
            if event.transaction_type == TransactionType.EXPENSE
            and (
                event.payer_type in {PayerType.USER, PayerType.SHARED}
                or event.settlement_status == SettlementStatus.REPAID_BY_USER
            )
            and not event.needs_confirmation
        ]
        confirmed_currencies = {event.currency for event in confirmed_user_expenses}
        if len(confirmed_currencies) > 1:
            raise ValueError(
                "Cannot calculate total_user_expense across multiple currencies "
                "without currency conversion."
            )

        calculated_user_expense = sum(
            (event.user_net_amount for event in confirmed_user_expenses),
            start=Decimal(0),
        )
        if calculated_user_expense != self.total_user_expense:
            raise ValueError(
                "total_user_expense must equal the sum of confirmed user/shared expense events."
            )

        paid_by_other_mentions = [
            mention
            for event in self.spending_events
            for mention in event.amount_mentions
            if mention.role == AmountRole.PAID_BY_OTHER
        ]
        saved_decision_mentions = [
            mention
            for event in self.spending_events
            for mention in event.amount_mentions
            if mention.role == AmountRole.SAVED_DECISION
        ]
        self.total_paid_by_others = self._sum_single_currency_mentions(
            paid_by_other_mentions,
            "total_paid_by_others",
        )
        self.total_saved_decisions = self._sum_single_currency_mentions(
            saved_decision_mentions,
            "total_saved_decisions",
        )

        return self

    @staticmethod
    def _sum_single_currency_mentions(
        mentions: list[AmountMention],
        total_name: str,
    ) -> Decimal:
        currencies = {mention.currency for mention in mentions}
        if len(currencies) > 1:
            raise ValueError(
                f"Cannot calculate {total_name} across multiple currencies "
                "without currency conversion."
            )
        return sum(
            (mention.amount for mention in mentions),
            start=Decimal(0),
        )
