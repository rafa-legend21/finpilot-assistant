import 'dart:async';
import 'dart:convert';

import 'package:finpilot_assistant/core/api_client.dart';
import 'package:finpilot_assistant/features/financial_review/models/financial_review_models.dart';
import 'package:finpilot_assistant/features/transactions/transaction_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('transaction queries preserve amounts and use read-only endpoints',
      () async {
    final paths = <String>[];
    final client = MockClient((request) async {
      paths.add(request.url.toString());
      expect(request.method, 'GET');
      if (request.url.path.endsWith('/summary')) {
        return http.Response(
            jsonEncode({
              'totals_by_currency': {'CAD': '80.00', 'USD': '25.00'},
              'by_date': [],
              'by_category': [],
            }),
            200);
      }
      return http.Response(
          jsonEncode({
            'transactions': [
              {
                'id': 7,
                'merchant': null,
                'amount': '80.00',
                'currency': 'CAD',
                'category': 'dining',
                'transaction_date': '2026-10-30',
                'note': 'Dinner',
              }
            ],
            'total_count': 1,
          }),
          200);
    });
    final api = HttpFinPilotApi(client: client, baseUrl: 'http://test');

    final page = await api.getTransactions(limit: 20, offset: 40);
    final summary = await api.getTransactionSummary();

    expect(paths, [
      'http://test/api/v1/transactions?limit=20&offset=40',
      'http://test/api/v1/transactions/summary',
    ]);
    expect(page.totalCount, 1);
    expect(page.transactions.single.amount, '80.00');
    expect(page.transactions.single.merchant, isNull);
    expect(summary.totalsByCurrency, {'CAD': '80.00', 'USD': '25.00'});
  });

  test('corrections send the expected version and preserve monetary strings',
      () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.url.path.endsWith('/corrections')) {
        return http.Response(
            jsonEncode([
              {
                'action': 'edit',
                'reason': 'Receipt corrected',
                'before_state': {'amount': '18.00'},
                'after_state': {'amount': '12.50'},
                'created_at': '2026-10-30T12:00:00Z',
              }
            ]),
            200);
      }
      return http.Response(
          jsonEncode({
            'id': 7,
            'version': 2,
            'amount': '12.50',
            'currency': 'CAD',
            'category': 'grocery',
            'transaction_date': '2026-10-30',
            'merchant': null,
            'note': null,
            'voided_at': null,
          }),
          200);
    });
    final api = HttpFinPilotApi(client: client, baseUrl: 'http://test');
    const original = RecordedTransaction(
        id: 7,
        amount: '18.00',
        currency: 'CAD',
        category: 'dining',
        transactionDate: '2026-10-29');

    final edited = await api.editTransaction(
        transaction: original,
        reason: 'Receipt corrected',
        amount: '12.50',
        currency: 'CAD',
        category: 'grocery',
        transactionDate: '2026-10-30');
    final history = await api.getTransactionHistory(7);
    await api.voidTransaction(transaction: edited, reason: 'Paid by friend');

    expect(requests.map((request) => request.method).toList(),
        ['PATCH', 'GET', 'POST']);
    expect(jsonDecode(requests[0].body), containsPair('expected_version', 1));
    expect(jsonDecode(requests[0].body), containsPair('amount', '12.50'));
    expect(history.single.beforeState['amount'], '18.00');
    expect(jsonDecode(requests[2].body), containsPair('expected_version', 2));
  });

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

  test('a stalled request reports a timeout instead of loading forever',
      () async {
    final stalled = Completer<http.Response>();
    final api = HttpFinPilotApi(
      client: MockClient((_) => stalled.future),
      baseUrl: 'http://test',
      requestTimeout: const Duration(milliseconds: 10),
    );

    await expectLater(
      api.createDraftFromJournal(
        text: 'I paid 5 CAD for coffee.',
        defaultCurrency: CurrencyCode.CAD,
      ),
      throwsA(isA<ApiException>().having(
        (error) => error.message,
        'message',
        contains('too long to respond'),
      )),
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
