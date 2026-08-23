import 'package:finpilot_assistant/core/api_client.dart';
import 'package:finpilot_assistant/features/financial_review/clarification_page.dart';
import 'package:finpilot_assistant/features/financial_review/models/financial_review_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows journal and required question conversationally', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ClarificationPage(
        api: _ClarificationApi(),
        journal: 'Mother bought coffee beans',
        initialState: _state(),
      ),
    ));

    expect(find.text('Mother bought coffee beans'), findsOneWidget);
    expect(find.byKey(const Key('activeClarification')), findsOneWidget);
    expect(find.text('Someone else paid'), findsOneWidget);
  });

  testWidgets('free text and visible error survive recoverable failure', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ClarificationPage(
        api: _ClarificationApi(fail: true),
        journal: 'Mother bought coffee beans',
        initialState: _state(),
      ),
    ));
    await tester.enterText(
      find.byKey(const Key('clarificationFreeText')),
      'I paid her back',
    );
    await tester.pump();
    await tester.tap(find.text('Send answer'));
    await tester.pumpAndSettle();

    expect(find.text('I paid her back'), findsOneWidget);
    expect(find.byKey(const Key('clarificationError')), findsOneWidget);
  });

  testWidgets('answered options render persisted labels and hide internal keys',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ClarificationPage(
        api: _ClarificationApi(),
        journal: 'Mother bought coffee beans',
        initialState: _historyState(),
      ),
    ));

    expect(find.text('Keep this unresolved and exclude it'), findsOneWidget);
    expect(find.text('They paid for me — I owe nothing'), findsOneWidget);
    expect(find.text('I paid her back yesterday'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('Answered'), findsOneWidget);
    expect(find.text('keep_unresolved'), findsNothing);
    expect(find.text('paid_by_other'), findsNothing);
    expect(find.text('repaid_by_user'), findsNothing);
    expect(find.text('repayment_due'), findsNothing);
    expect(find.text('Superseded question'), findsNothing);
  });
}

ClarifyingFinancialDraft _state() => ClarifyingFinancialDraft.fromJson({
      'clarification_state': 'awaiting_required',
      'draft': {
        'id': 'draft-1',
        'status': 'draft',
        'version': 1,
        'summary': 'Clarify payer',
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
          'question': 'Who paid?',
          'reason': 'This changes your expense.',
          'related_event_id': null,
          'related_source_text': 'Mother bought coffee beans',
          'options': [
            {'option_key': 'paid_by_other', 'label': 'Someone else paid'}
          ],
          'answer': null,
        }
      ],
    });

ClarifyingFinancialDraft _historyState() => ClarifyingFinancialDraft.fromJson({
      'clarification_state': 'ready_for_review',
      'draft': {
        'id': 'draft-1',
        'status': 'draft',
        'version': 2,
        'summary': 'Clarifications complete',
        'confirmation_questions': [],
        'events': [],
        'totals_by_currency': {},
      },
      'clarifications': [
        _answeredQuestion(
          id: 'keep',
          question: 'Keep unresolved?',
          optionKey: 'keep_unresolved',
          label: 'Keep this unresolved and exclude it',
        ),
        _answeredQuestion(
          id: 'paid',
          question: 'Did they cover it?',
          optionKey: 'paid_by_other',
          label: 'They paid for me — I owe nothing',
        ),
        {
          ..._answeredQuestion(
            id: 'free-text',
            question: 'What happened?',
            optionKey: 'repayment_due',
            label: 'I still owe them',
          ),
          'answer': {'free_text': 'I paid her back yesterday'},
        },
        _answeredQuestion(
          id: 'missing',
          question: 'Missing mapping?',
          optionKey: 'repaid_by_user',
          label: 'Different persisted option',
          persistedOptionKey: 'different_key',
        ),
        {
          ..._answeredQuestion(
            id: 'superseded',
            question: 'Superseded question',
            optionKey: 'keep_unresolved',
            label: 'Keep this unresolved and exclude it',
          ),
          'status': 'superseded',
          'answer': null,
        },
      ],
    });

Map<String, dynamic> _answeredQuestion({
  required String id,
  required String question,
  required String optionKey,
  required String label,
  String? persistedOptionKey,
}) =>
    {
      'id': id,
      'sequence': 1,
      'round_number': 1,
      'requirement': 'required',
      'issue_type': 'payer_responsibility',
      'status': 'answered',
      'question': question,
      'reason': 'This changes your expense.',
      'related_event_id': null,
      'related_source_text': 'Mother bought coffee beans',
      'options': [
        {'option_key': persistedOptionKey ?? optionKey, 'label': label}
      ],
      'answer': {'option_key': optionKey},
    };

class _ClarificationApi implements FinPilotApi {
  _ClarificationApi({this.fail = false});
  final bool fail;

  @override
  Future<ClarifyingFinancialDraft> answerClarification({
    required String draftId,
    required int expectedVersion,
    required String questionId,
    String? optionKey,
    String? freeText,
  }) async {
    if (fail) throw const ApiException('Please try again');
    return _state();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
