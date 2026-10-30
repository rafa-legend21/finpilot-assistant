import 'package:finpilot_assistant/core/api_client.dart';
import 'package:finpilot_assistant/core/voice_input.dart';
import 'package:finpilot_assistant/features/financial_review/journal_entry_page.dart';
import 'package:finpilot_assistant/features/financial_review/models/financial_review_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('confirmed draft clears the journal on return', (tester) async {
    await tester
        .pumpWidget(MaterialApp(home: JournalEntryPage(api: _FlowApi())));
    await _submitJournal(tester);

    await tester.ensureVisible(find.byKey(const Key('confirmDraftButton')));
    await tester.tap(find.byKey(const Key('confirmDraftButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(_journalText(tester), isEmpty);
  });

  testWidgets('back from confirmed screen also clears the journal',
      (tester) async {
    await tester
        .pumpWidget(MaterialApp(home: JournalEntryPage(api: _FlowApi())));
    await _submitJournal(tester);

    await tester.ensureVisible(find.byKey(const Key('confirmDraftButton')));
    await tester.tap(find.byKey(const Key('confirmDraftButton')));
    await tester.pumpAndSettle();
    expect(find.text('Draft confirmed'), findsWidgets);
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(_journalText(tester), isEmpty);
  });

  testWidgets('leaving review without confirmation preserves the journal',
      (tester) async {
    await tester
        .pumpWidget(MaterialApp(home: JournalEntryPage(api: _FlowApi())));
    await _submitJournal(tester);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(_journalText(tester), 'I decided not to buy the shoes');
  });

  testWidgets('confirmation after clarification also clears the journal',
      (tester) async {
    await tester.pumpWidget(
        MaterialApp(home: JournalEntryPage(api: _FlowApi(clarify: true))));
    await _submitJournal(tester);

    await tester.tap(find.text('I did not buy them'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review draft'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('confirmDraftButton')));
    await tester.tap(find.byKey(const Key('confirmDraftButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(_journalText(tester), isEmpty);
  });

  testWidgets('journal text survives a recoverable API error', (tester) async {
    await tester
        .pumpWidget(MaterialApp(home: JournalEntryPage(api: _FailingApi())));
    await tester.enterText(
        find.byKey(const Key('journalField')), 'Dinner was 80 dollars');
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('journalSubmit')));
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
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('journalSubmit')));
    await tester.pumpAndSettle();

    expect(find.text('A quick clarification'), findsOneWidget);
    expect(find.byKey(const Key('activeClarification')), findsOneWidget);
  });

  for (final (label, heading, question) in [
    ('中文', '请确认一下', '你需要还款吗？'),
    ('Français', 'Une petite précision', 'Devez-vous rembourser ?'),
  ]) {
    testWidgets('$label clarification uses the selected reply language',
        (tester) async {
      await tester
          .pumpWidget(MaterialApp(home: JournalEntryPage(api: _AwaitingApi())));
      await tester.tap(find.byKey(const Key('voiceLanguage')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('journalField')), 'Mother paid 18 CAD');
      await tester.drag(find.byType(ListView), const Offset(0, -700));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('journalSubmit')));
      await tester.pumpAndSettle();

      expect(find.text(heading), findsOneWidget);
      expect(find.text(question), findsOneWidget);
    });
  }

  for (final (label, localeId, language, journal) in [
    ('中文', 'zh_CN', 'zh', '妈妈付了18元'),
    ('English', 'en_US', 'en', 'Mother paid 18 dollars'),
    ('Français', 'fr_FR', 'fr', 'Ma mère a payé 18 euros'),
  ]) {
    testWidgets(
        '$label speech keeps the transcript reviewable and sends its language',
        (tester) async {
      final voice = _FakeVoiceInput();
      final api = _CapturingApi();
      await tester.pumpWidget(
          MaterialApp(home: JournalEntryPage(api: api, voiceInput: voice)));
      if (language != 'en') {
        await tester.tap(find.byKey(const Key('voiceLanguage')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const Key('voiceButton')));
      await tester.pump();
      expect(voice.localeId, localeId);
      voice.onWords!(journal);
      await tester.pump();
      expect(
          tester
              .widget<TextField>(find.byKey(const Key('journalField')))
              .controller!
              .text,
          journal);
      await tester.tap(find.byKey(const Key('voiceButton')));
      await tester.pump();
      await tester.drag(find.byType(ListView), const Offset(0, -700));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('journalSubmit')));
      await tester.pumpAndSettle();
      expect(api.text, journal);
      expect(api.responseLanguage, language);
    });
  }

  testWidgets('keeps final speech result after recognition reports done',
      (tester) async {
    final voice = _FakeVoiceInput();
    await tester.pumpWidget(MaterialApp(
        home: JournalEntryPage(api: _CapturingApi(), voiceInput: voice)));
    await tester.tap(find.byKey(const Key('voiceButton')));
    await tester.pump();

    voice.onStatus!('done');
    await tester.pump();
    voice.onWords!('Dinner cost 80 CAD');
    await tester.pump();

    expect(
        tester
            .widget<TextField>(find.byKey(const Key('journalField')))
            .controller!
            .text,
        'Dinner cost 80 CAD');
  });

  testWidgets('late speech result cannot overwrite a user correction',
      (tester) async {
    final voice = _FakeVoiceInput();
    await tester.pumpWidget(MaterialApp(
        home: JournalEntryPage(api: _CapturingApi(), voiceInput: voice)));
    await tester.tap(find.byKey(const Key('voiceButton')));
    await tester.pump();
    voice.onStatus!('done');
    await tester.pump();
    await tester.enterText(
        find.byKey(const Key('journalField')), 'I paid 80 CAD');

    voice.onWords!('I paid 18 CAD');
    await tester.pump();

    expect(
        tester
            .widget<TextField>(find.byKey(const Key('journalField')))
            .controller!
            .text,
        'I paid 80 CAD');
  });
}

Future<void> _submitJournal(WidgetTester tester) async {
  await tester.enterText(
      find.byKey(const Key('journalField')), 'I decided not to buy the shoes');
  await tester.pump();
  await tester.drag(find.byType(ListView), const Offset(0, -700));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('journalSubmit')));
  await tester.pumpAndSettle();
}

String _journalText(WidgetTester tester) => tester
    .widget<TextField>(find.byKey(const Key('journalField')))
    .controller!
    .text;

class _FlowApi implements FinPilotApi {
  _FlowApi({this.clarify = false});

  final bool clarify;

  @override
  Future<ClarifyingFinancialDraft> createDraftFromJournal({
    required String text,
    required CurrencyCode defaultCurrency,
    DateTime? referenceDate,
    String? responseLanguage,
  }) async =>
      _flowState(clarify);

  @override
  Future<ClarifyingFinancialDraft> answerClarification({
    required String draftId,
    required int expectedVersion,
    required String questionId,
    String? optionKey,
    String? freeText,
  }) async =>
      _flowState(false);

  @override
  Future<FinancialDraftConfirmation> confirmDraft({
    required String draftId,
    required int expectedVersion,
  }) async =>
      FinancialDraftConfirmation(
          draft: FinancialDraft.fromJson({
            ..._flowDraft(),
            'status': 'confirmed',
            'version': 2,
          }),
          transactionIds: const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ClarifyingFinancialDraft _flowState(bool clarify) =>
    ClarifyingFinancialDraft.fromJson({
      'clarification_state': clarify ? 'awaiting_required' : 'ready_for_review',
      'draft': _flowDraft(),
      'clarifications': clarify
          ? [
              {
                'id': 'question-1',
                'sequence': 1,
                'round_number': 1,
                'requirement': 'required',
                'status': 'open',
                'question': 'Did you buy them?',
                'reason': 'This changes your expense.',
                'options': [
                  {'option_key': 'not_bought', 'label': 'I did not buy them'}
                ],
                'answer': null,
              }
            ]
          : [],
    });

Map<String, dynamic> _flowDraft() => {
      'id': 'draft-1',
      'status': 'draft',
      'version': 1,
      'summary': 'No purchase was made.',
      'confirmation_questions': [],
      'events': [
        {
          'id': 'event-1',
          'position': 0,
          'disposition': 'exclude',
          'event': {
            'title': 'Shoes',
            'category': 'shopping',
            'transaction_type': 'expense',
            'event_date': null,
            'merchant': null,
            'payer_type': 'user',
            'paid_by_name': null,
            'settlement_status': 'not_applicable',
            'user_net_amount': '0',
            'currency': 'CAD',
            'amount_mentions': [],
            'quantities': [],
            'source_text': 'I decided not to buy the shoes',
            'confidence': 1.0,
            'needs_confirmation': false,
          },
        }
      ],
      'totals_by_currency': {},
    };

class _FakeVoiceInput implements VoiceInput {
  String? localeId;
  void Function(String)? onWords;
  void Function(String)? onStatus;

  @override
  Future<bool> initialize({
    required void Function(String) onStatus,
    required void Function() onError,
  }) async {
    this.onStatus = onStatus;
    return true;
  }

  @override
  Future<List<String>> availableLocales() async => ['zh_CN', 'en_US', 'fr_FR'];

  @override
  Future<void> listen({
    required String localeId,
    required void Function(String) onWords,
  }) async {
    this.localeId = localeId;
    this.onWords = onWords;
  }

  @override
  Future<void> stop() async {}
}

class _CapturingApi implements FinPilotApi {
  String? text;
  String? responseLanguage;

  @override
  Future<ClarifyingFinancialDraft> createDraftFromJournal({
    required String text,
    required CurrencyCode defaultCurrency,
    DateTime? referenceDate,
    String? responseLanguage,
  }) async {
    this.text = text;
    this.responseLanguage = responseLanguage;
    throw const ApiException('Draft unavailable');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
    String? responseLanguage,
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
            'question': switch (responseLanguage) {
              'zh' => '你需要还款吗？',
              'fr' => 'Devez-vous rembourser ?',
              _ => 'Do you need to pay her back?',
            },
            'reason': switch (responseLanguage) {
              'zh' => '这会改变你的费用。',
              'fr' => 'Cela change votre dépense.',
              _ => 'This changes your expense.',
            },
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
