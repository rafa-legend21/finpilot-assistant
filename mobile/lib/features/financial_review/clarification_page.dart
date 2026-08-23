import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import 'draft_review_page.dart';
import 'models/financial_review_models.dart';
import 'widgets/clarification_bubble.dart';

class ClarificationPage extends StatefulWidget {
  const ClarificationPage({
    required this.api,
    required this.journal,
    required this.initialState,
    super.key,
  });

  final FinPilotApi api;
  final String journal;
  final ClarifyingFinancialDraft initialState;

  @override
  State<ClarificationPage> createState() => _ClarificationPageState();
}

class _ClarificationPageState extends State<ClarificationPage> {
  final _freeText = TextEditingController();
  late ClarifyingFinancialDraft _state;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _state = widget.initialState;
  }

  @override
  void dispose() {
    _freeText.dispose();
    super.dispose();
  }

  DraftClarification? get _openQuestion => _state.clarifications
      .where((item) => item.status == 'open' && item.requirement == 'required')
      .firstOrNull;

  String _answerText(DraftClarification item) {
    final freeText = item.answer?['free_text'] as String?;
    if (freeText != null) return freeText;
    final optionKey = item.answer?['option_key'] as String?;
    if (optionKey == null) return 'Answered';
    return item.options
            .where((option) => option.optionKey == optionKey)
            .firstOrNull
            ?.label ??
        'Answered';
  }

  Future<void> _answer({String? optionKey, String? freeText}) async {
    final question = _openQuestion;
    if (question == null || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final updated = await widget.api.answerClarification(
        draftId: _state.draft.id,
        expectedVersion: _state.draft.version,
        questionId: question.id,
        optionKey: optionKey,
        freeText: freeText,
      );
      if (mounted) {
        setState(() {
          _state = updated;
          _freeText.clear();
        });
      }
    } on ApiException catch (error) {
      if (error.statusCode == 409) {
        try {
          final latest = await widget.api.getClarifications(_state.draft.id);
          if (mounted) setState(() => _state = latest);
        } catch (_) {
          // Preserve the unsent free-text response when refresh fails.
        }
      }
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _reviewDraft() {
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
      builder: (_) => DraftReviewPage(api: widget.api, initialDraft: _state.draft),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final openQuestion = _openQuestion;
    return Scaffold(
      appBar: AppBar(title: const Text('A quick clarification')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          ClarificationBubble(text: widget.journal, isUser: true),
          ..._state.clarifications.where((item) => item.status == 'answered').expand(
                (item) => [
                  ClarificationBubble(
                    text: item.question,
                    subtitle: item.reason,
                    isUser: false,
                  ),
                  ClarificationBubble(
                    text: _answerText(item),
                    isUser: true,
                  ),
                ],
              ),
          if (openQuestion != null) ...[
            ClarificationBubble(
              key: const Key('activeClarification'),
              text: openQuestion.question,
              subtitle: openQuestion.reason,
              isUser: false,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: openQuestion.options
                  .map((option) => OutlinedButton(
                        onPressed: _submitting
                            ? null
                            : () => _answer(optionKey: option.optionKey),
                        child: Text(option.label),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 14),
            TextField(
              key: const Key('clarificationFreeText'),
              controller: _freeText,
              enabled: !_submitting,
              decoration: const InputDecoration(
                labelText: 'Something else',
                border: OutlineInputBorder(),
              ),
              minLines: 2,
              maxLines: 4,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _submitting || _freeText.text.trim().isEmpty
                    ? null
                    : () => _answer(freeText: _freeText.text.trim()),
                child: Text(_submitting ? 'Sending…' : 'Send answer'),
              ),
            ),
          ] else ...[
            const SizedBox(height: 20),
            const Icon(Icons.check_circle_outline, size: 48, color: Colors.green),
            const SizedBox(height: 10),
            const Text(
              'Your draft is ready to review',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            FilledButton(onPressed: _reviewDraft, child: const Text('Review draft')),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                key: const Key('clarificationError'),
                style: TextStyle(color: Colors.red.shade700),
              ),
            ),
        ],
      ),
    );
  }
}
