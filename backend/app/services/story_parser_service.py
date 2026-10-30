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
            raise StoryParserConfigurationError("OPENAI_API_KEY is not configured.")

        self.client = client or OpenAI(
            api_key=self.settings.openai_api_key,
            timeout=60.0,
            max_retries=0,
        )

    def parse(self, request: StoryParseRequest) -> StoryParseResponse:
        try:
            response = self.client.responses.parse(
                model=self.settings.openai_model,
                instructions=STORY_PARSER_SYSTEM_PROMPT,
                input=self._build_user_input(request),
                text_format=StoryParseResponse,
                max_output_tokens=self.settings.openai_max_output_tokens,
                reasoning={"effort": self.settings.openai_reasoning_effort},
                text={"verbosity": self.settings.openai_text_verbosity},
            )
        except Exception as exc:
            raise StoryParserOutputError(f"OpenAI Story Parser request failed: {exc}") from exc

        if response.status == "incomplete":
            reason = getattr(response.incomplete_details, "reason", "unknown")
            raise StoryParserOutputError(f"The AI Story Parser response was incomplete: {reason}.")

        parsed_result = response.output_parsed

        if parsed_result is None:
            raise StoryParserOutputError("The AI returned no parsed Story Parser result.")

        return parsed_result

    @staticmethod
    def _build_user_input(request: StoryParseRequest) -> str:
        reference_date = (
            request.reference_date.isoformat() if request.reference_date else "not supplied"
        )

        return f"""
Default currency: {request.default_currency.value}
Reference date: {reference_date}
Response language: {request.response_language or "same as journal entry"}

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
- Apply the same financial rules regardless of the journal language.
- Write human-readable summary, event titles/descriptions, mood and life-event
  descriptions, and confirmation questions/reasons in the response language.
- Preserve source_text exactly as it appeared in the journal. Keep structured
  enum values, currency codes, and numeric amounts unchanged.
""".strip()
