from datetime import date, datetime
from decimal import Decimal
from uuid import UUID

from sqlalchemy import (
    JSON,
    CheckConstraint,
    Date,
    DateTime,
    ForeignKey,
    Integer,
    Numeric,
    String,
    UniqueConstraint,
    Uuid,
    func,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class Transaction(Base):
    __tablename__ = "transactions"
    __table_args__ = (
        UniqueConstraint(
            "source_draft_id",
            "source_event_id",
            name="uq_transactions_draft_event",
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    version: Mapped[int] = mapped_column(Integer, nullable=False, default=1, server_default="1")
    voided_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    merchant: Mapped[str | None] = mapped_column(
        String(150),
        nullable=True,
        index=True,
    )

    amount: Mapped[Decimal] = mapped_column(
        Numeric(12, 2),
        nullable=False,
    )

    currency: Mapped[str] = mapped_column(
        String(3),
        nullable=False,
        default="CAD",
    )

    category: Mapped[str] = mapped_column(
        String(50),
        nullable=False,
        default="Other",
        index=True,
    )

    transaction_date: Mapped[date] = mapped_column(
        Date,
        nullable=False,
        index=True,
    )

    bank: Mapped[str | None] = mapped_column(
        String(50),
        nullable=True,
    )

    account_last4: Mapped[str | None] = mapped_column(
        String(4),
        nullable=True,
    )

    note: Mapped[str | None] = mapped_column(
        String(500),
        nullable=True,
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )

    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
        onupdate=func.now(),
    )

    source_draft_id: Mapped[UUID | None] = mapped_column(
        Uuid,
        ForeignKey("financial_drafts.id"),
        nullable=True,
    )
    source_event_id: Mapped[UUID | None] = mapped_column(
        Uuid,
        ForeignKey("financial_draft_events.id"),
        nullable=True,
    )


class TransactionCorrection(Base):
    __tablename__ = "transaction_corrections"
    __table_args__ = (
        CheckConstraint("action IN ('edit', 'void')", name="ck_transaction_corrections_action"),
        CheckConstraint(
            "version_after = version_before + 1",
            name="ck_transaction_corrections_version",
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    transaction_id: Mapped[int] = mapped_column(
        ForeignKey("transactions.id", ondelete="RESTRICT"), nullable=False, index=True
    )
    version_before: Mapped[int] = mapped_column(Integer, nullable=False)
    version_after: Mapped[int] = mapped_column(Integer, nullable=False)
    action: Mapped[str] = mapped_column(String(10), nullable=False)
    reason: Mapped[str] = mapped_column(String(500), nullable=False)
    before_state: Mapped[dict] = mapped_column(JSON().with_variant(JSONB, "postgresql"))
    after_state: Mapped[dict] = mapped_column(JSON().with_variant(JSONB, "postgresql"))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
