import 'package:flutter/material.dart';

import '../models/financial_review_models.dart';

class DraftEventCard extends StatelessWidget {
  const DraftEventCard(
      {required this.draftEvent, required this.onEdit, super.key});

  final FinancialDraftEvent draftEvent;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final event = draftEvent.event;
    final excluded = draftEvent.disposition == DraftEventDisposition.exclude;
    final missingIncludedDate =
        draftEvent.disposition == DraftEventDisposition.include &&
            (event.eventDate == null || event.eventDate!.trim().isEmpty);
    final unresolved =
        draftEvent.disposition == DraftEventDisposition.pending ||
            event.needsConfirmation ||
            missingIncludedDate;
    final paidByOther =
        event.payerType != 'user' && event.payerType != 'shared';
    final savedDate = event.eventDate?.trim();
    final color = excluded
        ? Colors.grey
        : unresolved
            ? Colors.amber.shade800
            : draftEvent.disposition == DraftEventDisposition.include
                ? Colors.green.shade700
                : Theme.of(context).colorScheme.primary;
    final label = excluded
        ? "Won't be recorded"
        : missingIncludedDate
            ? 'Date required'
            : unresolved
                ? event.needsConfirmation
                    ? 'Needs confirmation'
                    : 'Review needed'
                : draftEvent.disposition == DraftEventDisposition.include
                    ? 'Will be recorded'
                    : paidByOther
                        ? 'Paid by others'
                        : 'You paid';
    final icon = excluded
        ? Icons.remove_circle_outline
        : unresolved
            ? Icons.warning_amber_rounded
            : paidByOther
                ? Icons.person_outline
                : Icons.check_circle_outline;

    return Card(
      color: excluded ? Colors.grey.shade100 : null,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: color, width: unresolved ? 2 : 1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(event.title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 16)),
                  ),
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Event amount',
                          key: const Key('eventAmountLabel'),
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        Text(
                          '${event.currency} ${event.userNetAmount}',
                          key: const Key('eventAmountValue'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  Chip(
                    avatar: Icon(icon, size: 17, color: color),
                    label: Text(label),
                    visualDensity: VisualDensity.compact,
                  ),
                  Chip(
                      label: Text(event.category),
                      visualDensity: VisualDensity.compact),
                  Chip(
                    label: Text(_merchantLabel(event)),
                    visualDensity: VisualDensity.compact,
                  ),
                  if (savedDate != null && savedDate.isNotEmpty)
                    Chip(
                      avatar:
                          const Icon(Icons.calendar_today_outlined, size: 16),
                      label: Text('Date: $savedDate'),
                      visualDensity: VisualDensity.compact,
                    ),
                  Chip(
                    label: Text(_payerLabel(event)),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                event.sourceText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.grey.shade700),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _merchantLabel(SpendingEvent event) {
    final merchant = event.merchant;
    return merchant == null || merchant.trim().isEmpty
        ? 'Unknown merchant'
        : merchant;
  }

  String _payerLabel(SpendingEvent event) => switch (event.payerType) {
        'user' => 'You paid',
        'shared' => 'Shared',
        'other_person' => event.paidByName == null
            ? 'Paid by someone else'
            : 'Paid by ${event.paidByName}',
        'employer' => 'Employer paid',
        _ => 'Payer unknown',
      };
}
