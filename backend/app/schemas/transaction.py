from datetime import date, datetime
from decimal import Decimal
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.schemas.story_parser import ExpenseCategory


class TransactionResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    version: int
    voided_at: datetime | None
    merchant: str | None
    amount: Decimal
    currency: str
    category: str
    transaction_date: date
    note: str | None
    created_at: datetime
    updated_at: datetime
    source_draft_id: UUID | None
    source_event_id: UUID | None


class TransactionListResponse(BaseModel):
    transactions: list[TransactionResponse]
    total_count: int


class DailyTotal(BaseModel):
    date: date
    currency: str
    amount: Decimal


class CategoryTotal(BaseModel):
    category: str
    currency: str
    amount: Decimal


class TransactionSummaryResponse(BaseModel):
    totals_by_currency: dict[str, Decimal]
    by_date: list[DailyTotal]
    by_category: list[CategoryTotal]


class TransactionEditRequest(BaseModel):
    expected_version: int = Field(ge=1)
    reason: str = Field(min_length=3, max_length=500)
    amount: Decimal = Field(gt=0, max_digits=12, decimal_places=2)
    currency: Literal["CAD", "USD", "CNY", "GBP", "EUR"]
    category: ExpenseCategory
    transaction_date: date
    merchant: str | None = Field(default=None, max_length=150)
    note: str | None = Field(default=None, max_length=500)

    @field_validator("reason")
    @classmethod
    def reason_not_blank(cls, value: str) -> str:
        value = value.strip()
        if len(value) < 3:
            raise ValueError("Explain why this record needs correction.")
        return value

    @field_validator("merchant", "note")
    @classmethod
    def trim_optional(cls, value: str | None) -> str | None:
        return value.strip() or None if value is not None else None

    @field_validator("category")
    @classmethod
    def category_is_spending(cls, value: ExpenseCategory) -> ExpenseCategory:
        if value in {
            ExpenseCategory.INCOME,
            ExpenseCategory.TRANSFER,
            ExpenseCategory.INVESTMENT,
        }:
            raise ValueError("Choose an expense category for a spending record.")
        return value


class TransactionVoidRequest(BaseModel):
    expected_version: int = Field(ge=1)
    reason: str = Field(min_length=3, max_length=500)

    @field_validator("reason")
    @classmethod
    def reason_not_blank(cls, value: str) -> str:
        value = value.strip()
        if len(value) < 3:
            raise ValueError("Explain why this record is being removed from spending.")
        return value


class TransactionCorrectionResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    transaction_id: int
    version_before: int
    version_after: int
    action: Literal["edit", "void"]
    reason: str
    before_state: dict[str, str | None]
    after_state: dict[str, str | None]
    created_at: datetime
