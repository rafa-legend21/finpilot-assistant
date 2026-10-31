import 'package:finpilot_assistant/core/api_client.dart';
import 'package:finpilot_assistant/features/financial_review/draft_review_page.dart';
import 'package:finpilot_assistant/features/financial_review/models/financial_review_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('French draft card shows translated category', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: DraftReviewPage(
        api: _UnusedApi(),
        initialDraft: _draft(),
        responseLanguage: 'fr',
      ),
    ));

    expect(find.text('Restauration'), findsOneWidget);
    expect(find.text('dining'), findsNothing);
  });

  for (final (language, gesture) in [
    ('zh', '← 左滑记录'),
    ('en', '← Swipe left to record'),
    ('fr', '← Glisser à gauche pour enregistrer'),
  ]) {
    testWidgets('draft swipe guidance uses $language on a narrow phone',
        (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(MaterialApp(
        home: DraftReviewPage(
          api: _UnusedApi(),
          initialDraft: _draft(),
          responseLanguage: language,
        ),
      ));

      expect(find.text(gesture), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('pending events block confirmation and show review state',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: DraftReviewPage(api: _UnusedApi(), initialDraft: _draft()),
    ));

    expect(find.text('Review needed'), findsOneWidget);
    expect(find.text('Nothing will be recorded'), findsNothing);
    final button = tester
        .widget<FilledButton>(find.byKey(const Key('confirmDraftButton')));
    expect(button.onPressed, isNull);
  });

  testWidgets('draft cards handle include and exclude swipes directly',
      (tester) async {
    final api = _ReviewApi(_twoPendingDraft());
    await tester.pumpWidget(MaterialApp(
      home: DraftReviewPage(api: api, initialDraft: api.draft),
    ));

    expect(find.byKey(const Key('quickReviewButton')), findsNothing);
    expect(find.byKey(const Key('draftSwipeGuidance')), findsOneWidget);

    await tester.drag(
      find.byKey(const ValueKey('draftSwipe-dinner')),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();
    expect(api.decisions.first.$2, DraftEventDisposition.include);
    expect(find.text('Will be recorded'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('draftSwipe-coffee')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(
      find.byKey(const ValueKey('draftSwipe-coffee')),
      const Offset(500, 0),
    );
    await tester.pumpAndSettle();

    expect(api.decisions, [
      ('dinner', DraftEventDisposition.include, 1),
      ('coffee', DraftEventDisposition.exclude, 2),
    ]);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('confirmDraftButton')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('draft date chip opens calendar and saves the selected date',
      (tester) async {
    final api = _ReviewApi(_undatedPendingDraft());
    await tester.pumpWidget(MaterialApp(
      home: DraftReviewPage(api: api, initialDraft: api.draft),
    ));

    await tester.tap(find.byKey(const ValueKey('eventDate-undated-event')));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);

    final now = DateTime.now();
    await tester.tap(find.text('1').last);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    final expectedDate = '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-01';
    expect(find.text('Date: $expectedDate'), findsOneWidget);
    expect(api.decisions.single.$2, DraftEventDisposition.pending);
  });

  testWidgets('left swipe with no date opens calendar before recording',
      (tester) async {
    final api = _ReviewApi(_undatedPendingDraft());
    await tester.pumpWidget(MaterialApp(
      home: DraftReviewPage(api: api, initialDraft: api.draft),
    ));

    await tester.drag(
      find.byKey(const ValueKey('draftSwipe-undated-event')),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();

    expect(find.byType(DatePickerDialog), findsOneWidget);
    expect(api.decisions, isEmpty);
  });

  testWidgets('avoided purchase card does not claim the user paid',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: DraftReviewPage(
        api: _UnusedApi(),
        initialDraft: _avoidedDraft(),
      ),
    ));

    expect(find.text('Not purchased'), findsOneWidget);
    expect(find.text('You paid'), findsNothing);
    expect(find.text('Review needed'), findsOneWidget);
    final swipe = tester.widget<Dismissible>(
      find.byKey(const ValueKey('draftSwipe-avoided-event')),
    );
    expect(swipe.direction, DismissDirection.startToEnd);
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
    expect(find.text('Nothing will be recorded'), findsNothing);
    expect(find.text('Date: 2026-08-08'), findsNWidgets(2));
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('confirmDraftButton')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('displays unknown and known merchants without fabricating data',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: DraftReviewPage(
        api: _UnusedApi(),
        initialDraft: _merchantDraft(),
      ),
    ));

    expect(find.text('Unknown merchant'), findsWidgets);
    await tester.scrollUntilVisible(find.text('Cafe'), 300);
    expect(find.text('Cafe'), findsOneWidget);
  });

  testWidgets('legacy included event without a date blocks confirmation',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: DraftReviewPage(
        api: _UnusedApi(),
        initialDraft: _legacyUndatedDraft(),
      ),
    ));

    expect(find.text('Date required'), findsOneWidget);
    expect(find.text('Will be recorded'), findsNothing);
    expect(find.text('Date: 2026-08-08'), findsNothing);
    expect(find.text('Nothing will be recorded'), findsNothing);
    expect(
      find.text(
          'Review events marked Date required and add an exact transaction date.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('missingDateGuidance')), findsOneWidget);
    final button = tester
        .widget<FilledButton>(find.byKey(const Key('confirmDraftButton')));
    expect(button.onPressed, isNull);
  });

  testWidgets('all excluded events say that nothing will be recorded',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: DraftReviewPage(
        api: _UnusedApi(),
        initialDraft: _allExcludedDraft(),
      ),
    ));

    expect(find.text('Nothing will be recorded'), findsOneWidget);
    expect(find.byKey(const Key('nothingRecordedMessage')), findsOneWidget);
    expect(find.text('Included totals'), findsNothing);
    expect(find.textContaining('Date:'), findsNothing);
  });

  testWidgets('empty draft does not say that anything was excluded',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: DraftReviewPage(
        api: _UnusedApi(),
        initialDraft: _emptyDraft(),
      ),
    ));

    expect(find.text('Nothing will be recorded'), findsNothing);
    expect(find.textContaining('No financial events found'), findsOneWidget);
  });

  testWidgets('event amount and saved date fit a narrow review card',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: DraftReviewPage(
        api: _UnusedApi(),
        initialDraft: _singleIncludedDraft(),
      ),
    ));

    expect(find.text('Event amount'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('eventAmountValue'))).data,
      'CAD 18',
    );
    expect(find.text('Date: 2026-08-08'), findsOneWidget);
    expect(tester.takeException(), isNull);
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

FinancialDraft _twoPendingDraft() => FinancialDraft.fromJson({
      'id': 'swipe-draft',
      'status': 'draft',
      'version': 1,
      'summary': 'Two events',
      'confirmation_questions': [],
      'events': [
        _pendingEvent('dinner', 0, 'Dinner', '80.00', '2026-08-08'),
        _pendingEvent('coffee', 1, 'Coffee', '5.00', '2026-08-08'),
      ],
      'totals_by_currency': {},
    });

FinancialDraft _undatedPendingDraft() => FinancialDraft.fromJson({
      'id': 'undated-pending-draft',
      'status': 'draft',
      'version': 1,
      'summary': 'One event needs a date',
      'confirmation_questions': [],
      'events': [
        _pendingEvent('undated-event', 0, 'Dinner', '18.00', null),
      ],
      'totals_by_currency': {},
    });

Map<String, dynamic> _pendingEvent(
  String id,
  int position,
  String title,
  String amount,
  String? eventDate,
) =>
    {
      'id': id,
      'position': position,
      'disposition': 'pending',
      'event': {
        'title': title,
        'category': 'dining',
        'transaction_type': 'expense',
        'event_date': eventDate,
        'merchant': 'Cafe',
        'payer_type': 'user',
        'paid_by_name': null,
        'settlement_status': 'not_applicable',
        'user_net_amount': amount,
        'currency': 'CAD',
        'amount_mentions': [],
        'quantities': [],
        'source_text': '$title was $amount CAD',
        'confidence': 1.0,
        'needs_confirmation': false,
      },
    };

FinancialDraft _avoidedDraft() => FinancialDraft.fromJson({
      'id': 'avoided-draft',
      'status': 'draft',
      'version': 1,
      'summary': 'I decided not to buy the shoes.',
      'confirmation_questions': [],
      'events': [
        {
          'id': 'avoided-event',
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
                'explanation': 'The shoes were not purchased.',
              }
            ],
            'quantities': [],
            'source_text': 'I considered 180 CAD shoes but did not buy them.',
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

FinancialDraft _merchantDraft() => FinancialDraft.fromJson({
      'id': 'draft-merchant',
      'status': 'draft',
      'version': 1,
      'summary': 'Three merchants',
      'confirmation_questions': [],
      'events': [
        _reviewedEvent(
          'null-merchant',
          'exclude',
          'Coffee',
          '0',
          merchant: null,
        ),
        _reviewedEvent(
          'blank-merchant',
          'exclude',
          'Tea',
          '0',
          merchant: '   ',
        ),
        _reviewedEvent(
          'known-merchant',
          'include',
          'Dinner',
          '18.00',
          merchant: 'Cafe',
        ),
      ],
      'totals_by_currency': {'CAD': '18.00'},
    });

FinancialDraft _legacyUndatedDraft() => FinancialDraft.fromJson({
      'id': 'draft-undated',
      'status': 'draft',
      'version': 1,
      'summary': 'One undated event',
      'confirmation_questions': [],
      'events': [
        _reviewedEvent(
          'undated-event',
          'include',
          'Dinner',
          '18.00',
          merchant: null,
          eventDate: null,
        ),
      ],
      'totals_by_currency': {},
    });

FinancialDraft _allExcludedDraft() => FinancialDraft.fromJson({
      'id': 'draft-excluded',
      'status': 'draft',
      'version': 1,
      'summary': 'Two excluded events',
      'confirmation_questions': [],
      'events': [
        _reviewedEvent(
          'excluded-one',
          'exclude',
          'Coffee',
          '0',
          eventDate: null,
        ),
        _reviewedEvent(
          'excluded-two',
          'exclude',
          'Tea',
          '0',
          eventDate: null,
        ),
      ],
      'totals_by_currency': {},
    });

FinancialDraft _emptyDraft() => FinancialDraft.fromJson({
      'id': 'draft-empty',
      'status': 'draft',
      'version': 1,
      'summary': 'No events',
      'confirmation_questions': [],
      'events': [],
      'totals_by_currency': {},
    });

FinancialDraft _singleIncludedDraft() => FinancialDraft.fromJson({
      'id': 'draft-included',
      'status': 'draft',
      'version': 1,
      'summary': 'One included event',
      'confirmation_questions': [],
      'events': [
        _reviewedEvent('included-one', 'include', 'Coffee beans', '18'),
      ],
      'totals_by_currency': {'CAD': '18'},
    });

Map<String, dynamic> _reviewedEvent(
  String id,
  String disposition,
  String title,
  String amount, {
  String? merchant = 'Cafe',
  String? eventDate = '2026-08-08',
}) =>
    {
      'id': id,
      'position': disposition == 'include' ? 0 : 1,
      'disposition': disposition,
      'event': {
        'title': title,
        'category': 'dining',
        'transaction_type': 'expense',
        'event_date': eventDate,
        'merchant': merchant,
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

class _ReviewApi implements FinPilotApi {
  _ReviewApi(this.draft);

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
      'confirmation_questions': draft.confirmationQuestions,
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
