import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import 'event_edit_page.dart';
import 'models/financial_review_models.dart';
import 'widgets/draft_event_card.dart';

class DraftReviewPage extends StatefulWidget {
  const DraftReviewPage({required this.api, required this.initialDraft, super.key});
  final FinPilotApi api;
  final FinancialDraft initialDraft;

  @override
  State<DraftReviewPage> createState() => _DraftReviewPageState();
}

class _DraftReviewPageState extends State<DraftReviewPage> {
  late FinancialDraft _draft;
  bool _confirming = false;
  FinancialDraftConfirmation? _confirmation;
  String? _error;

  @override
  void initState() {
    super.initState();
    _draft = widget.initialDraft;
  }

  int get _pendingCount =>
      _draft.events.where((event) => event.disposition == DraftEventDisposition.pending).length;

  bool get _canConfirm => _draft.status == DraftStatus.draft &&
      _draft.events.isNotEmpty &&
      _pendingCount == 0 &&
      !_confirming;

  Future<void> _edit(FinancialDraftEvent event) async {
    if (_confirming || _draft.status != DraftStatus.draft) return;
    final updated = await Navigator.of(context).push<FinancialDraft>(MaterialPageRoute(
      builder: (_) => EventEditPage(api: widget.api, draft: _draft, draftEvent: event),
    ));
    if (updated != null && mounted) setState(() => _draft = updated);
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
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  Future<void> _cancel() async {
    if (_confirming || _draft.status != DraftStatus.draft) return;
    setState(() => _confirming = true);
    try {
      await widget.api.cancelDraft(draftId: _draft.id, expectedVersion: _draft.version);
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
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_confirmation != null) return _success(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Review your draft'),
        actions: [
          TextButton(
            onPressed: _confirming || _draft.status != DraftStatus.draft ? null : _cancel,
            child: const Text('Cancel draft'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
        children: [
          Text(_draft.summary, style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 18),
          if (_draft.totalsByCurrency.isNotEmpty) ...[
            const Text('Included totals', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: _draft.totalsByCurrency.entries
                  .map((entry) => Chip(label: Text('${entry.key} ${entry.value}')))
                  .toList(),
            ),
          ],
          if (_draft.confirmationQuestions.isNotEmpty) ...[
            const SizedBox(height: 16),
            ..._draft.confirmationQuestions.map((question) => ListTile(
                  leading: const Icon(Icons.help_outline, color: Colors.amber),
                  title: Text(question['question'] as String? ?? 'Please review this event.'),
                  subtitle: Text(question['reason'] as String? ?? ''),
                )),
          ],
          const SizedBox(height: 12),
          if (_draft.events.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text('No financial events found. Go back and edit your journal entry.'),
              ),
            )
          else
            ..._draft.events.map((event) => DraftEventCard(
                  key: ValueKey(event.id),
                  draftEvent: event,
                  onEdit: () => _edit(event),
                )),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, key: const Key('draftError'),
                  style: TextStyle(color: Colors.red.shade700)),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_pendingCount > 0)
                Text('$_pendingCount event${_pendingCount == 1 ? '' : 's'} still need review'),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('confirmDraftButton'),
                  onPressed: _canConfirm ? _confirm : null,
                  icon: _confirming
                      ? const SizedBox.square(
                          dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check_circle_outline),
                  label: Text(_confirming ? 'Confirming…' : 'Confirm draft'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _success(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Draft confirmed')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, size: 64, color: Colors.green.shade700),
                const SizedBox(height: 16),
                const Text('Draft confirmed',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text('${_confirmation!.transactionIds.length} transaction(s) saved'),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Done'),
                ),
              ],
            ),
          ),
        ),
      );
}
