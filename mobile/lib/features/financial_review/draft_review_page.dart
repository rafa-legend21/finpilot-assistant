import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/finpilot_theme.dart';
import 'event_edit_page.dart';
import 'models/financial_review_models.dart';
import 'widgets/draft_event_card.dart';

enum PostConfirmationChoice { addMore, home }

class DraftReviewPage extends StatefulWidget {
  const DraftReviewPage(
      {required this.api,
      required this.initialDraft,
      this.responseLanguage = 'en',
      this.onConfirmed,
      super.key});
  final FinPilotApi api;
  final FinancialDraft initialDraft;
  final String responseLanguage;
  final VoidCallback? onConfirmed;

  @override
  State<DraftReviewPage> createState() => _DraftReviewPageState();
}

class _DraftReviewPageState extends State<DraftReviewPage> {
  late FinancialDraft _draft;
  bool _confirming = false;
  String? _updatingEventId;
  FinancialDraftConfirmation? _confirmation;
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
  }

  int get _pendingCount => _draft.events
      .where((event) => event.disposition == DraftEventDisposition.pending)
      .length;

  int get _missingIncludedDateCount => _draft.events
      .where((event) =>
          event.disposition == DraftEventDisposition.include &&
          (event.event.eventDate == null ||
              event.event.eventDate!.trim().isEmpty))
      .length;

  bool get _nothingWillBeRecorded =>
      _draft.events.isNotEmpty &&
      _draft.totalsByCurrency.isEmpty &&
      _draft.events.every(
        (event) => event.disposition == DraftEventDisposition.exclude,
      );

  bool get _canConfirm =>
      _draft.status == DraftStatus.draft &&
      _draft.events.isNotEmpty &&
      _pendingCount == 0 &&
      _missingIncludedDateCount == 0 &&
      _updatingEventId == null &&
      !_confirming;

  bool get _busy => _confirming || _updatingEventId != null;

  Future<void> _edit(FinancialDraftEvent event) async {
    if (_busy || _draft.status != DraftStatus.draft) return;
    final updated =
        await Navigator.of(context).push<FinancialDraft>(MaterialPageRoute(
      builder: (_) => EventEditPage(
        api: widget.api,
        draft: _draft,
        draftEvent: event,
        responseLanguage: widget.responseLanguage,
      ),
    ));
    if (updated != null && mounted) setState(() => _draft = updated);
  }

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

  String _recordingBlocker(SpendingEvent event) {
    if (event.needsConfirmation) {
      return _t(
        '这笔事件仍有未解决的信息，暂时不能记录。',
        'This event still has unresolved information and cannot be recorded yet.',
        'Cet événement contient encore des informations non résolues et ne peut pas encore être enregistré.',
      );
    }
    if (event.transactionType != 'expense') {
      return _t(
        '当前账本只记录支出，这项内容暂时不能记录。',
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
    return _t(
      '记录支出前需要选择准确日期。',
      'Choose an exact date before recording this expense.',
      'Choisissez une date exacte avant d’enregistrer cette dépense.',
    );
  }

  Future<void> _saveEvent(
    FinancialDraftEvent draftEvent,
    SpendingEvent event,
    DraftEventDisposition disposition,
  ) async {
    if (_busy || _draft.status != DraftStatus.draft) return;
    setState(() {
      _updatingEventId = draftEvent.id;
      _error = null;
    });
    try {
      final updated = await widget.api.updateDraftEvent(
        draftId: _draft.id,
        eventId: draftEvent.id,
        expectedVersion: _draft.version,
        disposition: disposition,
        event: event,
      );
      if (mounted) setState(() => _draft = updated);
    } on ApiException catch (error) {
      if (error.statusCode == 409) {
        try {
          final latest = await widget.api.getDraft(_draft.id);
          if (mounted) setState(() => _draft = latest);
        } catch (_) {
          // Keep the current review visible if refreshing also fails.
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
      if (mounted) setState(() => _updatingEventId = null);
    }
  }

  Future<void> _selectDate(FinancialDraftEvent draftEvent) async {
    if (_busy || _draft.status != DraftStatus.draft) return;
    final parsed = DateTime.tryParse(draftEvent.event.eventDate ?? '');
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
      draftEvent,
      draftEvent.event.withEventDate(date),
      draftEvent.disposition,
    );
  }

  Future<bool> _handleSwipe(
    FinancialDraftEvent draftEvent,
    DismissDirection direction,
  ) async {
    if (_busy || _draft.status != DraftStatus.draft) return false;
    if (direction == DismissDirection.startToEnd) {
      await _saveEvent(
        draftEvent,
        draftEvent.event,
        DraftEventDisposition.exclude,
      );
      return false;
    }
    final event = draftEvent.event;
    if (event.isAvoidedPurchase) return false;
    final date = event.eventDate?.trim();
    if (date == null || date.isEmpty) {
      await _selectDate(draftEvent);
      return false;
    }
    if (!_canRecord(event)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_recordingBlocker(event))),
        );
      }
      return false;
    }
    await _saveEvent(
      draftEvent,
      event,
      DraftEventDisposition.include,
    );
    return false;
  }

  Future<void> _confirm() async {
    if (!_canConfirm) return;
    setState(() {
      _confirming = true;
      _error = null;
    });
    try {
      final result = await widget.api.confirmDraft(
        draftId: _draft.id,
        expectedVersion: _draft.version,
      );
      if (mounted) {
        widget.onConfirmed?.call();
        setState(() {
          _confirmation = result;
          _draft = result.draft;
        });
      }
    } on ApiException catch (error) {
      if (error.statusCode == 409) {
        try {
          final latest = await widget.api.getDraft(_draft.id);
          if (mounted) setState(() => _draft = latest);
        } catch (_) {
          // Keep the current review visible if refresh fails.
        }
      }
      if (mounted) {
        setState(() => _error = widget.responseLanguage == 'en'
            ? error.message
            : error.statusCode == 409
                ? _t('草稿已更新，请核对后重试。', error.message,
                    'Le brouillon a été actualisé. Vérifiez-le, puis réessayez.')
                : _t('无法确认草稿，请重试。', error.message,
                    'Impossible de confirmer le brouillon. Réessayez.'));
      }
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  Future<void> _cancel() async {
    if (_busy || _draft.status != DraftStatus.draft) return;
    setState(() => _confirming = true);
    try {
      await widget.api
          .cancelDraft(draftId: _draft.id, expectedVersion: _draft.version);
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (error) {
      if (error.statusCode == 409) {
        try {
          final latest = await widget.api.getDraft(_draft.id);
          if (mounted) setState(() => _draft = latest);
        } catch (_) {
          // Keep the current review visible if refresh fails.
        }
      }
      if (mounted) {
        setState(() => _error = widget.responseLanguage == 'en'
            ? error.message
            : error.statusCode == 409
                ? _t('草稿已更新，请核对后重试。', error.message,
                    'Le brouillon a été actualisé. Vérifiez-le, puis réessayez.')
                : _t('无法取消草稿，请重试。', error.message,
                    'Impossible d’annuler le brouillon. Réessayez.'));
      }
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  Widget _buildSwipeCard(FinancialDraftEvent draftEvent) {
    final event = draftEvent.event;
    final canChooseDate = !event.isAvoidedPurchase &&
        draftEvent.disposition != DraftEventDisposition.exclude;
    final card = DraftEventCard(
      draftEvent: draftEvent,
      responseLanguage: widget.responseLanguage,
      isBusy: _updatingEventId == draftEvent.id,
      onDateTap: canChooseDate ? () => _selectDate(draftEvent) : null,
      onEdit: () => _edit(draftEvent),
    );
    if (_draft.status != DraftStatus.draft) return card;
    return Dismissible(
      key: ValueKey('draftSwipe-${draftEvent.id}'),
      direction: _busy
          ? DismissDirection.none
          : event.isAvoidedPurchase
              ? DismissDirection.startToEnd
              : DismissDirection.horizontal,
      confirmDismiss: (direction) => _handleSwipe(draftEvent, direction),
      background: _DraftSwipeBackground(
        alignment: Alignment.centerLeft,
        color: Colors.orange.shade700,
        icon: Icons.arrow_forward,
        label: _t('排除', 'Exclude', 'Exclure'),
      ),
      secondaryBackground: _DraftSwipeBackground(
        alignment: Alignment.centerRight,
        color: Colors.green.shade700,
        icon: Icons.arrow_back,
        label: _t('记录', 'Include', 'Inclure'),
      ),
      child: card,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_confirmation != null) return _success(context);
    return Scaffold(
      appBar: AppBar(
        title:
            Text(_t('核对草稿', 'Review your draft', 'Vérifier votre brouillon')),
        actions: [
          TextButton(
            onPressed:
                _busy || _draft.status != DraftStatus.draft ? null : _cancel,
            child: Text(_t('取消草稿', 'Cancel draft', 'Annuler le brouillon')),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: FinPilotColors.mint,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.fact_check_outlined,
                        color: FinPilotColors.forest, size: 28),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              _t('核对摘要', 'Review summary', 'Résumé à vérifier'),
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 7),
                          Text(_draft.summary,
                              style: const TextStyle(height: 1.4)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(_t('财务事件', 'Financial events', 'Événements financiers'),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              if (_draft.events.isNotEmpty &&
                  _draft.status == DraftStatus.draft) ...[
                Container(
                  key: const Key('draftSwipeGuidance'),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: FinPilotColors.mint.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 6,
                    alignment: WrapAlignment.spaceBetween,
                    children: [
                      Text(
                        _t('← 左滑记录', '← Swipe left to record',
                            '← Glisser à gauche pour enregistrer'),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        _t('右滑排除 →', 'Swipe right to exclude →',
                            'Glisser à droite pour exclure →'),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        _t('点击日期可打开日历', 'Tap the date to open the calendar',
                            'Touchez la date pour ouvrir le calendrier'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (_draft.totalsByCurrency.isNotEmpty) ...[
                Text(_t('计入的总额', 'Included totals', 'Totaux inclus'),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: _draft.totalsByCurrency.entries
                      .map((entry) =>
                          Chip(label: Text('${entry.key} ${entry.value}')))
                      .toList(),
                ),
              ] else if (_nothingWillBeRecorded) ...[
                Text(
                  _t('不会记录任何交易', 'Nothing will be recorded',
                      'Aucune transaction ne sera enregistrée'),
                  key: const Key('nothingRecordedMessage'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
              if (_draft.confirmationQuestions.isNotEmpty) ...[
                const SizedBox(height: 16),
                ..._draft.confirmationQuestions.map((question) => ListTile(
                      leading:
                          const Icon(Icons.help_outline, color: Colors.amber),
                      title: Text(question['question'] as String? ??
                          _t('请核对这笔事件。', 'Please review this event.',
                              'Veuillez vérifier cet événement.')),
                      subtitle: Text(question['reason'] as String? ?? ''),
                    )),
              ],
              const SizedBox(height: 12),
              if (_draft.events.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(_t(
                        '没有找到财务事件。请返回并修改日记内容。',
                        'No financial events found. Go back and edit your journal entry.',
                        'Aucun événement financier trouvé. Revenez en arrière et modifiez votre récit.')),
                  ),
                )
              else
                ..._draft.events.map(_buildSwipeCard),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!,
                      key: const Key('draftError'),
                      style: TextStyle(color: Colors.red.shade700)),
                ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_pendingCount > 0)
                    Text(_t(
                        '还有 $_pendingCount 笔事件需要核对',
                        '$_pendingCount event${_pendingCount == 1 ? '' : 's'} still need review',
                        '$_pendingCount événement(s) restent à vérifier')),
                  if (_missingIncludedDateCount > 0)
                    Text(
                      _t(
                          '请为标记为需要日期的事件填写准确交易日期。',
                          'Review events marked Date required and add an exact transaction date.',
                          'Ajoutez une date exacte aux événements dont la date est requise.'),
                      key: const Key('missingDateGuidance'),
                      textAlign: TextAlign.center,
                    ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const Key('confirmDraftButton'),
                      onPressed: _canConfirm ? _confirm : null,
                      icon: _confirming
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.check_circle_outline),
                      label: Text(_confirming
                          ? _t('确认中…', 'Confirming…', 'Confirmation…')
                          : _t('确认草稿', 'Confirm draft',
                              'Confirmer le brouillon')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _success(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: Text(_t('草稿已确认', 'Draft confirmed', 'Brouillon confirmé'))),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle,
                    size: 64, color: Colors.green.shade700),
                const SizedBox(height: 16),
                Text(_t('草稿已确认', 'Draft confirmed', 'Brouillon confirmé'),
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(_t(
                    '已保存 ${_confirmation!.transactionIds.length} 笔交易',
                    '${_confirmation!.transactionIds.length} transaction(s) saved',
                    '${_confirmation!.transactionIds.length} transaction(s) enregistrée(s)')),
                const SizedBox(height: 20),
                Text(
                  _t('还有什么需要添加的吗？', 'Anything else to add?',
                      'Avez-vous autre chose à ajouter ?'),
                  key: const Key('addMorePrompt'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  key: const Key('addMoreYes'),
                  onPressed: () =>
                      Navigator.of(context).pop(PostConfirmationChoice.addMore),
                  child: Text(_t(
                      '有，继续添加', 'Yes, add more', 'Oui, ajouter autre chose')),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  key: const Key('addMoreNo'),
                  onPressed: () =>
                      Navigator.of(context).pop(PostConfirmationChoice.home),
                  child: Text(_t(
                      '没有了，回到首页', 'No, go home', 'Non, revenir à l’accueil')),
                ),
              ],
            ),
          ),
        ),
      );
}

class _DraftSwipeBackground extends StatelessWidget {
  const _DraftSwipeBackground({
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
        margin: const EdgeInsets.symmetric(vertical: 4),
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
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
}
