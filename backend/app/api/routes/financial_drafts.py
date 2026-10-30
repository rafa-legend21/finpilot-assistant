from collections.abc import Callable
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.db.dependencies import get_db_session
from app.schemas.financial_draft import (
    ClarificationAnswersRequest,
    ClarifyingFinancialDraftResponse,
    FinancialDraftConfirmationResponse,
    FinancialDraftCreateRequest,
    FinancialDraftEventUpdate,
    FinancialDraftResponse,
    FinancialDraftVersionRequest,
    JournalDraftCreateRequest,
)
from app.schemas.story_parser import StoryParseRequest
from app.services.clarification_service import ClarificationService
from app.services.financial_draft_service import (
    FinancialDraftConflictError,
    FinancialDraftNotFoundError,
    FinancialDraftService,
    FinancialDraftValidationError,
)
from app.services.story_parser_service import (
    StoryParserConfigurationError,
    StoryParserOutputError,
    StoryParserService,
)

router = APIRouter(prefix="/financial-drafts", tags=["financial-drafts"])


def service(session: Annotated[Session, Depends(get_db_session)]) -> FinancialDraftService:
    return FinancialDraftService(session)


DraftService = Annotated[FinancialDraftService, Depends(service)]
SessionDependency = Annotated[Session, Depends(get_db_session)]


@router.post(
    "/from-journal",
    response_model=ClarifyingFinancialDraftResponse,
    status_code=status.HTTP_201_CREATED,
)
def create_draft_from_journal(
    request: JournalDraftCreateRequest,
    session: SessionDependency,
) -> ClarifyingFinancialDraftResponse:
    try:
        parsed = StoryParserService().parse(
            StoryParseRequest(
                text=request.text,
                default_currency=request.default_currency,
                reference_date=request.reference_date,
                response_language=request.response_language,
            )
        )
    except StoryParserConfigurationError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Story parsing is temporarily unavailable. Please try again.",
        ) from exc
    except StoryParserOutputError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="FinPilot could not process the journal right now. Please try again.",
        ) from exc
    return ClarificationService(session).create_from_parse(
        request.text, parsed, response_language=request.response_language
    )


@router.get(
    "/{draft_id}/clarifications",
    response_model=ClarifyingFinancialDraftResponse,
)
def get_clarifications(
    draft_id: UUID,
    session: SessionDependency,
) -> ClarifyingFinancialDraftResponse:
    return _handle(lambda: ClarificationService(session).get(draft_id))


@router.post(
    "/{draft_id}/clarifications/answers",
    response_model=ClarifyingFinancialDraftResponse,
)
def answer_clarifications(
    draft_id: UUID,
    request: ClarificationAnswersRequest,
    session: SessionDependency,
) -> ClarifyingFinancialDraftResponse:
    return _handle(lambda: ClarificationService(session).answer(draft_id, request))


@router.post("", response_model=FinancialDraftResponse, status_code=status.HTTP_201_CREATED)
def create_draft(
    request: FinancialDraftCreateRequest,
    draft_service: DraftService,
) -> FinancialDraftResponse:
    return draft_service.create(request)


@router.get("/{draft_id}", response_model=FinancialDraftResponse)
def get_draft(
    draft_id: UUID,
    draft_service: DraftService,
) -> FinancialDraftResponse:
    return _handle(lambda: draft_service.get(draft_id))


@router.patch("/{draft_id}/events/{event_id}", response_model=FinancialDraftResponse)
def update_draft_event(
    draft_id: UUID,
    event_id: UUID,
    request: FinancialDraftEventUpdate,
    draft_service: DraftService,
) -> FinancialDraftResponse:
    return _handle(lambda: draft_service.update_event(draft_id, event_id, request))


@router.post("/{draft_id}/confirm", response_model=FinancialDraftConfirmationResponse)
def confirm_draft(
    draft_id: UUID,
    request: FinancialDraftVersionRequest,
    draft_service: DraftService,
) -> FinancialDraftConfirmationResponse:
    return _handle(lambda: draft_service.confirm(draft_id, request.expected_version))


@router.post("/{draft_id}/cancel", response_model=FinancialDraftResponse)
def cancel_draft(
    draft_id: UUID,
    request: FinancialDraftVersionRequest,
    draft_service: DraftService,
) -> FinancialDraftResponse:
    return _handle(lambda: draft_service.cancel(draft_id, request.expected_version))


def _handle[Result](operation: Callable[[], Result]) -> Result:
    try:
        return operation()
    except FinancialDraftNotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc
    except (FinancialDraftConflictError, IntegrityError) as exc:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc)) from exc
    except FinancialDraftValidationError as exc:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(exc)) from exc
