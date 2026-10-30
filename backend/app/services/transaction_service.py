from datetime import date

from sqlalchemy import Select, func, select
from sqlalchemy.orm import Session

from app.models.transaction import Transaction
from app.schemas.transaction import (
    CategoryTotal,
    DailyTotal,
    TransactionListResponse,
    TransactionResponse,
    TransactionSummaryResponse,
)


class TransactionService:
    def __init__(self, session: Session) -> None:
        self.session = session

    @staticmethod
    def _filtered(
        *, start_date: date | None, end_date: date | None, currency: str | None
    ) -> Select[tuple[Transaction]]:
        statement = select(Transaction)
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
    ) -> TransactionListResponse:
        filtered = self._filtered(start_date=start_date, end_date=end_date, currency=currency)
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
