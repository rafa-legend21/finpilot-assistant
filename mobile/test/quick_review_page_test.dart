import 'package:finpilot_assistant/core/api_client.dart';
import 'package:finpilot_assistant/features/financial_review/draft_review_page.dart';
import 'package:finpilot_assistant/features/financial_review/models/financial_review_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('quick review records swipe decisions one event at a time',
      (tester) async {
    final api = _QuickReviewApi(_draft());
    await tester.pumpWidget(MaterialApp(
      home: DraftReviewPage(api: api, initialDraft: api.draft),
    ));

    await tester.tap(find.byKey(const Key('quickReviewButton')));
    await tester.pumpAndSettle();
    expect(find.text('Item 1 of 2'), findsOneWidget);
    expect(find.text('Dinner'), findsOneWidget);
    expect(find.text('CAD 80.00'), findsOneWidget);

    await tester.drag(
      find.byKey(const Key('quickReviewSwipeCard')),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('Item 2 of 2'), findsOneWidget);
    expect(find.text('Coffee'), findsOneWidget);

    await tester.drag(
      find.byKey(const Key('quickReviewSwipeCard')),
      const Offset(500, 0),
    );
    await tester.pumpAndSettle();

    expect(api.decisions, [
      ('dinner', DraftEventDisposition.include, 1),
      ('coffee', DraftEventDisposition.exclude, 2),
    ]);
    expect(find.text('Review your draft'), findsOneWidget);
    final confirm = tester
        .widget<FilledButton>(find.byKey(const Key('confirmDraftButton')));
    expect(confirm.onPressed, isNotNull);
  });

  testWidgets('calendar saves a missing date without manual edit',
      (tester) async {
    final api = _QuickReviewApi(_draft(missingDate: true, eventCount: 1));
    await tester.pumpWidget(MaterialApp(
      home: DraftReviewPage(api: api, initialDraft: api.draft),
    ));

    await tester.tap(find.byKey(const Key('quickReviewButton')));
    await tester.pumpAndSettle();

    expect(find.text('Add an exact date before recording this expense.'),
        findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('quickReviewDatePicker')),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const Key('quickReviewDatePicker')));
    await tester.pumpAndSettle();

    expect(find.byType(DatePickerDialog), findsOneWidget);
    expect(find.byKey(const Key('quickReviewEdit')), findsNothing);
    final now = DateTime.now();
    await tester.tap(find.text('1').last);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    final expectedDate = '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-01';
    expect(find.text(expectedDate), findsOneWidget);
    expect(api.decisions.single.$2, DraftEventDisposition.pending);
  });

  testWidgets('left swipe on a missing date opens the calendar',
      (tester) async {
    final api = _QuickReviewApi(_draft(missingDate: true, eventCount: 1));
    await tester.pumpWidget(MaterialApp(
      home: DraftReviewPage(api: api, initialDraft: api.draft),
    ));
    await tester.tap(find.byKey(const Key('quickReviewButton')));
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const Key('quickReviewSwipeCard')),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();

    expect(find.byType(DatePickerDialog), findsOneWidget);
    expect(api.decisions, isEmpty);
  });

  testWidgets('closing quick review keeps decisions already saved',
      (tester) async {
    final api = _QuickReviewApi(_draft());
    await tester.pumpWidget(MaterialApp(
      home: DraftReviewPage(api: api, initialDraft: api.draft),
    ));
    await tester.tap(find.byKey(const Key('quickReviewButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('quickReviewInclude')));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.text('Will be recorded'), findsOneWidget);
    expect(find.text('1 event still need review'), findsOneWidget);
    expect(api.draft.version, 2);
  });

  testWidgets('avoided purchase can only be confirmed as not purchased',
      (tester) async {
    final api = _QuickReviewApi(_avoidedDraft());
    await tester.pumpWidget(MaterialApp(
      home: DraftReviewPage(api: api, initialDraft: api.draft),
    ));
    await tester.tap(find.byKey(const Key('quickReviewButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('quickReviewInclude')), findsNothing);
    expect(find.text('Confirm not purchased'), findsOneWidget);
    await tester.tap(find.byKey(const Key('quickReviewExclude')));
    await tester.pumpAndSettle();

    expect(api.decisions.single.$2, DraftEventDisposition.exclude);
    expect(find.text('Nothing will be recorded'), findsOneWidget);
  });

  for (final (language, title, gesture) in [
    ('zh', '快速核对', '← 左滑记录'),
    ('en', 'Quick review', '← Swipe left to record'),
    ('fr', 'Vérification rapide', '← Glisser à gauche pour enregistrer'),
  ]) {
    testWidgets('quick review controls use $language', (tester) async {
      final api = _QuickReviewApi(_draft(eventCount: 1));
      await tester.pumpWidget(MaterialApp(
        home: DraftReviewPage(
          api: api,
          initialDraft: api.draft,
          responseLanguage: language,
        ),
      ));

      await tester.tap(find.byKey(const Key('quickReviewButton')));
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget);
      expect(find.text(gesture), findsOneWidget);
    });
  }
}

FinancialDraft _draft({bool missingDate = false, int eventCount = 2}) =>
    FinancialDraft.fromJson({
      'id': 'quick-draft',
      'status': 'draft',
      'version': 1,
      'summary': 'Two purchases to review.',
      'confirmation_questions': [],
      'events': [
        _event(
          id: 'dinner',
          position: 0,
          title: 'Dinner',
          amount: '80.00',
          date: missingDate ? null : '2026-10-30',
        ),
        if (eventCount > 1)
          _event(
            id: 'coffee',
            position: 1,
            title: 'Coffee',
            amount: '5.00',
            date: '2026-10-30',
          ),
      ],
      'totals_by_currency': {},
    });

FinancialDraft _avoidedDraft() => FinancialDraft.fromJson({
      'id': 'avoided-draft',
      'status': 'draft',
      'version': 1,
      'summary': 'Shoes were considered but not bought.',
      'confirmation_questions': [],
      'events': [
        {
          'id': 'shoes',
          'position': 0,
          'disposition': 'pending',
          'event': {
            'title': 'Shoes not bought',
            'category': 'shopping',
            'transaction_type': 'expense',
            'event_date': null,
            'merchant': null,
            'payer_type': 'user',
            'paid_by_name': null,
            'settlement_status': 'not_applicable',
            'user_net_amount': '0',
            'currency': 'CAD',
            'amount_mentions': [
              {
                'amount': '180',
                'currency': 'CAD',
                'role': 'saved_decision',
                'counted_in_user_total': false,
                'source_text': '180 CAD',
                'confidence': 1.0,
                'explanation': 'Not purchased.',
              }
            ],
            'quantities': [],
            'source_text': 'I did not buy the 180 CAD shoes.',
            'confidence': 1.0,
            'needs_confirmation': false,
          },
        },
      ],
      'totals_by_currency': {},
    });

Map<String, dynamic> _event({
  required String id,
  required int position,
  required String title,
  required String amount,
  required String? date,
}) =>
    {
      'id': id,
      'position': position,
      'disposition': 'pending',
      'event': {
        'title': title,
        'category': 'dining',
        'transaction_type': 'expense',
        'event_date': date,
        'merchant': 'Cafe',
        'payer_type': 'user',
        'paid_by_name': null,
        'settlement_status': 'not_applicable',
        'user_net_amount': amount,
        'currency': 'CAD',
        'amount_mentions': [],
        'quantities': [],
        'source_text': '$title was $amount CAD.',
        'confidence': 1.0,
        'needs_confirmation': false,
      },
    };

class _QuickReviewApi implements FinPilotApi {
  _QuickReviewApi(this.draft);

  FinancialDraft draft;
  final decisions = <(String, DraftEventDisposition, int)>[];

  @override
  Future<FinancialDraft> updateDraftEvent({
    required String draftId,
    required String eventId,
    required int expectedVersion,
    required DraftEventDisposition disposition,
    required SpendingEvent event,
  }) async {
    decisions.add((eventId, disposition, expectedVersion));
    final events = draft.events
        .map((item) => {
              'id': item.id,
              'position': item.position,
              'disposition':
                  item.id == eventId ? disposition.name : item.disposition.name,
              'event':
                  item.id == eventId ? event.toJson() : item.event.toJson(),
            })
        .toList();
    final totals = <String, String>{};
    for (final item in events) {
      if (item['disposition'] == 'include') {
        final included = item['event']! as Map<String, dynamic>;
        totals[included['currency']! as String] =
            included['user_net_amount']!.toString();
      }
    }
    draft = FinancialDraft.fromJson({
      'id': draft.id,
      'status': 'draft',
      'version': draft.version + 1,
      'summary': draft.summary,
      'confirmation_questions': [],
      'events': events,
      'totals_by_currency': totals,
    });
    return draft;
  }

  @override
  Future<FinancialDraft> getDraft(String draftId) async => draft;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
