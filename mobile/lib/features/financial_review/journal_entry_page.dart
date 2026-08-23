import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import 'clarification_page.dart';
import 'draft_review_page.dart';
import 'models/financial_review_models.dart';

class JournalEntryPage extends StatefulWidget {
  const JournalEntryPage({required this.api, super.key});
  final FinPilotApi api;

  @override
  State<JournalEntryPage> createState() => _JournalEntryPageState();
}

class _JournalEntryPageState extends State<JournalEntryPage> {
  final _controller = TextEditingController();
  CurrencyCode _currency = CurrencyCode.CAD;
  DateTime? _referenceDate;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.api.createDraftFromJournal(
        text: text,
        defaultCurrency: _currency,
        referenceDate: _referenceDate,
      );
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => result.clarificationState == 'awaiting_required'
            ? ClarificationPage(api: widget.api, journal: text, initialState: result)
            : DraftReviewPage(api: widget.api, initialDraft: result.draft),
      ));
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Unable to prepare your draft. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tell FinPilot your story')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Write naturally. Nothing is added to your ledger until you review and confirm.'),
          const SizedBox(height: 16),
          TextField(
            key: const Key('journalField'),
            controller: _controller,
            minLines: 7,
            maxLines: 12,
            enabled: !_loading,
            decoration: const InputDecoration(
              labelText: 'Journal entry',
              hintText: 'I had dinner with a friend…',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<CurrencyCode>(
            initialValue: _currency,
            decoration: const InputDecoration(labelText: 'Default currency'),
            items: CurrencyCode.values
                .map((currency) => DropdownMenuItem(value: currency, child: Text(currency.name)))
                .toList(),
            onChanged: _loading ? null : (value) => setState(() => _currency = value!),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _loading
                ? null
                : () async {
                    final selected = await showDatePicker(
                      context: context,
                      initialDate: _referenceDate ?? DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now(),
                    );
                    if (selected != null) setState(() => _referenceDate = selected);
                  },
            icon: const Icon(Icons.calendar_today_outlined),
            label: Text(_referenceDate == null
                ? 'Add reference date (optional)'
                : '${_referenceDate!.year}-${_referenceDate!.month.toString().padLeft(2, '0')}-${_referenceDate!.day.toString().padLeft(2, '0')}'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, key: const Key('journalError'), style: TextStyle(color: Colors.red.shade700)),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _controller.text.trim().isEmpty || _loading ? null : _submit,
            icon: _loading
                ? const SizedBox.square(
                    dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.auto_awesome),
            label: Text(_loading ? 'Understanding your story…' : 'Review financial events'),
          ),
        ],
      ),
    );
  }
}
