import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/finpilot_theme.dart';
import 'category_labels.dart';
import 'models/financial_review_models.dart';

class QuickReviewPage extends StatefulWidget {
  const QuickReviewPage({
    required this.api,
    required this.initialDraft,
    required this.onDraftUpdated,
    this.responseLanguage = 'en',
    super.key,
  });

  final FinPilotApi api;
  final FinancialDraft initialDraft;
  final ValueChanged<FinancialDraft> onDraftUpdated;
  final String responseLanguage;

  @override
  State<QuickReviewPage> createState() => _QuickReviewPageState();
}

class _QuickReviewPageState extends State<QuickReviewPage> {
  late FinancialDraft _draft;
  late final int _totalToReview;
  bool _saving = false;
  String? _error;

  String _t(String zh, String en, String fr) =>
      switch (widget.responseLanguage) {
        'zh' => zh,
        'fr' => fr,
        _ => en,
      };

  @override
  void initState() {
    super.initState();
    _draft = widget.initialDraft;
    _totalToReview = _pending.length;
  }

  List<FinancialDraftEvent> get _pending => _draft.events
      .where((event) => event.disposition == DraftEventDisposition.pending)
      .toList()
    ..sort((a, b) => a.position.compareTo(b.position));

  FinancialDraftEvent? get _current => _pending.firstOrNull;

  bool _canRecord(SpendingEvent event) {
    final date = event.eventDate?.trim();
    final userBearsCost = event.payerType == 'user' ||
        event.payerType == 'shared' ||
        event.settlementStatus == 'repaid_by_user';
    return !event.isAvoidedPurchase &&
        event.transactionType == 'expense' &&
        !event.needsConfirmation &&
        userBearsCost &&
        (num.tryParse(event.userNetAmount) ?? 0) > 0 &&
        date != null &&
        date.isNotEmpty;
  }

  String? _recordingBlocker(SpendingEvent event) {
    if (event.isAvoidedPurchase) return null;
    if (event.needsConfirmation) {
      return _t(
        '这笔事件还有未解决的信息，暂时不能记录。',
        'This event still has unresolved information and cannot be recorded yet.',
        'Cet événement contient encore des informations non résolues et ne peut pas encore être enregistré.',
      );
    }
    if (event.transactionType != 'expense') {
      return _t(
        '当前账本只能记录支出，这项内容暂时不能记录。',
        'This ledger currently records expenses only, so this item cannot be recorded.',
        'Ce registre enregistre actuellement uniquement les dépenses; cet élément ne peut donc pas être enregistré.',
      );
    }
    if (event.payerType != 'user' &&
        event.payerType != 'shared' &&
        event.settlementStatus != 'repaid_by_user') {
      return _t(
        '付款责任不明确或由他人承担，不能计入你的支出。',
        'Payment responsibility is unclear or belongs to someone else, so it cannot count as your expense.',
        'La responsabilité du paiement est incertaine ou revient à une autre personne; cette dépense ne peut donc pas être comptée comme la vôtre.',
      );
    }
    if ((num.tryParse(event.userNetAmount) ?? 0) <= 0) {
      return _t(
        '需要先核对你实际承担的金额。',
        'Review the amount you actually paid before recording.',
        'Vérifiez le montant que vous avez réellement payé avant de l’enregistrer.',
      );
    }
    if (event.eventDate == null || event.eventDate!.trim().isEmpty) {
      return _t(
        '记录支出前需要填写准确日期。',
        'Add an exact date before recording this expense.',
        'Ajoutez une date exacte avant d’enregistrer cette dépense.',
      );
    }
    return null;
  }

  Future<void> _decide(DraftEventDisposition disposition) async {
    final current = _current;
    if (current == null || _saving) return;
    if (disposition == DraftEventDisposition.include &&
        !_canRecord(current.event)) {
      return;
    }
    await _saveEvent(current.event, disposition);
  }

  Future<void> _saveEvent(
    SpendingEvent event,
    DraftEventDisposition disposition,
  ) async {
    final current = _current;
    if (current == null || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await widget.api.updateDraftEvent(
        draftId: _draft.id,
        eventId: current.id,
        expectedVersion: _draft.version,
        disposition: disposition,
        event: event,
      );
      if (!mounted) return;
      _acceptUpdate(updated);
    } on ApiException catch (error) {
      if (error.statusCode == 409) {
        try {
          final latest = await widget.api.getDraft(_draft.id);
          if (mounted) {
            widget.onDraftUpdated(latest);
            setState(() => _draft = latest);
          }
        } catch (_) {
          // Keep the current item visible if refreshing also fails.
        }
      }
      if (mounted) {
        setState(() => _error = widget.responseLanguage == 'en'
            ? error.message
            : _t(
                '无法保存这项决定，请重试。',
                error.message,
                'Impossible d’enregistrer cette décision. Réessayez.',
              ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _selectDate() async {
    final current = _current;
    if (current == null || _saving) return;
    final parsed = DateTime.tryParse(current.event.eventDate ?? '');
    final selected = await showDatePicker(
      context: context,
      locale: Locale(widget.responseLanguage),
      initialDate: parsed ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (selected == null || !mounted) return;
    final date = '${selected.year.toString().padLeft(4, '0')}-'
        '${selected.month.toString().padLeft(2, '0')}-'
        '${selected.day.toString().padLeft(2, '0')}';
    await _saveEvent(
      current.event.withEventDate(date),
      DraftEventDisposition.pending,
    );
  }

  Future<bool> _handleSwipe(DismissDirection direction) async {
    final current = _current;
    if (current == null || _saving) return false;
    if (direction == DismissDirection.startToEnd) {
      await _decide(DraftEventDisposition.exclude);
      return false;
    }
    if (current.event.isAvoidedPurchase) return false;
    if (!_canRecord(current.event)) {
      if (current.event.eventDate == null ||
          current.event.eventDate!.trim().isEmpty) {
        await _selectDate();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_recordingBlocker(current.event)!)),
        );
      }
      return false;
    }
    await _decide(DraftEventDisposition.include);
    return false;
  }

  Future<void> _includeOrChooseDate() async {
    final current = _current;
    if (current == null || _saving) return;
    final date = current.event.eventDate?.trim();
    if (date == null || date.isEmpty) {
      await _selectDate();
      return;
    }
    await _decide(DraftEventDisposition.include);
  }

  void _acceptUpdate(FinancialDraft updated) {
    widget.onDraftUpdated(updated);
    if (updated.events
        .every((event) => event.disposition != DraftEventDisposition.pending)) {
      Navigator.of(context).pop(updated);
    } else {
      setState(() => _draft = updated);
    }
  }

  void _finish() => Navigator.of(context).pop(_draft);

  @override
  Widget build(BuildContext context) {
    final current = _current;
    if (current == null) {
      return const SizedBox.shrink();
    }
    final event = current.event;
    final reviewed = _totalToReview - _pending.length;
    final position = reviewed + 1;
    final blocker = _recordingBlocker(event);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: _saving ? null : _finish,
          icon: const Icon(Icons.close),
          tooltip: _t('稍后继续', 'Continue later', 'Continuer plus tard'),
        ),
        title: Text(_t('快速核对', 'Quick review', 'Vérification rapide')),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              Text(
                _t(
                    '第 $position 项，共 $_totalToReview 项',
                    'Item $position of $_totalToReview',
                    'Élément $position sur $_totalToReview'),
                key: const Key('quickReviewProgress'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: position / _totalToReview),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                runSpacing: 6,
                spacing: 16,
                children: [
                  if (!event.isAvoidedPurchase)
                    Text(
                      _t('← 左滑记录', '← Swipe left to record',
                          '← Glisser à gauche pour enregistrer'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    )
                  else
                    const SizedBox.shrink(),
                  Text(
                    _t('右滑排除 →', 'Swipe right to exclude →',
                        'Glisser à droite pour exclure →'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Dismissible(
                key: const Key('quickReviewSwipeCard'),
                direction: event.isAvoidedPurchase
                    ? DismissDirection.startToEnd
                    : DismissDirection.horizontal,
                confirmDismiss: _handleSwipe,
                background: _SwipeBackground(
                  alignment: Alignment.centerLeft,
                  color: Colors.orange.shade700,
                  icon: Icons.arrow_forward,
                  label: _t('排除', 'Exclude', 'Exclure'),
                ),
                secondaryBackground: _SwipeBackground(
                  alignment: Alignment.centerRight,
                  color: Colors.green.shade700,
                  icon: Icons.arrow_back,
                  label: _t('记录', 'Include', 'Inclure'),
                ),
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: FinPilotColors.mint,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(event.title,
                              style: const TextStyle(
                                  fontSize: 21, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 8),
                          Text('“${event.sourceText}”'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          children: [
                            _DetailRow(
                              label: _t('金额', 'Amount', 'Montant'),
                              value: '${event.currency} ${event.userNetAmount}',
                            ),
                            const Divider(),
                            _DetailRow(
                              label: _t('付款责任', 'Paid by', 'Payé par'),
                              value: _payerLabel(event),
                            ),
                            const Divider(),
                            _DetailRow(
                              key: const Key('quickReviewDatePicker'),
                              label: _t('日期', 'Date', 'Date'),
                              value: event.eventDate?.trim().isNotEmpty == true
                                  ? event.eventDate!
                                  : _t('选择日期', 'Choose date',
                                      'Choisir une date'),
                              icon: Icons.calendar_month_outlined,
                              onTap: _saving ? null : _selectDate,
                            ),
                            const Divider(),
                            _DetailRow(
                              label: _t('类别', 'Category', 'Catégorie'),
                              value: categoryLabel(
                                  event.category, widget.responseLanguage),
                            ),
                            const Divider(),
                            _DetailRow(
                              label: _t('商家', 'Merchant', 'Commerçant'),
                              value: event.merchant?.trim().isNotEmpty == true
                                  ? event.merchant!
                                  : _t('未知', 'Unknown', 'Inconnu'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _t(
                  '请逐项核对。快速核对不会自动记录任何内容。',
                  'Check each value. Quick review never records anything automatically.',
                  'Vérifiez chaque valeur. La vérification rapide n’enregistre jamais rien automatiquement.',
                ),
                textAlign: TextAlign.center,
              ),
              if (blocker != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(blocker, key: const Key('quickReviewBlocker')),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    key: const Key('quickReviewError'),
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 18),
              if (event.isAvoidedPurchase)
                FilledButton.icon(
                  key: const Key('quickReviewExclude'),
                  onPressed: _saving
                      ? null
                      : () => _decide(DraftEventDisposition.exclude),
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(_t('确认没有购买', 'Confirm not purchased',
                      'Confirmer l’absence d’achat')),
                )
              else ...[
                FilledButton.icon(
                  key: const Key('quickReviewInclude'),
                  onPressed: _saving ||
                          (!_canRecord(event) &&
                              event.eventDate?.trim().isNotEmpty == true)
                      ? null
                      : _includeOrChooseDate,
                  icon: Icon(event.eventDate?.trim().isNotEmpty == true
                      ? Icons.add_card_outlined
                      : Icons.calendar_month_outlined),
                  label: Text(event.eventDate?.trim().isNotEmpty == true
                      ? _t('记录这笔支出', 'Record this expense',
                          'Enregistrer cette dépense')
                      : _t('选择日期后记录', 'Choose date to record',
                          'Choisir la date avant d’enregistrer')),
                ),
                const SizedBox(height: 8),
                TextButton(
                  key: const Key('quickReviewExclude'),
                  onPressed: _saving
                      ? null
                      : () => _decide(DraftEventDisposition.exclude),
                  child: Text(
                      _t('不记录这项', "Don't record this", 'Ne pas enregistrer')),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _payerLabel(SpendingEvent event) => switch (event.payerType) {
        'user' => _t('你已付款', 'You paid', 'Vous avez payé'),
        'shared' => _t('共同承担', 'Shared', 'Partagé'),
        'other_person' => event.settlementStatus == 'repaid_by_user'
            ? _t('你已偿还', 'You repaid them', 'Vous avez remboursé')
            : _t('他人付款', 'Someone else paid', 'Une autre personne a payé'),
        'employer' => _t('雇主付款', 'Employer paid', 'Employeur'),
        _ => _t('未知', 'Unknown', 'Inconnu'),
      };
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.icon,
    this.onTap,
    super.key,
  });

  final String label;
  final String value;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: onTap == null
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 116,
            child: Text(label,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Text(value,
                  textAlign: TextAlign.end,
                  style: const TextStyle(fontWeight: FontWeight.w700))),
          if (icon != null) ...[
            const SizedBox(width: 8),
            Icon(icon, size: 20),
          ],
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(
        onTap: onTap, borderRadius: BorderRadius.circular(8), child: row);
  }
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({
    required this.alignment,
    required this.color,
    required this.icon,
    required this.label,
  });

  final Alignment alignment;
  final Color color;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        alignment: alignment,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(height: 4),
            Text(label,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w800)),
          ],
        ),
      );
}
