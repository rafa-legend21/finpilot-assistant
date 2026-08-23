from functools import lru_cache

from pydantic import field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

DEVELOPMENT_CORS_ORIGIN_REGEX = (
    r"^https?://(?:localhost|127\.0\.0\.1)(?::[0-9]{1,5})?$"
)


class Settings(BaseSettings):
    app_env: str = "development"
    app_name: str = "FinPilot Assistant API"
    api_v1_prefix: str = "/api/v1"
    database_url: str = "sqlite+pysqlite:///./finpilot.db"
    cors_origins: list[str] = ["http://localhost:3000", "http://localhost:8080"]
    secret_key: str = "development-only-change-me"

    openai_api_key: str | None = None
    openai_model: str = "gpt-5"

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    @field_validator("cors_origins", mode="before")
    @classmethod
    def parse_origins(cls, value: object) -> object:
        if isinstance(value, str):
            return [item.strip() for item in value.split(",") if item.strip()]
        return value

    @property
    def cors_origin_regex(self) -> str | None:
        if self.app_env.casefold() == "development":
            return DEVELOPMENT_CORS_ORIGIN_REGEX
        return None


@lru_cache
def get_settings() -> Settings:
    return Settings()
