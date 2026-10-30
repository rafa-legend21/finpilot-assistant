from __future__ import annotations

from datetime import UTC, date, datetime

from sqlalchemy import Select, func, select
from sqlalchemy.orm import Session

from app.models.transaction import Transaction, TransactionCorrection
from app.schemas.transaction import (
    CategoryTotal,
    DailyTotal,
    TransactionCorrectionResponse,
    TransactionEditRequest,
    TransactionListResponse,
    TransactionResponse,
    TransactionSummaryResponse,
    TransactionVoidRequest,
)


class TransactionNotFoundError(LookupError):
    pass


class TransactionConflictError(ValueError):
    pass


class TransactionService:
    def __init__(self, session: Session) -> None:
        self.session = session

    @staticmethod
    def _filtered(
        *,
        start_date: date | None,
        end_date: date | None,
        currency: str | None,
        include_voided: bool = False,
    ) -> Select[tuple[Transaction]]:
        statement = select(Transaction)
        if not include_voided:
            statement = statement.where(Transaction.voided_at.is_(None))
        if start_date is not None:
            statement = statement.where(Transaction.transaction_date >= start_date)
        if end_date is not None:
            statement = statement.where(Transaction.transaction_date <= end_date)
        if currency is not None:
            statement = statement.where(Transaction.currency == currency)
        return statement

    def list(
        self,
        *,
        start_date: date | None,
        end_date: date | None,
        currency: str | None,
        limit: int,
        offset: int,
        include_voided: bool = False,
    ) -> TransactionListResponse:
        filtered = self._filtered(
            start_date=start_date,
            end_date=end_date,
            currency=currency,
            include_voided=include_voided,
        )
        total_count = (
            self.session.scalar(select(func.count()).select_from(filtered.subquery())) or 0
        )
        rows = self.session.scalars(
            filtered.order_by(Transaction.transaction_date.desc(), Transaction.id.desc())
            .limit(limit)
            .offset(offset)
        ).all()
        return TransactionListResponse(
            transactions=[TransactionResponse.model_validate(row) for row in rows],
            total_count=total_count,
        )

    def summary(
        self, *, start_date: date | None, end_date: date | None, currency: str | None
    ) -> TransactionSummaryResponse:
        filtered = self._filtered(start_date=start_date, end_date=end_date, currency=currency)
        base = filtered.subquery()
        currency_rows = self.session.execute(
            select(base.c.currency, func.sum(base.c.amount))
            .group_by(base.c.currency)
            .order_by(base.c.currency)
        )
        date_rows = self.session.execute(
            select(base.c.transaction_date, base.c.currency, func.sum(base.c.amount))
            .group_by(base.c.transaction_date, base.c.currency)
            .order_by(base.c.transaction_date, base.c.currency)
        )
        category_rows = self.session.execute(
            select(base.c.category, base.c.currency, func.sum(base.c.amount))
            .group_by(base.c.category, base.c.currency)
            .order_by(base.c.category, base.c.currency)
        )
        return TransactionSummaryResponse(
            totals_by_currency={row_currency: amount for row_currency, amount in currency_rows},
            by_date=[
                DailyTotal(date=day, currency=row_currency, amount=amount)
                for day, row_currency, amount in date_rows
            ],
            by_category=[
                CategoryTotal(category=category, currency=row_currency, amount=amount)
                for category, row_currency, amount in category_rows
            ],
        )

    def get(self, transaction_id: int) -> TransactionResponse:
        row = self.session.get(Transaction, transaction_id)
        if row is None:
            raise TransactionNotFoundError
        return TransactionResponse.model_validate(row)

    def history(self, transaction_id: int) -> list[TransactionCorrectionResponse]:
        if self.session.get(Transaction, transaction_id) is None:
            raise TransactionNotFoundError
        rows = self.session.scalars(
            select(TransactionCorrection)
            .where(TransactionCorrection.transaction_id == transaction_id)
            .order_by(TransactionCorrection.version_after)
        ).all()
        return [TransactionCorrectionResponse.model_validate(row) for row in rows]

    def edit(self, transaction_id: int, request: TransactionEditRequest) -> TransactionResponse:
        row = self._locked(transaction_id, request.expected_version)
        before = self._snapshot(row)
        row.amount = request.amount
        row.currency = request.currency
        row.category = request.category.value
        row.transaction_date = request.transaction_date
        row.merchant = request.merchant
        row.note = request.note
        row.version += 1
        self._record(row, "edit", request.reason, before)
        self.session.commit()
        self.session.refresh(row)
        return TransactionResponse.model_validate(row)

    def void(self, transaction_id: int, request: TransactionVoidRequest) -> TransactionResponse:
        row = self._locked(transaction_id, request.expected_version)
        before = self._snapshot(row)
        row.voided_at = datetime.now(UTC)
        row.version += 1
        self._record(row, "void", request.reason, before)
        self.session.commit()
        self.session.refresh(row)
        return TransactionResponse.model_validate(row)

    def _locked(self, transaction_id: int, expected_version: int) -> Transaction:
        row = self.session.scalar(
            select(Transaction).where(Transaction.id == transaction_id).with_for_update()
        )
        if row is None:
            raise TransactionNotFoundError
        if row.version != expected_version or row.voided_at is not None:
            raise TransactionConflictError
        return row

    def _record(
        self, row: Transaction, action: str, reason: str, before: dict[str, str | None]
    ) -> None:
        self.session.add(
            TransactionCorrection(
                transaction_id=row.id,
                version_before=row.version - 1,
                version_after=row.version,
                action=action,
                reason=reason,
                before_state=before,
                after_state=self._snapshot(row),
            )
        )

    @staticmethod
    def _snapshot(row: Transaction) -> dict[str, str | None]:
        return {
            "amount": str(row.amount),
            "currency": row.currency,
            "category": row.category,
            "transaction_date": row.transaction_date.isoformat(),
            "merchant": row.merchant,
            "note": row.note,
            "voided_at": row.voided_at.isoformat() if row.voided_at else None,
        }
