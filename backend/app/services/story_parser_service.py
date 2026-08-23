from __future__ import annotations

from openai import OpenAI

from app.core.config import get_settings
from app.prompts.story_parser_prompt import STORY_PARSER_SYSTEM_PROMPT
from app.schemas.story_parser import (
    StoryParseRequest,
    StoryParseResponse,
)


class StoryParserConfigurationError(RuntimeError):
    """Raised when the Story Parser is not correctly configured."""


class StoryParserOutputError(RuntimeError):
    """Raised when the model returns unusable structured output."""


class StoryParserService:
    def __init__(self, client: OpenAI | None = None) -> None:
        self.settings = get_settings()

        if not self.settings.openai_api_key:
            raise StoryParserConfigurationError(
                "OPENAI_API_KEY is not configured."
            )

        self.client = client or OpenAI(
            api_key=self.settings.openai_api_key,
        )

    def parse(self, request: StoryParseRequest) -> StoryParseResponse:
        try:
            response = self.client.responses.parse(
                model=self.settings.openai_model,
                instructions=STORY_PARSER_SYSTEM_PROMPT,
                input=self._build_user_input(request),
                text_format=StoryParseResponse,
            )
        except Exception as exc:
            raise StoryParserOutputError(
                f"OpenAI Story Parser request failed: {exc}"
            ) from exc

        parsed_result = response.output_parsed

        if parsed_result is None:
            raise StoryParserOutputError(
                "The AI returned no parsed Story Parser result."
            )

        return parsed_result

    @staticmethod
    def _build_user_input(request: StoryParseRequest) -> str:
        reference_date = (
            request.reference_date.isoformat()
            if request.reference_date
            else "not supplied"
        )

        return f"""
Default currency: {request.default_currency.value}
Reference date: {reference_date}

Journal entry:
{request.text}

Return a conservative draft.

Important:
- Group related amounts into complete real-world events.
- Do not double count included details.
- Do not treat quantities or measurements as money.
- Only include expenses ultimately borne by the user in total_user_expense.
- If an ambiguity materially changes the financial result, add a
  confirmation question.
""".strip()
