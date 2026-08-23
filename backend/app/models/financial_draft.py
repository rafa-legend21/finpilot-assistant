from __future__ import annotations

from datetime import datetime
from typing import Any
from uuid import UUID, uuid4

from sqlalchemy import JSON, DateTime, ForeignKey, Integer, String, Uuid, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base


class FinancialDraft(Base):
    __tablename__ = "financial_drafts"

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="draft", index=True)
    original_snapshot: Mapped[dict[str, Any]] = mapped_column(JSON, nullable=False)
    original_journal: Mapped[str | None] = mapped_column(String(10000))
    working_metadata: Mapped[dict[str, Any]] = mapped_column(JSON, nullable=False)
    clarification_state: Mapped[str] = mapped_column(
        String(30), nullable=False, default="ready_for_review"
    )
    version: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now(), onupdate=func.now()
    )
    confirmed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    cancelled_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    events: Mapped[list[FinancialDraftEvent]] = relationship(
        back_populates="draft",
        cascade="all, delete-orphan",
        order_by="FinancialDraftEvent.position",
    )
    clarifications: Mapped[list[FinancialDraftClarification]] = relationship(
        back_populates="draft",
        cascade="all, delete-orphan",
        order_by="FinancialDraftClarification.sequence",
    )


class FinancialDraftEvent(Base):
    __tablename__ = "financial_draft_events"

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    draft_id: Mapped[UUID] = mapped_column(
        Uuid,
        ForeignKey("financial_drafts.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    position: Mapped[int] = mapped_column(Integer, nullable=False)
    disposition: Mapped[str] = mapped_column(String(20), nullable=False, default="pending")
    event_payload: Mapped[dict[str, Any]] = mapped_column(JSON, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now(), onupdate=func.now()
    )

    draft: Mapped[FinancialDraft] = relationship(back_populates="events")


class FinancialDraftClarification(Base):
    __tablename__ = "financial_draft_clarifications"

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    draft_id: Mapped[UUID] = mapped_column(
        Uuid,
        ForeignKey("financial_drafts.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    sequence: Mapped[int] = mapped_column(Integer, nullable=False)
    round_number: Mapped[int] = mapped_column(Integer, nullable=False)
    semantic_key: Mapped[str] = mapped_column(String(255), nullable=False)
    requirement: Mapped[str] = mapped_column(String(30), nullable=False)
    issue_type: Mapped[str] = mapped_column(String(50), nullable=False)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="open")
    question: Mapped[str] = mapped_column(String(500), nullable=False)
    reason: Mapped[str] = mapped_column(String(500), nullable=False)
    related_event_id: Mapped[UUID | None] = mapped_column(
        Uuid,
        ForeignKey("financial_draft_events.id", ondelete="SET NULL"),
    )
    related_source_text: Mapped[str] = mapped_column(String(10000), nullable=False)
    options_payload: Mapped[list[dict[str, Any]]] = mapped_column(JSON, nullable=False)
    answer_payload: Mapped[dict[str, Any] | None] = mapped_column(JSON)
    resolution_method: Mapped[str | None] = mapped_column(String(30))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    answered_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    draft: Mapped[FinancialDraft] = relationship(back_populates="clarifications")
