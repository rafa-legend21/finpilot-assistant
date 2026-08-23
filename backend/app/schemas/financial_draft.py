from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal
from enum import StrEnum
from typing import Any
from uuid import UUID

from pydantic import BaseModel, Field, model_validator

from app.schemas.story_parser import (
    ConfirmationQuestion,
    CurrencyCode,
    LifeEvent,
    MoodObservation,
    SpendingEvent,
)


class DraftStatus(StrEnum):
    DRAFT = "draft"
    CONFIRMED = "confirmed"
    CANCELLED = "cancelled"


class DraftEventDisposition(StrEnum):
    PENDING = "pending"
    INCLUDE = "include"
    EXCLUDE = "exclude"


class ClarificationWorkflowState(StrEnum):
    AWAITING_REQUIRED = "awaiting_required"
    READY_FOR_REVIEW = "ready_for_review"


class ClarificationRequirement(StrEnum):
    REQUIRED = "required"
    OPTIONAL = "optional"
    CONFIDENCE_ONLY = "confidence_only"


class ClarificationStatus(StrEnum):
    OPEN = "open"
    ANSWERED = "answered"
    SUPERSEDED = "superseded"


class ClarificationIssueType(StrEnum):
    PAYER_RESPONSIBILITY = "payer_responsibility"
    INCLUDED_OR_SEPARATE = "included_or_separate_amount"
    PURCHASE_CONFIRMATION = "purchase_confirmation"
    REIMBURSEMENT = "reimbursement"
    SHARED_AMOUNT = "shared_amount"
    CURRENCY = "currency"
    EVENT_BOUNDARY = "event_boundary"
    OTHER = "other"


class SubmittedStoryParseResponse(BaseModel):
    """Untrusted parser-shaped input; submitted aggregate totals are informational only."""

    summary: str
    spending_events: list[SpendingEvent] = Field(default_factory=list)
    moods: list[MoodObservation] = Field(default_factory=list)
    life_events: list[LifeEvent] = Field(default_factory=list)
    confirmation_questions: list[ConfirmationQuestion] = Field(default_factory=list)
    total_user_expense: Decimal = Field(ge=0)
    total_paid_by_others: Decimal = Field(ge=0)
    total_saved_decisions: Decimal = Field(ge=0)
    parser_confidence: float = Field(ge=0, le=1)
    draft_only: bool = True


class FinancialDraftCreateRequest(BaseModel):
    story_parse_response: SubmittedStoryParseResponse


class FinancialDraftEventResponse(BaseModel):
    id: UUID
    position: int
    disposition: DraftEventDisposition
    event: SpendingEvent


class FinancialDraftResponse(BaseModel):
    id: UUID
    status: DraftStatus
    version: int
    original_snapshot: dict[str, Any]
    summary: str
    moods: list[MoodObservation]
    life_events: list[LifeEvent]
    confirmation_questions: list[ConfirmationQuestion]
    events: list[FinancialDraftEventResponse]
    totals_by_currency: dict[CurrencyCode, Decimal]
    created_at: datetime
    updated_at: datetime
    confirmed_at: datetime | None
    cancelled_at: datetime | None


class FinancialDraftEventUpdate(BaseModel):
    expected_version: int = Field(ge=1)
    disposition: DraftEventDisposition
    event: SpendingEvent


class FinancialDraftVersionRequest(BaseModel):
    expected_version: int = Field(ge=1)


class FinancialDraftConfirmationResponse(BaseModel):
    draft: FinancialDraftResponse
    transaction_ids: list[int]


class JournalDraftCreateRequest(BaseModel):
    text: str = Field(min_length=1, max_length=10_000)
    default_currency: CurrencyCode = CurrencyCode.CAD
    reference_date: date | None = None


class ClarificationOption(BaseModel):
    option_key: str
    label: str


class DraftClarificationQuestion(BaseModel):
    id: UUID
    sequence: int
    round_number: int
    requirement: ClarificationRequirement
    issue_type: ClarificationIssueType
    status: ClarificationStatus
    question: str
    reason: str
    related_event_id: UUID | None
    related_source_text: str
    options: list[ClarificationOption]
    answer: dict[str, Any] | None


class ClarificationAnswer(BaseModel):
    question_id: UUID
    option_key: str | None = None
    free_text: str | None = Field(default=None, min_length=1, max_length=2000)

    @model_validator(mode="after")
    def validate_answer_shape(self) -> ClarificationAnswer:
        if (self.option_key is None) == (self.free_text is None):
            raise ValueError("Provide exactly one option_key or free_text answer.")
        return self


class ClarificationAnswersRequest(BaseModel):
    expected_version: int = Field(ge=1)
    answers: list[ClarificationAnswer] = Field(min_length=1)


class ClarifyingFinancialDraftResponse(BaseModel):
    draft: FinancialDraftResponse
    clarification_state: ClarificationWorkflowState
    clarifications: list[DraftClarificationQuestion]


class ClarificationOperation(StrEnum):
    CONFIRM_AS_PARSED = "confirm_as_parsed"
    USER_PAID = "user_paid"
    PAID_BY_OTHER = "paid_by_other"
    REPAID_BY_USER = "repaid_by_user"
    REPAYMENT_DUE = "repayment_due"
    EXCLUDE_EVENT = "exclude_event"
    KEEP_UNRESOLVED = "keep_unresolved"


class ClarificationResolution(BaseModel):
    question_id: UUID
    operation: ClarificationOperation
    event_id: UUID | None = None
    explanation: str = Field(min_length=1, max_length=500)
