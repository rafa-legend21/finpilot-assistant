from __future__ import annotations

from datetime import UTC, datetime
from decimal import Decimal
from uuid import UUID

from pydantic import ValidationError
from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from app.models.financial_draft import FinancialDraft, FinancialDraftEvent
from app.models.transaction import Transaction
from app.schemas.financial_draft import (
    ClarificationIssueType,
    DraftEventDisposition,
    DraftStatus,
    FinancialDraftConfirmationResponse,
    FinancialDraftCreateRequest,
    FinancialDraftEventResponse,
    FinancialDraftEventUpdate,
    FinancialDraftResponse,
)
from app.schemas.story_parser import PayerType, SettlementStatus, SpendingEvent, TransactionType


class FinancialDraftNotFoundError(LookupError):
    pass


class FinancialDraftConflictError(RuntimeError):
    pass


class FinancialDraftValidationError(ValueError):
    pass


class FinancialDraftService:
    def __init__(self, session: Session) -> None:
        self.session = session

    def create(self, request: FinancialDraftCreateRequest) -> FinancialDraftResponse:
        submitted = request.story_parse_response
        snapshot = submitted.model_dump(mode="json")
        metadata = {
            "summary": submitted.summary,
            "moods": [item.model_dump(mode="json") for item in submitted.moods],
            "life_events": [item.model_dump(mode="json") for item in submitted.life_events],
            "confirmation_questions": [
                item.model_dump(mode="json") for item in submitted.confirmation_questions
            ],
        }

        with self.session.begin():
            draft = FinancialDraft(
                original_snapshot=snapshot,
                working_metadata=metadata,
                events=[
                    FinancialDraftEvent(
                        position=position,
                        disposition=DraftEventDisposition.PENDING.value,
                        event_payload=self._event_for_review(event).model_dump(mode="json"),
                    )
                    for position, event in enumerate(submitted.spending_events)
                ],
            )
            self.session.add(draft)
            self.session.flush()
            result = self._to_response(draft)

        return result

    def get(self, draft_id: UUID) -> FinancialDraftResponse:
        return self._to_response(self._load(draft_id))

    def update_event(
        self,
        draft_id: UUID,
        event_id: UUID,
        request: FinancialDraftEventUpdate,
    ) -> FinancialDraftResponse:
        with self.session.begin():
            draft = self._load(draft_id, for_update=True)
            self._require_editable_version(draft, request.expected_version)
            draft_event = next((item for item in draft.events if item.id == event_id), None)
            if draft_event is None:
                raise FinancialDraftNotFoundError("Draft event was not found.")
            if any(
                clarification.related_event_id == event_id
                and clarification.status == "open"
                and clarification.requirement == "required"
                for clarification in draft.clarifications
            ):
                raise FinancialDraftConflictError(
                    "Answer the required clarification before editing this event."
                )

            persisted_event = self._validated_event(draft_event)
            settlement_was_resolved = any(
                clarification.related_event_id == event_id
                and clarification.status == "answered"
                and clarification.issue_type == ClarificationIssueType.PAYER_RESPONSIBILITY.value
                for clarification in draft.clarifications
            )
            if settlement_was_resolved and (
                request.event.payer_type != persisted_event.payer_type
                or request.event.paid_by_name != persisted_event.paid_by_name
                or request.event.settlement_status != persisted_event.settlement_status
            ):
                raise FinancialDraftConflictError(
                    "Resolved third-party settlement details cannot be changed during event review."
                )

            payload = persisted_event.model_dump(mode="json")
            submitted = request.event.model_dump(mode="json")
            editable_fields = {
                "category",
                "event_date",
                "merchant",
                "user_net_amount",
                "amount_mentions",
            }
            if not settlement_was_resolved:
                editable_fields.update({"payer_type", "paid_by_name", "settlement_status"})
            payload.update({field: submitted[field] for field in editable_fields})
            try:
                merged_event = SpendingEvent.model_validate(payload)
            except ValidationError as exc:
                raise FinancialDraftValidationError("The reviewed draft event is invalid.") from exc

            self._validate_review_disposition(merged_event, request.disposition)
            draft_event.event_payload = merged_event.model_dump(mode="json")
            draft_event.disposition = request.disposition.value
            draft.version += 1
            draft.updated_at = datetime.now(UTC)
            self.session.flush()
            result = self._to_response(draft)

        return result

    def cancel(self, draft_id: UUID, expected_version: int) -> FinancialDraftResponse:
        with self.session.begin():
            draft = self._load(draft_id, for_update=True)
            self._require_editable_version(draft, expected_version)
            draft.status = DraftStatus.CANCELLED.value
            draft.version += 1
            draft.cancelled_at = datetime.now(UTC)
            draft.updated_at = draft.cancelled_at
            self.session.flush()
            result = self._to_response(draft)

        return result

    def confirm(
        self,
        draft_id: UUID,
        expected_version: int,
    ) -> FinancialDraftConfirmationResponse:
        with self.session.begin():
            draft = self._load(draft_id, for_update=True)
            self._require_editable_version(draft, expected_version)
            if draft.clarification_state != "ready_for_review":
                raise FinancialDraftConflictError(
                    "Required clarifications must be resolved before confirmation."
                )
            transaction_ids: list[int] = []

            for draft_event in draft.events:
                disposition = DraftEventDisposition(draft_event.disposition)
                if disposition == DraftEventDisposition.PENDING:
                    raise FinancialDraftConflictError(
                        "All draft events must be included or excluded before confirmation."
                    )
                if disposition == DraftEventDisposition.EXCLUDE:
                    continue

                event = self._validated_event(draft_event)
                self._validate_included_event(event)
                transaction = Transaction(
                    merchant=event.merchant,
                    amount=event.user_net_amount,
                    currency=event.currency.value,
                    category=event.category.value,
                    transaction_date=event.event_date,
                    note=event.title,
                    source_draft_id=draft.id,
                    source_event_id=draft_event.id,
                )
                self.session.add(transaction)
                self.session.flush()
                transaction_ids.append(transaction.id)

            draft.status = DraftStatus.CONFIRMED.value
            draft.version += 1
            draft.confirmed_at = datetime.now(UTC)
            draft.updated_at = draft.confirmed_at
            self.session.flush()
            result = FinancialDraftConfirmationResponse(
                draft=self._to_response(draft),
                transaction_ids=transaction_ids,
            )

        return result

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

    @staticmethod
    def _require_editable_version(draft: FinancialDraft, expected_version: int) -> None:
        if draft.status != DraftStatus.DRAFT.value:
            raise FinancialDraftConflictError("Confirmed or cancelled drafts are immutable.")
        if draft.version != expected_version:
            raise FinancialDraftConflictError("The draft version is stale.")

    @staticmethod
    def _event_for_review(event: SpendingEvent) -> SpendingEvent:
        if (
            event.payer_type == PayerType.OTHER_PERSON
            and event.settlement_status == SettlementStatus.REPAID_BY_USER
        ):
            # The parsed date may be the purchase date, not the cash-outflow date.
            return event.model_copy(update={"event_date": None})
        return event

    @staticmethod
    def _validated_event(draft_event: FinancialDraftEvent) -> SpendingEvent:
        try:
            return SpendingEvent.model_validate(draft_event.event_payload)
        except ValidationError as exc:
            raise FinancialDraftValidationError(
                f"Stored draft event {draft_event.id} is invalid."
            ) from exc

    @staticmethod
    def _validate_review_disposition(
        event: SpendingEvent,
        disposition: DraftEventDisposition,
    ) -> None:
        if (
            event.settlement_status
            in {
                SettlementStatus.COVERED_BY_OTHER,
                SettlementStatus.REPAYMENT_DUE,
            }
            and disposition != DraftEventDisposition.EXCLUDE
        ):
            raise FinancialDraftConflictError(
                "Third-party expenses not yet realized by the user must be excluded."
            )
        if (
            disposition == DraftEventDisposition.INCLUDE
            and event.payer_type not in {PayerType.USER, PayerType.SHARED}
            and event.settlement_status != SettlementStatus.REPAID_BY_USER
        ):
            raise FinancialDraftConflictError(
                "Only user, shared, or completed repayment expenses may be included."
            )
        if disposition == DraftEventDisposition.INCLUDE and event.event_date is None:
            raise FinancialDraftConflictError("Included events require an exact transaction date.")
        if disposition == DraftEventDisposition.INCLUDE and event.user_net_amount <= 0:
            raise FinancialDraftConflictError("Included expenses must have a positive amount.")

    @staticmethod
    def _validate_included_event(event: SpendingEvent) -> None:
        if event.needs_confirmation:
            raise FinancialDraftConflictError(
                "Included events requiring confirmation must be resolved first."
            )
        if event.transaction_type != TransactionType.EXPENSE:
            raise FinancialDraftConflictError(
                "Only expense events may be included in this ledger version."
            )
        if (
            event.payer_type not in {PayerType.USER, PayerType.SHARED}
            and event.settlement_status != SettlementStatus.REPAID_BY_USER
        ):
            raise FinancialDraftConflictError(
                "Only user or shared expenses may be included in this ledger version."
            )
        if event.event_date is None:
            raise FinancialDraftConflictError("Included events require an exact transaction date.")
        if event.user_net_amount <= 0:
            raise FinancialDraftConflictError("Included expenses must have a positive amount.")

    def _to_response(self, draft: FinancialDraft) -> FinancialDraftResponse:
        events: list[FinancialDraftEventResponse] = []
        totals: dict = {}
        for draft_event in draft.events:
            event = self._validated_event(draft_event)
            disposition = DraftEventDisposition(draft_event.disposition)
            events.append(
                FinancialDraftEventResponse(
                    id=draft_event.id,
                    position=draft_event.position,
                    disposition=disposition,
                    event=event,
                )
            )
            if (
                disposition == DraftEventDisposition.INCLUDE
                and not event.needs_confirmation
                and event.event_date is not None
                and event.transaction_type == TransactionType.EXPENSE
                and (
                    event.payer_type in {PayerType.USER, PayerType.SHARED}
                    or event.settlement_status == SettlementStatus.REPAID_BY_USER
                )
            ):
                totals[event.currency] = (
                    totals.get(event.currency, Decimal(0)) + event.user_net_amount
                )

        metadata = draft.working_metadata
        return FinancialDraftResponse(
            id=draft.id,
            status=DraftStatus(draft.status),
            version=draft.version,
            original_snapshot=draft.original_snapshot,
            summary=metadata["summary"],
            moods=metadata.get("moods", []),
            life_events=metadata.get("life_events", []),
            confirmation_questions=metadata.get("confirmation_questions", []),
            events=events,
            totals_by_currency=totals,
            created_at=draft.created_at,
            updated_at=draft.updated_at,
            confirmed_at=draft.confirmed_at,
            cancelled_at=draft.cancelled_at,
        )
