import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import 'iso_date_input_formatter.dart';
import 'models/financial_review_models.dart';

class EventEditPage extends StatefulWidget {
  const EventEditPage({
    required this.api,
    required this.draft,
    required this.draftEvent,
    this.responseLanguage = 'en',
    super.key,
  });

  final FinPilotApi api;
  final FinancialDraft draft;
  final FinancialDraftEvent draftEvent;
  final String responseLanguage;

  @override
  State<EventEditPage> createState() => _EventEditPageState();
}

class _EventEditPageState extends State<EventEditPage> {
  late final TextEditingController _amount;
  late final TextEditingController _merchant;
  late final TextEditingController _date;
  late String _category;
  late String _payer;
  late DraftEventDisposition _disposition;
  late int _version;
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
    final event = widget.draftEvent.event;
    _amount = TextEditingController(text: event.userNetAmount);
    _merchant = TextEditingController(text: event.merchant ?? '');
    _date = TextEditingController(text: event.eventDate ?? '');
    _category = event.category;
    _payer = event.payerType;
    _disposition = widget.draftEvent.disposition;
    _version = widget.draft.version;
  }

  @override
  void dispose() {
    _amount.dispose();
    _merchant.dispose();
    _date.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final avoidedPurchase = widget.draftEvent.event.isAvoidedPurchase;
    final amount = _amount.text.trim();
    if (!avoidedPurchase && !RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(amount)) {
      setState(() => _error = 'Enter a valid non-negative amount.');
      return;
    }
    var disposition =
        avoidedPurchase ? DraftEventDisposition.exclude : _disposition;
    if (_payer != 'user' &&
        _payer != 'shared' &&
        widget.draftEvent.event.settlementStatus != 'repaid_by_user' &&
        disposition == DraftEventDisposition.include) {
      disposition = DraftEventDisposition.exclude;
    }
    final eventDate = _date.text.trim();
    if (disposition == DraftEventDisposition.include &&
        !_isValidExactDate(eventDate)) {
      setState(() => _error =
          'Enter a valid date in YYYY-MM-DD format to include this event.');
      return;
    }
    if (disposition == DraftEventDisposition.include &&
        num.parse(amount) <= 0) {
      setState(() =>
          _error = 'Enter the amount you actually paid to include this event.');
      return;
    }
    final edited = avoidedPurchase
        ? widget.draftEvent.event
        : widget.draftEvent.event.edited(
            amount: amount,
            category: _category,
            payerType: _payer,
            merchant:
                _merchant.text.trim().isEmpty ? null : _merchant.text.trim(),
            eventDate: eventDate.isEmpty ? null : eventDate,
          );
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final draft = await widget.api.updateDraftEvent(
        draftId: widget.draft.id,
        eventId: widget.draftEvent.id,
        expectedVersion: _version,
        disposition: disposition,
        event: edited,
      );
      if (mounted) Navigator.of(context).pop(draft);
    } on ApiException catch (error) {
      if (error.statusCode == 409) {
        try {
          final latest = await widget.api.getDraft(widget.draft.id);
          _version = latest.version;
        } catch (_) {
          // Keep the user's unsaved fields even when refresh also fails.
        }
      }
      if (mounted) {
        setState(() => _error = error.statusCode == 409
            ? '${error.message} Latest draft loaded; review and save again.'
            : error.message);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  bool _isValidExactDate(String value) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (match == null) return false;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    if (year == 0) return false;
    final parsed = DateTime.utc(year, month, day);
    return parsed.year == year && parsed.month == month && parsed.day == day;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.draftEvent.event.isAvoidedPurchase) {
      return _buildAvoidedPurchase(context);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Review event')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(widget.draftEvent.event.sourceText,
              style: TextStyle(color: Colors.grey.shade700)),
          const SizedBox(height: 16),
          TextField(
            key: const Key('amountField'),
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: widget.draftEvent.event.settlementStatus ==
                      'repaid_by_user'
                  ? 'Amount you repaid (${widget.draftEvent.event.currency})'
                  : 'Your amount (${widget.draftEvent.event.currency})',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _category,
            decoration: const InputDecoration(labelText: 'Category'),
            items: expenseCategories
                .map((category) =>
                    DropdownMenuItem(value: category, child: Text(category)))
                .toList(),
            onChanged:
                _saving ? null : (value) => setState(() => _category = value!),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _payer,
            decoration:
                const InputDecoration(labelText: 'Payment responsibility'),
            items: const {
              'user': 'You paid',
              'shared': 'Shared',
              'other_person': 'Someone else paid',
              'employer': 'Employer paid',
              'unknown': 'Unknown',
            }
                .entries
                .map((entry) => DropdownMenuItem(
                    value: entry.key, child: Text(entry.value)))
                .toList(),
            onChanged:
                _saving ? null : (value) => setState(() => _payer = value!),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('merchantField'),
            controller: _merchant,
            decoration: const InputDecoration(
              labelText: 'Merchant (optional)',
              helperText: 'Leave blank if unknown',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('dateField'),
            controller: _date,
            keyboardType: TextInputType.datetime,
            inputFormatters: const [IsoDateInputFormatter()],
            decoration: InputDecoration(
              labelText:
                  widget.draftEvent.event.settlementStatus == 'repaid_by_user'
                      ? 'Date you repaid them (YYYY-MM-DD)'
                      : 'Date (YYYY-MM-DD)',
            ),
          ),
          const SizedBox(height: 16),
          SegmentedButton<DraftEventDisposition>(
            segments: const [
              ButtonSegment(
                value: DraftEventDisposition.pending,
                label: Text('Pending'),
                enabled: false,
              ),
              ButtonSegment(
                  value: DraftEventDisposition.include, label: Text('Include')),
              ButtonSegment(
                  value: DraftEventDisposition.exclude, label: Text('Exclude')),
            ],
            selected: {_disposition},
            onSelectionChanged: _saving
                ? null
                : (values) => setState(() => _disposition = values.first),
          ),
          if (_disposition == DraftEventDisposition.pending)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child:
                  Text('Choose Include or Exclude before saving this review.'),
            ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(_error!,
                key: const Key('editError'),
                style: TextStyle(color: Colors.red.shade700)),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving || _disposition == DraftEventDisposition.pending
                ? null
                : _save,
            child: Text(_saving ? 'Saving…' : 'Save review'),
          ),
          const SizedBox(height: 8),
          const Text(
            'FinPilot will validate this event again on the server before confirmation.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildAvoidedPurchase(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: Text(_t('核对未购买事项', 'Review an avoided purchase',
                'Vérifier un achat évité'))),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(widget.draftEvent.event.sourceText,
                style: TextStyle(color: Colors.grey.shade700)),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(_t(
                    '你最后没有购买，因此没有付款，也不会记录支出。如果其实买了，请返回修改故事。',
                    "You decided not to buy this. Nothing was paid or added to your expenses. If you did buy it, go back and correct your story.",
                    "Vous avez décidé de ne pas acheter cet article. Aucune dépense ne sera enregistrée. Si vous l'avez acheté, revenez corriger votre récit.")),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(_error!, style: TextStyle(color: Colors.red.shade700)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('confirmNoPurchaseButton'),
              onPressed: _saving ? null : _save,
              child: Text(_saving
                  ? _t('保存中…', 'Saving…', 'Enregistrement…')
                  : _t('确认未购买', 'Confirm no purchase',
                      'Confirmer l’achat évité')),
            ),
          ],
        ),
      );
}
