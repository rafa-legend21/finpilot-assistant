import 'package:finpilot_assistant/core/api_client.dart';
import 'package:finpilot_assistant/features/financial_review/event_edit_page.dart';
import 'package:finpilot_assistant/features/financial_review/models/financial_review_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('merchant is optional and unknown merchant stays blank',
      (tester) async {
    final draft = _draft();
    await tester.pumpWidget(MaterialApp(
      home: EventEditPage(
        api: _RecordingApi(draft),
        draft: draft,
        draftEvent: draft.events.first,
      ),
    ));

    expect(find.text('Merchant (optional)'), findsOneWidget);
    expect(find.text('Leave blank if unknown'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('merchantField')))
          .controller!
          .text,
      isEmpty,
    );
    expect(find.text('Unknown merchant'), findsNothing);
  });

  testWidgets('pending is explicit and requires an include or exclude decision',
      (tester) async {
    final draft = _draft();
    await tester.pumpWidget(MaterialApp(
      home: EventEditPage(
          api: _RecordingApi(draft),
          draft: draft,
          draftEvent: draft.events.first),
    ));

    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Choose Include or Exclude before saving this review.'),
        findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
  });

  testWidgets('ordinary review preserves needs_confirmation', (tester) async {
    final draft = _draft();
    final api = _RecordingApi(draft);
    await tester.pumpWidget(MaterialApp(
      home:
          EventEditPage(api: api, draft: draft, draftEvent: draft.events.first),
    ));

    await tester.tap(find.text('Exclude'));
    await tester.pump();
    await tester.tap(find.text('Save review'));
    await tester.pumpAndSettle();

    expect(api.savedEvent?.needsConfirmation, isTrue);
    expect(api.savedDisposition, DraftEventDisposition.exclude);
    expect(api.savedEvent?.merchant, isNull);
    expect(api.savedEvent?.eventDate, isNull);
  });

  testWidgets('included event rejects blank malformed and impossible dates',
      (tester) async {
    final draft =
        _draft(settlementStatus: 'repaid_by_user', needsConfirmation: false);
    final api = _RecordingApi(draft);
    await tester.pumpWidget(MaterialApp(
      home: EventEditPage(
        api: api,
        draft: draft,
        draftEvent: draft.events.first,
      ),
    ));

    await tester.tap(find.text('Include'));
    await tester.pump();

    await tester.tap(find.text('Save review'));
    await tester.pump();
    expect(api.updateCalls, 0);
    expect(
      find.text(
          'Enter a valid date in YYYY-MM-DD format to include this event.'),
      findsOneWidget,
    );

    await tester.enterText(find.byKey(const Key('dateField')), '08/08/2026');
    tester.testTextInput.hide();
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pump();
    await tester.tap(find.text('Save review'));
    await tester.pump();
    expect(api.updateCalls, 0);

    await tester.ensureVisible(find.byKey(const Key('dateField')));
    await tester.enterText(find.byKey(const Key('dateField')), '2026-02-30');
    tester.testTextInput.hide();
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pump();
    await tester.tap(find.text('Save review'));
    await tester.pump();
    expect(api.updateCalls, 0);
  });

  testWidgets('valid exact date and unknown merchant are sent without a label',
      (tester) async {
    final draft =
        _draft(settlementStatus: 'repaid_by_user', needsConfirmation: false);
    final api = _RecordingApi(draft);
    await tester.pumpWidget(MaterialApp(
      home: EventEditPage(
        api: api,
        draft: draft,
        draftEvent: draft.events.first,
      ),
    ));

    await tester.tap(find.text('Include'));
    await tester.enterText(find.byKey(const Key('dateField')), '2026-08-08');
    await tester.tap(find.text('Save review'));
    await tester.pumpAndSettle();

    expect(api.updateCalls, 1);
    expect(api.savedDisposition, DraftEventDisposition.include);
    expect(api.savedEvent?.eventDate, '2026-08-08');
    expect(api.savedEvent?.merchant, isNull);
  });

  testWidgets('a completed repayment can be included after normal review',
      (tester) async {
    final draft = _draft(
      settlementStatus: 'repaid_by_user',
      needsConfirmation: false,
      eventDate: '2026-08-08',
    );
    final api = _RecordingApi(draft);
    await tester.pumpWidget(MaterialApp(
      home: EventEditPage(
        api: api,
        draft: draft,
        draftEvent: draft.events.first,
      ),
    ));

    await tester.tap(find.text('Include'));
    await tester.pump();
    await tester.tap(find.text('Save review'));
    await tester.pumpAndSettle();

    expect(api.savedDisposition, DraftEventDisposition.include);
    expect(api.savedEvent?.payerType, 'other_person');
    expect(api.savedEvent?.paidByName, 'mother');
    expect(api.savedEvent?.settlementStatus, 'repaid_by_user');
    expect(api.savedEvent?.userNetAmount, '18.00');
    final countedMentions = api.savedEvent!.amountMentions
        .where((mention) => mention.countedInUserTotal)
        .toList();
    expect(countedMentions, hasLength(1));
    expect(countedMentions.single.role, 'user_net_expense');
    expect(countedMentions.single.amount, '18.00');
    expect(countedMentions.single.currency, 'CAD');
  });

  test('editing preserves only realized third-party repayments', () {
    final repaid = _draft(
      settlementStatus: 'repaid_by_user',
      needsConfirmation: false,
    ).events.first.event.edited(
          amount: '18.00',
          category: 'grocery',
          payerType: 'other_person',
          merchant: null,
          eventDate: null,
        );
    final covered = _draft(
      settlementStatus: 'covered_by_other',
      needsConfirmation: false,
    ).events.first.event.edited(
          amount: '18.00',
          category: 'grocery',
          payerType: 'other_person',
          merchant: null,
          eventDate: null,
        );
    final repaymentDue = _draft(
      settlementStatus: 'repayment_due',
      needsConfirmation: false,
    ).events.first.event.edited(
          amount: '18.00',
          category: 'grocery',
          payerType: 'other_person',
          merchant: null,
          eventDate: null,
        );

    expect(repaid.userNetAmount, '18.00');
    expect(
      repaid.amountMentions.where((mention) => mention.countedInUserTotal),
      hasLength(1),
    );
    expect(covered.userNetAmount, '0');
    expect(
      covered.amountMentions.where((mention) => mention.countedInUserTotal),
      isEmpty,
    );
    expect(repaymentDue.userNetAmount, '0');
    expect(
      repaymentDue.amountMentions
          .where((mention) => mention.countedInUserTotal),
      isEmpty,
    );
  });
}

FinancialDraft _draft({
  String settlementStatus = 'unresolved',
  bool needsConfirmation = true,
  String? eventDate,
}) =>
    FinancialDraft.fromJson({
      'id': 'draft-1',
      'status': 'draft',
      'version': 1,
      'summary': 'Settlement needs clarification',
      'confirmation_questions': [],
      'events': [
        {
          'id': 'event-1',
          'position': 0,
          'disposition': 'pending',
          'event': {
            'title': 'Coffee beans',
            'category': 'grocery',
            'transaction_type': 'expense',
            'event_date': eventDate,
            'merchant': null,
            'payer_type': 'other_person',
            'paid_by_name': 'mother',
            'settlement_status': settlementStatus,
            'user_net_amount': '18.00',
            'currency': 'CAD',
            'amount_mentions': [],
            'quantities': [],
            'source_text': 'Mother paid 18 CAD',
            'confidence': 0.8,
            'needs_confirmation': needsConfirmation,
          },
        }
      ],
      'totals_by_currency': {},
    });

class _RecordingApi implements FinPilotApi {
  _RecordingApi(this.draft);

  final FinancialDraft draft;
  SpendingEvent? savedEvent;
  DraftEventDisposition? savedDisposition;
  int updateCalls = 0;

  @override
  Future<FinancialDraft> updateDraftEvent({
    required String draftId,
    required String eventId,
    required int expectedVersion,
    required DraftEventDisposition disposition,
    required SpendingEvent event,
  }) async {
    updateCalls += 1;
    savedEvent = event;
    savedDisposition = disposition;
    return draft;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
