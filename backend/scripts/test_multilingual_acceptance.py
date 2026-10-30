from __future__ import annotations

import argparse
import json
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from decimal import Decimal
from typing import Any

from app.schemas.story_parser import (
    AmountRole,
    MoodType,
    SettlementStatus,
    StoryParseRequest,
    StoryParseResponse,
)
from app.services.story_parser_service import StoryParserService

STORIES = {
    1: {
        "zh": "我自己付了晚餐的80加元。饮料33加元已经包含在这80加元里。",
        "en": "I paid 80 CAD for dinner. The 33 CAD drink was included in that 80 CAD.",
        "fr": (
            "J'ai payé 80 CAD pour le dîner. "
            "La boisson à 33 CAD était comprise dans ces 80 CAD."
        ),
    },
    2: {
        "zh": "妈妈替我付了18加元买咖啡豆。我没说是否需要还她。",
        "en": (
            "My mother paid 18 CAD for my coffee beans. "
            "I have not said whether I owe her."
        ),
        "fr": (
            "Ma mère a payé 18 CAD pour mes grains de café. "
            "Je n'ai pas dit si je dois la rembourser."
        ),
    },
    3: {
        "zh": (
            "我很累但也很开心。朋友请我喝了8加元的奶茶，不用我还。"
            "我自己付12加元买了六盎司咖啡豆。"
        ),
        "en": (
            "I was tired but happy. My friend treated me to an 8 CAD milk tea; "
            "I owe nothing. I paid 12 CAD for six ounces of coffee beans."
        ),
        "fr": (
            "J'étais fatigué mais heureux. Mon ami m'a offert un thé aux perles "
            "à 8 CAD ; je ne lui dois rien. J'ai payé 12 CAD pour six onces de "
            "grains de café."
        ),
    },
    4: {
        "zh": "我本来想买180加元的鞋，但最后没有买。",
        "en": "I considered buying 180 CAD shoes but did not buy them.",
        "fr": (
            "J'ai envisagé d'acheter des chaussures à 180 CAD, "
            "mais je ne les ai pas achetées."
        ),
    },
}


def _source_quotes_are_exact(story: str, result: StoryParseResponse) -> bool:
    quotes = [event.source_text for event in result.spending_events]
    quotes.extend(
        mention.source_text
        for event in result.spending_events
        for mention in event.amount_mentions
    )
    quotes.extend(
        quantity.source_text
        for event in result.spending_events
        for quantity in event.quantities
    )
    return all(quote in story for quote in quotes)


def _financial_checks(case: int, result: StoryParseResponse) -> dict[str, bool]:
    checks: dict[str, bool] = {}
    if case == 1:
        checks.update(
            {
                "user_total_80": result.total_user_expense == Decimal(80),
                "included_33_not_counted": any(
                    mention.amount == Decimal(33)
                    and mention.role == AmountRole.INCLUDED_DETAIL
                    and not mention.counted_in_user_total
                    for event in result.spending_events
                    for mention in event.amount_mentions
                ),
            }
        )
    elif case == 2:
        checks.update(
            {
                "confirmed_user_total_0": result.total_user_expense == 0,
                "responsibility_unresolved": any(
                    event.needs_confirmation
                    or event.settlement_status == SettlementStatus.UNRESOLVED
                    for event in result.spending_events
                ),
                "confirmation_question_present": bool(result.confirmation_questions),
            }
        )
    elif case == 3:
        moods = {item.mood for item in result.moods}
        checks.update(
            {
                "user_total_12": result.total_user_expense == Decimal(12),
                "friend_paid_8": result.total_paid_by_others == Decimal(8),
                "six_ounces_is_quantity": any(
                    quantity.value == Decimal(6)
                    for event in result.spending_events
                    for quantity in event.quantities
                ),
                "both_emotions_preserved": {
                    MoodType.TIRED,
                    MoodType.HAPPY,
                }.issubset(moods),
            }
        )
    else:
        checks.update(
            {
                "user_total_0": result.total_user_expense == 0,
                "saved_decision_180": result.total_saved_decisions == Decimal(180),
            }
        )
    return checks


def run_case(case: int, language: str, story: str) -> dict[str, Any]:
    result = StoryParserService().parse(
        StoryParseRequest(
            text=story,
            default_currency="CAD",
            response_language=language,
        )
    )
    checks = _financial_checks(case, result)
    checks["source_quotes_exact"] = _source_quotes_are_exact(story, result)
    return {
        "case": case,
        "language": language,
        "passed": all(checks.values()),
        "checks": checks,
        "summary": result.summary,
        "questions": [item.question for item in result.confirmation_questions],
        "totals": {
            "user_expense": str(result.total_user_expense),
            "paid_by_others": str(result.total_paid_by_others),
            "saved_decisions": str(result.total_saved_decisions),
        },
    }


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser()
    parser.add_argument("--case", type=int, choices=STORIES)
    parser.add_argument("--language", choices=("zh", "en", "fr"))
    args = parser.parse_args()
    jobs = [
        (case, language, story)
        for case, translations in STORIES.items()
        for language, story in translations.items()
        if (args.case is None or case == args.case)
        and (args.language is None or language == args.language)
    ]
    results: list[dict[str, Any]] = []
    with ThreadPoolExecutor(max_workers=3) as executor:
        futures = {
            executor.submit(run_case, case, language, story): (case, language)
            for case, language, story in jobs
        }
        for future in as_completed(futures):
            case, language = futures[future]
            try:
                results.append(future.result())
            except Exception as exc:  # noqa: BLE001 - report every live API failure
                results.append(
                    {
                        "case": case,
                        "language": language,
                        "passed": False,
                        "error": f"{type(exc).__name__}: {exc}",
                    }
                )

    results.sort(key=lambda item: (item["case"], item["language"]))
    print(json.dumps(results, ensure_ascii=False, indent=2))
    if not all(item["passed"] for item in results):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
