from fastapi import APIRouter, HTTPException, status

from app.schemas.story_parser import StoryParseRequest, StoryParseResponse
from app.services.story_parser_service import (
    StoryParserConfigurationError,
    StoryParserOutputError,
    StoryParserService,
)

router = APIRouter(
    prefix="/story-parser",
    tags=["story-parser"],
)


@router.post(
    "/parse",
    response_model=StoryParseResponse,
    status_code=status.HTTP_200_OK,
)
def parse_story(request: StoryParseRequest) -> StoryParseResponse:
    """
    Convert a natural-language life journal into a structured financial draft.

    Nothing is written to the permanent transaction ledger at this stage.
    """
    try:
        service = StoryParserService()
        return service.parse(request)

    except StoryParserConfigurationError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=str(exc),
        ) from exc

    except StoryParserOutputError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=str(exc),
        ) from exc

    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"{type(exc).__name__}: {exc}",
        ) from exc
