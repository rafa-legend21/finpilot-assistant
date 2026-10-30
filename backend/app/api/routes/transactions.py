from collections.abc import Callable
from datetime import date
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from app.db.dependencies import get_db_session
from app.schemas.story_parser import CurrencyCode
from app.schemas.transaction import (
    TransactionCorrectionResponse,
    TransactionEditRequest,
    TransactionListResponse,
    TransactionResponse,
    TransactionSummaryResponse,
    TransactionVoidRequest,
)
from app.services.transaction_service import (
    TransactionConflictError,
    TransactionNotFoundError,
    TransactionService,
)

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
    include_voided: bool = False,
) -> TransactionListResponse:
    _check_dates(start_date, end_date)
    return TransactionService(session).list(
        start_date=start_date,
        end_date=end_date,
        currency=currency,
        limit=limit,
        offset=offset,
        include_voided=include_voided,
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


def _handle_correction[T](operation: Callable[[], T]) -> T:
    try:
        return operation()
    except TransactionNotFoundError as exc:
        raise HTTPException(status_code=404, detail="Transaction not found.") from exc
    except TransactionConflictError as exc:
        raise HTTPException(
            status_code=409,
            detail="This record changed or was already voided. Refresh before trying again.",
        ) from exc


@router.get("/{transaction_id}", response_model=TransactionResponse)
def get_transaction(transaction_id: int, session: SessionDependency) -> TransactionResponse:
    return _handle_correction(lambda: TransactionService(session).get(transaction_id))


@router.get("/{transaction_id}/corrections", response_model=list[TransactionCorrectionResponse])
def get_transaction_corrections(
    transaction_id: int, session: SessionDependency
) -> list[TransactionCorrectionResponse]:
    return _handle_correction(lambda: TransactionService(session).history(transaction_id))


@router.patch("/{transaction_id}", response_model=TransactionResponse)
def edit_transaction(
    transaction_id: int, request: TransactionEditRequest, session: SessionDependency
) -> TransactionResponse:
    return _handle_correction(lambda: TransactionService(session).edit(transaction_id, request))


@router.post("/{transaction_id}/void", response_model=TransactionResponse)
def void_transaction(
    transaction_id: int, request: TransactionVoidRequest, session: SessionDependency
) -> TransactionResponse:
    return _handle_correction(lambda: TransactionService(session).void(transaction_id, request))
