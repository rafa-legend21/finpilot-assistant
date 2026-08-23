import 'package:finpilot_assistant/core/api_client.dart';
import 'package:finpilot_assistant/features/financial_review/journal_entry_page.dart';
import 'package:finpilot_assistant/features/financial_review/models/financial_review_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('journal text survives a recoverable API error', (tester) async {
    await tester
        .pumpWidget(MaterialApp(home: JournalEntryPage(api: _FailingApi())));
    await tester.enterText(
        find.byKey(const Key('journalField')), 'Dinner was 80 dollars');
    await tester.pump();
    await tester.tap(find.text('Review financial events'));
    await tester.pumpAndSettle();

    expect(find.text('Dinner was 80 dollars'), findsOneWidget);
    expect(find.byKey(const Key('journalError')), findsOneWidget);
  });

  testWidgets('required clarification opens the conversation before review',
      (tester) async {
    await tester
        .pumpWidget(MaterialApp(home: JournalEntryPage(api: _AwaitingApi())));
    await tester.enterText(
        find.byKey(const Key('journalField')), 'Mother paid 18 CAD');
    await tester.pump();
    await tester.tap(find.text('Review financial events'));
    await tester.pumpAndSettle();

    expect(find.text('A quick clarification'), findsOneWidget);
    expect(find.byKey(const Key('activeClarification')), findsOneWidget);
  });
}

class _FailingApi implements FinPilotApi {
  @override
  Future<StoryParseResponse> parseStory({
    required String text,
    required CurrencyCode defaultCurrency,
    DateTime? referenceDate,
  }) =>
      throw const ApiException('Try again');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AwaitingApi implements FinPilotApi {
  @override
  Future<ClarifyingFinancialDraft> createDraftFromJournal({
    required String text,
    required CurrencyCode defaultCurrency,
    DateTime? referenceDate,
  }) async =>
      ClarifyingFinancialDraft.fromJson({
        'clarification_state': 'awaiting_required',
        'draft': {
          'id': 'draft-1',
          'status': 'draft',
          'version': 1,
          'summary': 'Settlement is unresolved',
          'confirmation_questions': [],
          'events': [],
          'totals_by_currency': {},
        },
        'clarifications': [
          {
            'id': 'question-1',
            'sequence': 1,
            'round_number': 1,
            'requirement': 'required',
            'issue_type': 'payer_responsibility',
            'status': 'open',
            'question': 'Do you need to pay her back?',
            'reason': 'This changes your expense.',
            'related_event_id': null,
            'related_source_text': text,
            'options': [
              {'option_key': 'paid_by_other', 'label': 'I owe nothing'}
            ],
            'answer': null,
          }
        ],
      });

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
