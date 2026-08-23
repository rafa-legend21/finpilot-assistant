import 'package:finpilot_assistant/core/api_client.dart';
import 'package:finpilot_assistant/features/financial_review/draft_review_page.dart';
import 'package:finpilot_assistant/features/financial_review/models/financial_review_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('pending events block confirmation and show review state', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: DraftReviewPage(api: _UnusedApi(), initialDraft: _draft()),
    ));

    expect(find.text('Review needed'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byKey(const Key('confirmDraftButton')));
    expect(button.onPressed, isNull);
  });

  testWidgets('uses recording language for included and excluded status chips',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: DraftReviewPage(api: _UnusedApi(), initialDraft: _statusDraft()),
    ));

    expect(find.text('Will be recorded'), findsOneWidget);
    expect(find.text("Won't be recorded"), findsOneWidget);
    expect(find.text('Included'), findsNothing);
    expect(find.text('Excluded'), findsNothing);
  });
}

FinancialDraft _draft() => FinancialDraft.fromJson({
      'id': 'draft-1',
      'status': 'draft',
      'version': 1,
      'summary': 'One event',
      'confirmation_questions': [],
      'events': [
        {
          'id': 'event-1',
          'position': 0,
          'disposition': 'pending',
          'event': {
            'title': 'Dinner',
            'category': 'dining',
            'transaction_type': 'expense',
            'event_date': '2026-08-08',
            'merchant': 'Cafe',
            'payer_type': 'user',
            'paid_by_name': null,
            'user_net_amount': '80.00',
            'currency': 'CAD',
            'amount_mentions': [],
            'quantities': [],
            'source_text': 'Dinner was 80 dollars',
            'confidence': 1.0,
            'needs_confirmation': false,
          },
        }
      ],
      'totals_by_currency': {},
    });

FinancialDraft _statusDraft() => FinancialDraft.fromJson({
      'id': 'draft-2',
      'status': 'draft',
      'version': 1,
      'summary': 'Two reviewed events',
      'confirmation_questions': [],
      'events': [
        _reviewedEvent('included-event', 'include', 'Dinner', '80.00'),
        _reviewedEvent('excluded-event', 'exclude', 'Coffee', '0'),
      ],
      'totals_by_currency': {},
    });

Map<String, dynamic> _reviewedEvent(
  String id,
  String disposition,
  String title,
  String amount,
) =>
    {
      'id': id,
      'position': disposition == 'include' ? 0 : 1,
      'disposition': disposition,
      'event': {
        'title': title,
        'category': 'dining',
        'transaction_type': 'expense',
        'event_date': '2026-08-08',
        'merchant': 'Cafe',
        'payer_type': disposition == 'include' ? 'user' : 'other_person',
        'paid_by_name': disposition == 'include' ? null : 'mother',
        'settlement_status':
            disposition == 'include' ? 'not_applicable' : 'covered_by_other',
        'user_net_amount': amount,
        'currency': 'CAD',
        'amount_mentions': [],
        'quantities': [],
        'source_text': '$title was $amount CAD',
        'confidence': 1.0,
        'needs_confirmation': false,
      },
    };

class _UnusedApi implements FinPilotApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
