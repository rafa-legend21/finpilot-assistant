from datetime import date
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from app.db.dependencies import get_db_session
from app.schemas.story_parser import CurrencyCode
from app.schemas.transaction import TransactionListResponse, TransactionSummaryResponse
from app.services.transaction_service import TransactionService

router = APIRouter(prefix="/transactions", tags=["transactions"])
SessionDependency = Annotated[Session, Depends(get_db_session)]


def _check_dates(start_date: date | None, end_date: date | None) -> None:
    if start_date is not None and end_date is not None and start_date > end_date:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail="start_date must be on or before end_date.",
        )


@router.get("", response_model=TransactionListResponse)
def list_transactions(
    session: SessionDependency,
    start_date: date | None = None,
    end_date: date | None = None,
    currency: CurrencyCode | None = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
    offset: Annotated[int, Query(ge=0)] = 0,
) -> TransactionListResponse:
    _check_dates(start_date, end_date)
    return TransactionService(session).list(
        start_date=start_date,
        end_date=end_date,
        currency=currency,
        limit=limit,
        offset=offset,
    )


@router.get("/summary", response_model=TransactionSummaryResponse)
def summarize_transactions(
    session: SessionDependency,
    start_date: date | None = None,
    end_date: date | None = None,
    currency: CurrencyCode | None = None,
) -> TransactionSummaryResponse:
    _check_dates(start_date, end_date)
    return TransactionService(session).summary(
        start_date=start_date, end_date=end_date, currency=currency
    )
