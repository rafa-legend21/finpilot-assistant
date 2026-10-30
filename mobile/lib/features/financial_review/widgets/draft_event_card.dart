import 'package:flutter/material.dart';

import '../category_labels.dart';
import '../models/financial_review_models.dart';

class DraftEventCard extends StatelessWidget {
  const DraftEventCard(
      {required this.draftEvent,
      required this.onEdit,
      this.responseLanguage = 'en',
      super.key});

  final FinancialDraftEvent draftEvent;
  final VoidCallback onEdit;
  final String responseLanguage;

  String _t(String zh, String en, String fr) => switch (responseLanguage) {
        'zh' => zh,
        'fr' => fr,
        _ => en,
      };

  @override
  Widget build(BuildContext context) {
    final event = draftEvent.event;
    final avoidedPurchase = event.isAvoidedPurchase;
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
        ? _t('不会记录', "Won't be recorded", 'Ne sera pas enregistré')
        : missingIncludedDate
            ? _t('需要日期', 'Date required', 'Date requise')
            : unresolved
                ? event.needsConfirmation
                    ? _t('需要确认', 'Needs confirmation', 'Confirmation requise')
                    : _t('需要核对', 'Review needed', 'Vérification requise')
                : draftEvent.disposition == DraftEventDisposition.include
                    ? _t('将会记录', 'Will be recorded', 'Sera enregistré')
                    : paidByOther
                        ? _t('他人付款', 'Paid by others', 'Payé par autrui')
                        : _t('你已付款', 'You paid', 'Vous avez payé');
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
                          _t('事件金额', 'Event amount', 'Montant de l’événement'),
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
                      label:
                          Text(categoryLabel(event.category, responseLanguage)),
                      visualDensity: VisualDensity.compact),
                  Chip(
                    label: Text(_merchantLabel(event)),
                    visualDensity: VisualDensity.compact,
                  ),
                  if (savedDate != null && savedDate.isNotEmpty)
                    Chip(
                      avatar:
                          const Icon(Icons.calendar_today_outlined, size: 16),
                      label: Text('${_t('日期', 'Date', 'Date')}: $savedDate'),
                      visualDensity: VisualDensity.compact,
                    ),
                  Chip(
                    label: Text(avoidedPurchase
                        ? _t('未购买', 'Not purchased', 'Achat évité')
                        : _payerLabel(event)),
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
        ? _t('商家未知', 'Unknown merchant', 'Commerçant inconnu')
        : merchant;
  }

  String _payerLabel(SpendingEvent event) => switch (event.payerType) {
        'user' => _t('你已付款', 'You paid', 'Vous avez payé'),
        'shared' => _t('共同承担', 'Shared', 'Partagé'),
        'other_person' => event.paidByName == null
            ? _t('他人付款', 'Paid by someone else', 'Payé par une autre personne')
            : _t('由 ${event.paidByName} 付款', 'Paid by ${event.paidByName}',
                'Payé par ${event.paidByName}'),
        'employer' => _t('雇主付款', 'Employer paid', 'Payé par l’employeur'),
        _ => _t('付款人未知', 'Payer unknown', 'Payeur inconnu'),
      };
}
