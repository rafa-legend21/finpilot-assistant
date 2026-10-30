from datetime import date, datetime
from decimal import Decimal
from uuid import UUID

from pydantic import BaseModel, ConfigDict


class TransactionResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    merchant: str | None
    amount: Decimal
    currency: str
    category: str
    transaction_date: date
    note: str | None
    created_at: datetime
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
