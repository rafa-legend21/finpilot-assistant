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
    final client = MockClient((_) async => http.Response('{"detail":"stale"}', 409));
    final api = HttpFinPilotApi(client: client, baseUrl: 'http://test');

    expect(
      () => api.getDraft('draft-id'),
      throwsA(isA<ApiException>().having((error) => error.statusCode, 'status', 409)),
    );
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
