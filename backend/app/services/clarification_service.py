from __future__ import annotations

import json
from datetime import UTC, datetime
from decimal import Decimal
from typing import Literal, Protocol
from uuid import UUID

from openai import OpenAI
from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from app.core.config import get_settings
from app.models.financial_draft import (
    FinancialDraft,
    FinancialDraftClarification,
    FinancialDraftEvent,
)
from app.prompts.clarification_prompt import CLARIFICATION_RESOLUTION_PROMPT
from app.schemas.financial_draft import (
    ClarificationAnswer,
    ClarificationAnswersRequest,
    ClarificationIssueType,
    ClarificationOperation,
    ClarificationOption,
    ClarificationRequirement,
    ClarificationResolution,
    ClarificationStatus,
    ClarificationWorkflowState,
    ClarifyingFinancialDraftResponse,
    DraftClarificationQuestion,
    DraftEventDisposition,
)
from app.schemas.story_parser import (
    AmountRole,
    PayerType,
    SettlementStatus,
    SpendingEvent,
    StoryParseResponse,
)
from app.services.financial_draft_service import (
    FinancialDraftConflictError,
    FinancialDraftNotFoundError,
    FinancialDraftService,
    FinancialDraftValidationError,
)

MAX_REQUIRED_CLARIFICATION_ROUNDS = 3


class ClarificationResolver(Protocol):
    def resolve(self, context: dict) -> ClarificationResolution: ...


class OpenAIClarificationResolver:
    def resolve(self, context: dict) -> ClarificationResolution:
        settings = get_settings()
        if not settings.openai_api_key:
            raise FinancialDraftValidationError("Free-text clarification is not configured.")
        response = OpenAI(api_key=settings.openai_api_key).responses.parse(
            model=settings.openai_model,
            instructions=CLARIFICATION_RESOLUTION_PROMPT,
            input=json.dumps(context, ensure_ascii=False),
            text_format=ClarificationResolution,
            max_output_tokens=settings.openai_max_output_tokens,
            reasoning={"effort": settings.openai_reasoning_effort},
            text={"verbosity": settings.openai_text_verbosity},
        )
        if response.output_parsed is None:
            raise FinancialDraftValidationError("Clarification could not be resolved safely.")
        return response.output_parsed


class ClarificationService:
    def __init__(self, session: Session, resolver: ClarificationResolver | None = None) -> None:
        self.session = session
        self.resolver = resolver or OpenAIClarificationResolver()

    def create_from_parse(
        self,
        journal: str,
        parsed: StoryParseResponse,
        response_language: Literal["zh", "en", "fr"] | None = None,
    ) -> ClarifyingFinancialDraftResponse:
        snapshot = parsed.model_dump(mode="json")
        parsed = self._normalize_third_party_settlements(
            journal, parsed, response_language=response_language
        )
        with self.session.begin():
            draft = FinancialDraft(
                original_journal=journal,
                original_snapshot=snapshot,
                working_metadata={
                    "summary": parsed.summary,
                    "moods": [item.model_dump(mode="json") for item in parsed.moods],
                    "life_events": [item.model_dump(mode="json") for item in parsed.life_events],
                    "confirmation_questions": [
                        item.model_dump(mode="json") for item in parsed.confirmation_questions
                    ],
                },
                events=[
                    FinancialDraftEvent(
                        position=index,
                        disposition=DraftEventDisposition.PENDING.value,
                        event_payload=FinancialDraftService._event_for_review(event).model_dump(
                            mode="json"
                        ),
                    )
                    for index, event in enumerate(parsed.spending_events)
                ],
            )
            self.session.add(draft)
            self.session.flush()
            self._add_initial_questions(draft, parsed, response_language=response_language)
            self._refresh_state(draft)
            self.session.flush()
            result = self._response(draft)
        return result

    @staticmethod
    def _normalize_third_party_settlements(
        _journal: str,
        parsed: StoryParseResponse,
        response_language: Literal["zh", "en", "fr"] | None = None,
    ) -> StoryParseResponse:
        """Conservatively require settlement evidence beyond an initial payer."""
        explicit_markers = (
            "gift",
            "treated me",
            "owe nothing",
            "don't owe",
            "do not owe",
            "no need to pay back",
            "paid her back",
            "paid him back",
            "reimbursed",
            "still owe",
            "need to pay back",
            "cadeau",
            "m'a invité",
            "m’a invité",
            "m'a offert",
            "m’a offert",
            "je ne lui dois rien",
            "je l'ai remboursé",
            "je l’ai remboursé",
            "je lui dois",
            "je dois rembourser",
            "不用还",
            "请我",
            "已经还",
            "还给",
            "还欠",
            "需要还",
        )
        events: list[SpendingEvent] = []
        changed = False
        for event in parsed.spending_events:
            if event.payer_type != PayerType.OTHER_PERSON:
                events.append(event)
                continue
            event_text = event.source_text.casefold()
            if any(marker in event_text for marker in explicit_markers):
                events.append(event)
                continue

            changed = True
            candidate_amount = ClarificationService._candidate_user_amount(event)
            mentions = [
                mention.model_copy(
                    update={
                        "role": (
                            AmountRole.EVENT_TOTAL
                            if mention.role == AmountRole.PAID_BY_OTHER
                            else mention.role
                        ),
                        "counted_in_user_total": False,
                    }
                )
                for mention in event.amount_mentions
            ]
            events.append(
                event.model_copy(
                    update={
                        "settlement_status": SettlementStatus.UNRESOLVED,
                        "user_net_amount": candidate_amount,
                        "amount_mentions": mentions,
                        "needs_confirmation": True,
                    }
                )
            )
        if not changed:
            return parsed
        payload = parsed.model_dump()
        payload["summary"] = {
            "zh": "有一笔由他人先付款的消费需要确认，才能确定你最终承担的金额。",
            "en": "A third-party-paid purchase needs clarification before the user's final expense can be determined.",
            "fr": "Un achat payé par une autre personne doit être clarifié avant de déterminer votre dépense finale.",
        }[response_language or "en"]
        payload["spending_events"] = events
        payload["total_paid_by_others"] = 0
        return StoryParseResponse.model_validate(payload)

    @staticmethod
    def _candidate_user_amount(event: SpendingEvent) -> Decimal:
        """Never infer a user's share from the largest price in a story."""
        net_amounts = {
            mention.amount
            for mention in event.amount_mentions
            if mention.role == AmountRole.USER_NET_EXPENSE
            and mention.currency == event.currency
            and mention.amount > 0
        }
        if net_amounts:
            if len(net_amounts) == 1:
                amount = next(iter(net_amounts))
                if event.user_net_amount in {Decimal(0), amount}:
                    return amount
            return Decimal(0)

        candidate_amounts = {
            mention.amount
            for mention in event.amount_mentions
            if mention.role
            not in {
                AmountRole.INCLUDED_DETAIL,
                AmountRole.COMMENTARY_PRICE,
                AmountRole.QUOTED_PRICE,
                AmountRole.PLANNED_EXPENSE,
                AmountRole.SAVED_DECISION,
                AmountRole.REFUND_OR_REIMBURSEMENT,
            }
            and mention.currency == event.currency
            and mention.amount > 0
        }
        if event.user_net_amount > 0:
            if candidate_amounts and candidate_amounts != {event.user_net_amount}:
                return Decimal(0)
            return event.user_net_amount
        if len(candidate_amounts) == 1:
            return next(iter(candidate_amounts))
        return Decimal(0)

    def get(self, draft_id: UUID) -> ClarifyingFinancialDraftResponse:
        return self._response(self._load(draft_id))

    def answer(
        self,
        draft_id: UUID,
        request: ClarificationAnswersRequest,
    ) -> ClarifyingFinancialDraftResponse:
        with self.session.begin():
            draft = self._load(draft_id, for_update=True)
            if draft.status != "draft":
                raise FinancialDraftConflictError("Confirmed or cancelled drafts are immutable.")
            if draft.version != request.expected_version:
                raise FinancialDraftConflictError("The draft version is stale.")
            if len({answer.question_id for answer in request.answers}) != len(request.answers):
                raise FinancialDraftValidationError(
                    "A question may be answered only once per request."
                )

            for answer in request.answers:
                question = self._open_question(draft, answer.question_id)
                resolution = self._resolution_for(draft, question, answer)
                self._apply_resolution(draft, question, resolution)
                question.status = ClarificationStatus.ANSWERED.value
                question.answer_payload = answer.model_dump(mode="json", exclude_none=True)
                question.resolution_method = "llm_proposal" if answer.free_text else "deterministic"
                question.answered_at = datetime.now(UTC)

            draft.version += 1
            draft.updated_at = datetime.now(UTC)
            self._refresh_state(draft)
            self.session.flush()
            result = self._response(draft)
        return result

    def _add_initial_questions(
        self,
        draft: FinancialDraft,
        parsed: StoryParseResponse,
        response_language: Literal["zh", "en", "fr"] | None = None,
    ) -> None:
        round_number = 1
        if round_number > MAX_REQUIRED_CLARIFICATION_ROUNDS:
            return
        semantic_keys = {item.semantic_key for item in draft.clarifications}
        unresolved_settlement_events = [
            event
            for event in draft.events
            if event.event_payload.get("payer_type") == PayerType.OTHER_PERSON.value
            and event.event_payload.get("settlement_status") == SettlementStatus.UNRESOLVED.value
        ]
        for index, source_question in enumerate(parsed.confirmation_questions):
            event = self._match_event(draft.events, source_question.related_source_text)
            matches_unresolved_settlement = bool(
                event
                and event.event_payload.get("payer_type") == PayerType.OTHER_PERSON.value
                and event.event_payload.get("settlement_status")
                == SettlementStatus.UNRESOLVED.value
            )
            inferred_issue_type = self._issue_type(source_question.question, source_question.reason)
            is_only_question_for_only_unresolved_settlement = (
                len(parsed.confirmation_questions) == 1 and len(unresolved_settlement_events) == 1
            )
            is_redundant_settlement_question = bool(
                unresolved_settlement_events
                and (
                    matches_unresolved_settlement
                    or inferred_issue_type == ClarificationIssueType.PAYER_RESPONSIBILITY
                    or is_only_question_for_only_unresolved_settlement
                )
            )
            issue_type = (
                ClarificationIssueType.PAYER_RESPONSIBILITY
                if is_redundant_settlement_question
                else inferred_issue_type
            )
            semantic_key = (
                f"superseded:{issue_type.value}:{index}"
                if is_redundant_settlement_question
                else f"initial:{issue_type.value}:{event.id if event else index}"
            )
            if semantic_key in semantic_keys:
                continue
            semantic_keys.add(semantic_key)
            options = self._options(
                issue_type, has_event=event is not None, language=response_language
            )
            draft.clarifications.append(
                FinancialDraftClarification(
                    sequence=index + 1,
                    round_number=round_number,
                    semantic_key=semantic_key,
                    requirement=ClarificationRequirement.REQUIRED.value,
                    issue_type=issue_type.value,
                    status=(
                        ClarificationStatus.SUPERSEDED.value
                        if is_redundant_settlement_question
                        else ClarificationStatus.OPEN.value
                    ),
                    question=source_question.question,
                    reason=source_question.reason,
                    related_event_id=event.id if event else None,
                    related_source_text=source_question.related_source_text,
                    options_payload=options,
                )
            )

        sequence = len(parsed.confirmation_questions) + 1
        for event in unresolved_settlement_events:
            semantic_key = f"settlement:{event.id}"
            if semantic_key in semantic_keys:
                continue
            semantic_keys.add(semantic_key)
            payer = event.event_payload.get("paid_by_name") or {
                "zh": "对方",
                "en": "the other person",
                "fr": "L'autre personne",
            }[response_language or "en"]
            payer_label = f"Your {payer}" if payer.casefold() != "the other person" else payer
            amount = event.event_payload["user_net_amount"]
            currency = event.event_payload["currency"]
            title = event.event_payload["title"].casefold()
            amount_is_known = Decimal(amount) > 0
            purchase_totals = {
                mention["amount"]
                for mention in event.event_payload.get("amount_mentions", [])
                if mention["role"] == AmountRole.EVENT_TOTAL.value
                and mention["currency"] == currency
            }
            purchase_total = next(iter(purchase_totals)) if len(purchase_totals) == 1 else None
            purchase_label = f"{purchase_total} {currency}" if purchase_total is not None else None
            payer_statement = (
                f"{payer_label.capitalize()} paid {purchase_label} for {title}. "
                if purchase_label is not None
                else f"{payer_label.capitalize()} paid for {title}. "
            )
            question = (
                payer_statement + "What happened afterward?"
                if amount_is_known
                and purchase_total is not None
                and Decimal(purchase_total) == Decimal(amount)
                else payer_statement
                + "What happened afterward? "
                + (
                    f"Is your share {amount} {currency}?"
                    if amount_is_known
                    else "Confirm your amount during review."
                )
            )
            reason = (
                f"This helps FinPilot determine whether the {amount} {currency} "
                "is actually your expense."
                if amount_is_known
                else "This helps FinPilot determine whether any of this cost is your expense."
            )
            if response_language == "zh":
                question = (
                    f"{payer} 为{title}支付了{purchase_label or '费用'}。之后怎样了？"
                    + (
                        f"请确认你承担的金额是否为 {amount} {currency}。"
                        if amount_is_known
                        and (purchase_total is None or Decimal(purchase_total) != Decimal(amount))
                        else ""
                    )
                )
                reason = "这能帮助 FinPilot 确认这笔费用是否由你承担。"
            elif response_language == "fr":
                question = (
                    f"{payer} a payé {purchase_label or 'les frais'} pour {title}. "
                    "Que s'est-il passé ensuite ?"
                    + (
                        f" Confirmez-vous que votre part est de {amount} {currency} ?"
                        if amount_is_known
                        and (purchase_total is None or Decimal(purchase_total) != Decimal(amount))
                        else ""
                    )
                )
                reason = "Cela aide FinPilot à déterminer si cette dépense est à votre charge."
            draft.clarifications.append(
                FinancialDraftClarification(
                    sequence=sequence,
                    round_number=round_number,
                    semantic_key=semantic_key,
                    requirement=ClarificationRequirement.REQUIRED.value,
                    issue_type=ClarificationIssueType.PAYER_RESPONSIBILITY.value,
                    status=ClarificationStatus.OPEN.value,
                    question=question,
                    reason=reason,
                    related_event_id=event.id,
                    related_source_text=event.event_payload["source_text"],
                    options_payload=self._options(
                        ClarificationIssueType.PAYER_RESPONSIBILITY,
                        has_event=True,
                        language=response_language,
                    ),
                )
            )
            sequence += 1

    @staticmethod
    def _match_event(
        events: list[FinancialDraftEvent],
        source_text: str,
    ) -> FinancialDraftEvent | None:
        return next(
            (
                item
                for item in events
                if source_text in item.event_payload.get("source_text", "")
                or item.event_payload.get("source_text", "") in source_text
            ),
            None,
        )

    @staticmethod
    def _issue_type(question: str, reason: str) -> ClarificationIssueType:
        text = f"{question} {reason}".casefold()
        if any(token in text for token in ("paid", "payer", "付款", "谁付", "支付", "payé", "payer", "rembourser", "dois")):
            return ClarificationIssueType.PAYER_RESPONSIBILITY
        if any(token in text for token in ("included", "separate", "包含", "另外", "inclus", "séparé")):
            return ClarificationIssueType.INCLUDED_OR_SEPARATE
        return ClarificationIssueType.OTHER

    @staticmethod
    def _options(
        issue_type: ClarificationIssueType,
        *,
        has_event: bool,
        language: Literal["zh", "en", "fr"] | None = None,
    ) -> list[dict]:
        labels = {
            "zh": {
                "keep_unresolved": "暂不确定，排除这笔费用",
                "paid_by_other": "对方请客，我不欠款",
                "repaid_by_user": "我已经还款",
                "repayment_due": "我仍需还款",
                "confirm_as_parsed": "草稿理解正确",
                "exclude": "排除这笔事件",
            },
            "fr": {
                "keep_unresolved": "Laisser en suspens et exclure cette dépense",
                "paid_by_other": "Cette personne m'a invité, je ne dois rien",
                "repaid_by_user": "Je l'ai déjà remboursée",
                "repayment_due": "Je dois encore la rembourser",
                "confirm_as_parsed": "L'interprétation du brouillon est correcte",
                "exclude": "Exclure cet événement",
            },
        }.get(language, {})
        if not has_event:
            return [
                {
                    "option_key": "keep_unresolved",
                    "label": labels.get("keep_unresolved", "Keep this unresolved and exclude it"),
                    "operation": "keep_unresolved",
                }
            ]
        if issue_type == ClarificationIssueType.PAYER_RESPONSIBILITY:
            return [
                {
                    "option_key": "paid_by_other",
                    "label": labels.get("paid_by_other", "They paid for me — I owe nothing"),
                    "operation": "paid_by_other",
                },
                {
                    "option_key": "repaid_by_user",
                    "label": labels.get("repaid_by_user", "I already paid them back"),
                    "operation": "repaid_by_user",
                },
                {
                    "option_key": "repayment_due",
                    "label": labels.get("repayment_due", "I still owe them"),
                    "operation": "repayment_due",
                },
            ]
        return [
            {
                "option_key": "confirm_as_parsed",
                "label": labels.get("confirm_as_parsed", "The draft interpretation is correct"),
                "operation": "confirm_as_parsed",
            },
            {"option_key": "exclude", "label": labels.get("exclude", "Exclude this event"), "operation": "exclude_event"},
        ]

    def _resolution_for(
        self,
        draft: FinancialDraft,
        question: FinancialDraftClarification,
        answer: ClarificationAnswer,
    ) -> ClarificationResolution:
        if answer.option_key is not None:
            option = next(
                (
                    item
                    for item in question.options_payload
                    if item["option_key"] == answer.option_key
                ),
                None,
            )
            if option is None:
                raise FinancialDraftValidationError(
                    "The selected option is not valid for this open question."
                )
            return ClarificationResolution(
                question_id=question.id,
                event_id=question.related_event_id,
                operation=ClarificationOperation(option["operation"]),
                explanation="Applied the persisted clarification option.",
            )

        event = self._event(draft, question.related_event_id)
        proposal = self.resolver.resolve(
            {
                "journal": draft.original_journal,
                "original_parse": draft.original_snapshot,
                "working_event": event.event_payload if event else None,
                "question": question.question,
                "options": question.options_payload,
                "history": [
                    item.answer_payload for item in draft.clarifications if item.answer_payload
                ],
                "answer": answer.free_text,
                "question_id": str(question.id),
            }
        )
        if proposal.question_id != question.id:
            raise FinancialDraftValidationError(
                "Clarification proposal targets the wrong question."
            )
        if proposal.event_id not in {None, question.related_event_id}:
            raise FinancialDraftValidationError("Clarification proposal targets the wrong event.")
        return proposal

    def _apply_resolution(
        self,
        draft: FinancialDraft,
        question: FinancialDraftClarification,
        resolution: ClarificationResolution,
    ) -> None:
        event_row = self._event(draft, question.related_event_id)
        if event_row is None:
            if resolution.operation != ClarificationOperation.KEEP_UNRESOLVED:
                raise FinancialDraftValidationError("Clarification has no safely matched event.")
            return
        payload = dict(event_row.event_payload)
        if resolution.operation == ClarificationOperation.EXCLUDE_EVENT:
            event_row.disposition = DraftEventDisposition.EXCLUDE.value
            return
        if resolution.operation == ClarificationOperation.KEEP_UNRESOLVED:
            event_row.disposition = DraftEventDisposition.EXCLUDE.value
            return
        if resolution.operation == ClarificationOperation.PAID_BY_OTHER:
            payload["payer_type"] = PayerType.OTHER_PERSON.value
            payload["settlement_status"] = SettlementStatus.COVERED_BY_OTHER.value
            payload["user_net_amount"] = "0"
            payload["needs_confirmation"] = False
            for mention in payload.get("amount_mentions", []):
                mention["counted_in_user_total"] = False
                if mention.get("role") == AmountRole.USER_NET_EXPENSE.value:
                    mention["role"] = AmountRole.PAID_BY_OTHER.value
            event_row.disposition = DraftEventDisposition.EXCLUDE.value
        elif resolution.operation == ClarificationOperation.REPAID_BY_USER:
            payload["payer_type"] = PayerType.OTHER_PERSON.value
            payload["settlement_status"] = SettlementStatus.REPAID_BY_USER.value
            payload["event_date"] = None
            payload["needs_confirmation"] = False
            for mention in payload.get("amount_mentions", []):
                mention["counted_in_user_total"] = False
            payload["amount_mentions"].append(
                {
                    "amount": payload["user_net_amount"],
                    "currency": payload["currency"],
                    "role": AmountRole.USER_NET_EXPENSE.value,
                    "counted_in_user_total": True,
                    "source_text": payload["source_text"],
                    "confidence": 1,
                    "explanation": "Repayment confirmed by the user.",
                }
            )
            event_row.disposition = DraftEventDisposition.PENDING.value
        elif resolution.operation == ClarificationOperation.REPAYMENT_DUE:
            payload["payer_type"] = PayerType.OTHER_PERSON.value
            payload["settlement_status"] = SettlementStatus.REPAYMENT_DUE.value
            payload["needs_confirmation"] = False
            for mention in payload.get("amount_mentions", []):
                mention["counted_in_user_total"] = False
            event_row.disposition = DraftEventDisposition.EXCLUDE.value
        elif resolution.operation == ClarificationOperation.USER_PAID:
            payload["payer_type"] = PayerType.USER.value
            payload["needs_confirmation"] = False
        elif resolution.operation == ClarificationOperation.CONFIRM_AS_PARSED:
            payload["needs_confirmation"] = False
        event_row.event_payload = SpendingEvent.model_validate(payload).model_dump(mode="json")

    @staticmethod
    def _event(
        draft: FinancialDraft,
        event_id: UUID | None,
    ) -> FinancialDraftEvent | None:
        return next((item for item in draft.events if item.id == event_id), None)

    @staticmethod
    def _open_question(
        draft: FinancialDraft,
        question_id: UUID,
    ) -> FinancialDraftClarification:
        question = next((item for item in draft.clarifications if item.id == question_id), None)
        if question is None:
            raise FinancialDraftNotFoundError("Clarification question was not found.")
        if question.status != ClarificationStatus.OPEN.value:
            raise FinancialDraftConflictError(
                "Clarification question is stale or already answered."
            )
        return question

    @staticmethod
    def _refresh_state(draft: FinancialDraft) -> None:
        has_required = any(
            item.status == ClarificationStatus.OPEN.value
            and item.requirement == ClarificationRequirement.REQUIRED.value
            for item in draft.clarifications
        )
        draft.clarification_state = (
            ClarificationWorkflowState.AWAITING_REQUIRED.value
            if has_required
            else ClarificationWorkflowState.READY_FOR_REVIEW.value
        )

    def _load(self, draft_id: UUID, *, for_update: bool = False) -> FinancialDraft:
        statement = (
            select(FinancialDraft)
            .where(FinancialDraft.id == draft_id)
            .options(
                selectinload(FinancialDraft.events),
                selectinload(FinancialDraft.clarifications),
            )
        )
        if for_update:
            statement = statement.with_for_update()
        draft = self.session.execute(statement).scalar_one_or_none()
        if draft is None:
            raise FinancialDraftNotFoundError("Financial draft was not found.")
        return draft

    def _response(self, draft: FinancialDraft) -> ClarifyingFinancialDraftResponse:
        draft_response = FinancialDraftService(self.session)._to_response(draft)
        return ClarifyingFinancialDraftResponse(
            draft=draft_response,
            clarification_state=ClarificationWorkflowState(draft.clarification_state),
            clarifications=[
                DraftClarificationQuestion(
                    id=item.id,
                    sequence=item.sequence,
                    round_number=item.round_number,
                    requirement=ClarificationRequirement(item.requirement),
                    issue_type=ClarificationIssueType(item.issue_type),
                    status=ClarificationStatus(item.status),
                    question=item.question,
                    reason=item.reason,
                    related_event_id=item.related_event_id,
                    related_source_text=item.related_source_text,
                    options=[
                        ClarificationOption(option_key=option["option_key"], label=option["label"])
                        for option in item.options_payload
                    ],
                    answer=item.answer_payload,
                )
                for item in draft.clarifications
            ],
        )
