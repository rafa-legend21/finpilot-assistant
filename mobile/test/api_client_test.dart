import 'dart:convert';

import 'package:finpilot_assistant/core/api_client.dart';
import 'package:finpilot_assistant/features/financial_review/models/financial_review_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('parse request preserves monetary response values as strings', () async {
    late Map<String, dynamic> requestBody;
    final client = MockClient((request) async {
      requestBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(jsonEncode(_storyResponse()), 200);
    });
    final api = HttpFinPilotApi(client: client, baseUrl: 'http://test');

    final response = await api.parseStory(
      text: 'Dinner was 80 dollars.',
      defaultCurrency: CurrencyCode.CAD,
    );

    expect(requestBody['default_currency'], 'CAD');
    expect(response.toJson()['total_user_expense'], '80.00');
  });

  test('409 response exposes status and backend detail', () async {
    final client =
        MockClient((_) async => http.Response('{"detail":"stale"}', 409));
    final api = HttpFinPilotApi(client: client, baseUrl: 'http://test');

    expect(
      () => api.getDraft('draft-id'),
      throwsA(isA<ApiException>()
          .having((error) => error.statusCode, 'status', 409)),
    );
  });

  test('502 response exposes safe backend detail, not a reachability error',
      () async {
    const detail =
        'FinPilot could not process the journal right now. Please try again.';
    final client = MockClient(
      (request) async {
        expect(request.url.path, '/api/v1/financial-drafts/from-journal');
        return http.Response(jsonEncode({'detail': detail}), 502);
      },
    );
    final api = HttpFinPilotApi(client: client, baseUrl: 'http://test');

    await expectLater(
      api.createDraftFromJournal(
        text: 'I bought coffee beans for 18 CAD.',
        defaultCurrency: CurrencyCode.CAD,
      ),
      throwsA(
        isA<ApiException>()
            .having((error) => error.statusCode, 'status', 502)
            .having((error) => error.message, 'message', detail)
            .having(
              (error) => error.message,
              'reachability classification',
              isNot(contains('Unable to reach FinPilot')),
            ),
      ),
    );
  });

  test('journal request carries the selected reply language', () async {
    late Map<String, dynamic> requestBody;
    final client = MockClient((request) async {
      requestBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response('{"detail":"unavailable"}', 502);
    });
    final api = HttpFinPilotApi(client: client, baseUrl: 'http://test');

    await expectLater(
      api.createDraftFromJournal(
        text: 'Ma mère a payé 18 euros.',
        defaultCurrency: CurrencyCode.EUR,
        responseLanguage: 'fr',
      ),
      throwsA(isA<ApiException>()),
    );

    expect(requestBody['response_language'], 'fr');
    expect(requestBody['text'], 'Ma mère a payé 18 euros.');
  });

  test('transport exception exposes the reachability error', () async {
    final client = MockClient(
      (request) async {
        expect(request.url.path, '/api/v1/financial-drafts/from-journal');
        throw http.ClientException('connection failed');
      },
    );
    final api = HttpFinPilotApi(client: client, baseUrl: 'http://test');

    await expectLater(
      api.createDraftFromJournal(
        text: 'I bought coffee beans for 18 CAD.',
        defaultCurrency: CurrencyCode.CAD,
      ),
      throwsA(
        isA<ApiException>()
            .having((error) => error.statusCode, 'status', isNull)
            .having(
              (error) => error.message,
              'message',
              'Unable to reach FinPilot. Please try again.',
            ),
      ),
    );
  });

  test('event update sends null merchant and exact date without display text',
      () async {
    late Map<String, dynamic> requestBody;
    final client = MockClient((request) async {
      requestBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(jsonEncode(_draftResponse()), 200);
    });
    final api = HttpFinPilotApi(client: client, baseUrl: 'http://test');
    const event = SpendingEvent(
      title: 'Coffee beans',
      category: 'grocery',
      transactionType: 'expense',
      eventDate: '2026-08-08',
      merchant: null,
      payerType: 'user',
      paidByName: null,
      settlementStatus: 'not_applicable',
      userNetAmount: '18.00',
      currency: 'CAD',
      amountMentions: [],
      quantities: [],
      sourceText: 'Coffee beans were 18 CAD',
      confidence: 1,
      needsConfirmation: false,
    );

    await api.updateDraftEvent(
      draftId: 'draft-1',
      eventId: 'event-1',
      expectedVersion: 1,
      disposition: DraftEventDisposition.include,
      event: event,
    );

    final sentEvent = requestBody['event'] as Map<String, dynamic>;
    expect(sentEvent['merchant'], isNull);
    expect(sentEvent['event_date'], '2026-08-08');
    expect(jsonEncode(requestBody), isNot(contains('Unknown merchant')));
  });
}

Map<String, dynamic> _storyResponse() => {
      'summary': 'Dinner',
      'spending_events': [],
      'moods': [],
      'life_events': [],
      'confirmation_questions': [],
      'total_user_expense': '80.00',
      'total_paid_by_others': '0.00',
      'total_saved_decisions': '0.00',
      'parser_confidence': 1.0,
      'draft_only': true,
    };

Map<String, dynamic> _draftResponse() => {
      'id': 'draft-1',
      'status': 'draft',
      'version': 2,
      'summary': 'Coffee beans',
      'confirmation_questions': [],
      'events': [
        {
          'id': 'event-1',
          'position': 0,
          'disposition': 'include',
          'event': {
            'title': 'Coffee beans',
            'category': 'grocery',
            'transaction_type': 'expense',
            'event_date': '2026-08-08',
            'merchant': null,
            'payer_type': 'user',
            'paid_by_name': null,
            'settlement_status': 'not_applicable',
            'user_net_amount': '18.00',
            'currency': 'CAD',
            'amount_mentions': [],
            'quantities': [],
            'source_text': 'Coffee beans were 18 CAD',
            'confidence': 1.0,
            'needs_confirmation': false,
          },
        },
      ],
      'totals_by_currency': {'CAD': '18.00'},
    };
