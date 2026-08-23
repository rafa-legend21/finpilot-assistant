from fastapi import APIRouter

from app.api.health import router as health_router
from app.api.routes.financial_drafts import router as financial_drafts_router
from app.api.routes.story_parser import router as story_parser_router

api_router = APIRouter()

api_router.include_router(health_router)
api_router.include_router(story_parser_router)
api_router.include_router(financial_drafts_router)
