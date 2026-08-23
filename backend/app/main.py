from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.router import api_router
from app.core.config import get_settings

settings = get_settings()

app = FastAPI(
    title=settings.app_name,
    version="0.1.0",
    description="API for personal budgeting, transaction parsing, and financial insights.",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_origin_regex=settings.cors_origin_regex,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/", tags=["root"])
def root() -> dict[str, str]:
    return {
        "message": "FinPilot Assistant API",
        "docs": "/docs",
        "health": f"{settings.api_v1_prefix}/health",
    }


app.include_router(api_router, prefix=settings.api_v1_prefix)
