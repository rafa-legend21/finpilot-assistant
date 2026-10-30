import 'dart:convert';

import 'package:http/http.dart' as http;

import '../features/financial_review/models/financial_review_models.dart';
import 'api_config.dart';

abstract interface class FinPilotApi {
  Future<StoryParseResponse> parseStory({
    required String text,
    required CurrencyCode defaultCurrency,
    DateTime? referenceDate,
  });

  Future<FinancialDraft> createDraft(StoryParseResponse response);
  Future<ClarifyingFinancialDraft> createDraftFromJournal({
    required String text,
    required CurrencyCode defaultCurrency,
    DateTime? referenceDate,
    String? responseLanguage,
  });
  Future<ClarifyingFinancialDraft> getClarifications(String draftId);
  Future<ClarifyingFinancialDraft> answerClarification({
    required String draftId,
    required int expectedVersion,
    required String questionId,
    String? optionKey,
    String? freeText,
  });
  Future<FinancialDraft> getDraft(String draftId);
  Future<FinancialDraft> updateDraftEvent({
    required String draftId,
    required String eventId,
    required int expectedVersion,
    required DraftEventDisposition disposition,
    required SpendingEvent event,
  });
  Future<FinancialDraftConfirmation> confirmDraft({
    required String draftId,
    required int expectedVersion,
  });
  Future<FinancialDraft> cancelDraft({
    required String draftId,
    required int expectedVersion,
  });
}

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

class HttpFinPilotApi implements FinPilotApi {
  HttpFinPilotApi({http.Client? client, String baseUrl = ApiConfig.baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl;

  final http.Client _client;
  final String _baseUrl;

  @override
  Future<StoryParseResponse> parseStory({
    required String text,
    required CurrencyCode defaultCurrency,
    DateTime? referenceDate,
  }) async {
    final payload = <String, dynamic>{
      'text': text,
      'default_currency': defaultCurrency.name,
      if (referenceDate != null) 'reference_date': _date(referenceDate),
    };
    return StoryParseResponse.fromJson(
      await _send('POST', '/api/v1/story-parser/parse', payload),
    );
  }

  @override
  Future<FinancialDraft> createDraft(StoryParseResponse response) async =>
      FinancialDraft.fromJson(await _send(
        'POST',
        '/api/v1/financial-drafts',
        {'story_parse_response': response.toJson()},
      ));

  @override
  Future<ClarifyingFinancialDraft> createDraftFromJournal({
    required String text,
    required CurrencyCode defaultCurrency,
    DateTime? referenceDate,
    String? responseLanguage,
  }) async =>
      ClarifyingFinancialDraft.fromJson(await _send(
        'POST',
        '/api/v1/financial-drafts/from-journal',
        {
          'text': text,
          'default_currency': defaultCurrency.name,
          if (referenceDate != null) 'reference_date': _date(referenceDate),
          if (responseLanguage != null) 'response_language': responseLanguage,
        },
      ));

  @override
  Future<ClarifyingFinancialDraft> getClarifications(String draftId) async =>
      ClarifyingFinancialDraft.fromJson(await _send(
        'GET',
        '/api/v1/financial-drafts/$draftId/clarifications',
      ));

  @override
  Future<ClarifyingFinancialDraft> answerClarification({
    required String draftId,
    required int expectedVersion,
    required String questionId,
    String? optionKey,
    String? freeText,
  }) async =>
      ClarifyingFinancialDraft.fromJson(await _send(
        'POST',
        '/api/v1/financial-drafts/$draftId/clarifications/answers',
        {
          'expected_version': expectedVersion,
          'answers': [
            {
              'question_id': questionId,
              if (optionKey != null) 'option_key': optionKey,
              if (freeText != null) 'free_text': freeText,
            }
          ],
        },
      ));

  @override
  Future<FinancialDraft> getDraft(String draftId) async =>
      FinancialDraft.fromJson(
        await _send('GET', '/api/v1/financial-drafts/$draftId'),
      );

  @override
  Future<FinancialDraft> updateDraftEvent({
    required String draftId,
    required String eventId,
    required int expectedVersion,
    required DraftEventDisposition disposition,
    required SpendingEvent event,
  }) async =>
      FinancialDraft.fromJson(await _send(
        'PATCH',
        '/api/v1/financial-drafts/$draftId/events/$eventId',
        {
          'expected_version': expectedVersion,
          'disposition': disposition.name,
          'event': event.toJson(),
        },
      ));

  @override
  Future<FinancialDraftConfirmation> confirmDraft({
    required String draftId,
    required int expectedVersion,
  }) async =>
      FinancialDraftConfirmation.fromJson(await _send(
        'POST',
        '/api/v1/financial-drafts/$draftId/confirm',
        {'expected_version': expectedVersion},
      ));

  @override
  Future<FinancialDraft> cancelDraft({
    required String draftId,
    required int expectedVersion,
  }) async =>
      FinancialDraft.fromJson(await _send(
        'POST',
        '/api/v1/financial-drafts/$draftId/cancel',
        {'expected_version': expectedVersion},
      ));

  Future<Map<String, dynamic>> _send(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final uri = Uri.parse('$_baseUrl$path');
    final headers = {'Content-Type': 'application/json'};
    late http.Response response;
    try {
      response = switch (method) {
        'GET' => await _client.get(uri, headers: headers),
        'PATCH' =>
          await _client.patch(uri, headers: headers, body: jsonEncode(body)),
        _ => await _client.post(uri, headers: headers, body: jsonEncode(body)),
      };
    } catch (_) {
      throw const ApiException('Unable to reach FinPilot. Please try again.');
    }
    final decoded = jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = decoded is Map<String, dynamic> ? decoded['detail'] : null;
      throw ApiException(
        detail is String ? detail : 'Request failed (${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const ApiException('FinPilot returned an invalid response.');
    }
    return decoded;
  }

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
