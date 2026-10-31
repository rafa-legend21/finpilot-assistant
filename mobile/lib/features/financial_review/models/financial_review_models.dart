enum CurrencyCode { CAD, USD, CNY, GBP, EUR, UNKNOWN }

enum DraftStatus { draft, confirmed, cancelled }

enum DraftEventDisposition { pending, include, exclude }

const expenseCategories = <String>[
  'grocery',
  'dining',
  'transportation',
  'shopping',
  'entertainment',
  'housing',
  'utilities',
  'healthcare',
  'travel',
  'education',
  'subscription',
  'investment',
  'transfer',
  'income',
  'other',
];

String _money(Object? value) => value?.toString() ?? '0';

class AmountMention {
  const AmountMention({
    required this.amount,
    required this.currency,
    required this.role,
    required this.countedInUserTotal,
    required this.sourceText,
    required this.confidence,
    required this.explanation,
  });

  factory AmountMention.fromJson(Map<String, dynamic> json) => AmountMention(
        amount: _money(json['amount']),
        currency: json['currency'] as String? ?? 'CAD',
        role: json['role'] as String,
        countedInUserTotal: json['counted_in_user_total'] as bool,
        sourceText: json['source_text'] as String,
        confidence: (json['confidence'] as num).toDouble(),
        explanation: json['explanation'] as String,
      );

  final String amount;
  final String currency;
  final String role;
  final bool countedInUserTotal;
  final String sourceText;
  final double confidence;
  final String explanation;

  Map<String, dynamic> toJson() => {
        'amount': amount,
        'currency': currency,
        'role': role,
        'counted_in_user_total': countedInUserTotal,
        'source_text': sourceText,
        'confidence': confidence,
        'explanation': explanation,
      };
}

class SpendingEvent {
  const SpendingEvent({
    required this.title,
    required this.category,
    required this.transactionType,
    required this.eventDate,
    required this.merchant,
    required this.payerType,
    required this.paidByName,
    required this.settlementStatus,
    required this.userNetAmount,
    required this.currency,
    required this.amountMentions,
    required this.quantities,
    required this.sourceText,
    required this.confidence,
    required this.needsConfirmation,
  });

  factory SpendingEvent.fromJson(Map<String, dynamic> json) => SpendingEvent(
        title: json['title'] as String,
        category: json['category'] as String,
        transactionType: json['transaction_type'] as String? ?? 'expense',
        eventDate: json['event_date'] as String?,
        merchant: json['merchant'] as String?,
        payerType: json['payer_type'] as String? ?? 'unknown',
        paidByName: json['paid_by_name'] as String?,
        settlementStatus:
            json['settlement_status'] as String? ?? 'not_applicable',
        userNetAmount: _money(json['user_net_amount']),
        currency: json['currency'] as String? ?? 'CAD',
        amountMentions: (json['amount_mentions'] as List<dynamic>? ?? [])
            .map((item) => AmountMention.fromJson(item as Map<String, dynamic>))
            .toList(),
        quantities: (json['quantities'] as List<dynamic>? ?? [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList(),
        sourceText: json['source_text'] as String,
        confidence: (json['confidence'] as num).toDouble(),
        needsConfirmation: json['needs_confirmation'] as bool? ?? false,
      );

  final String title;
  final String category;
  final String transactionType;
  final String? eventDate;
  final String? merchant;
  final String payerType;
  final String? paidByName;
  final String settlementStatus;
  final String userNetAmount;
  final String currency;
  final List<AmountMention> amountMentions;
  final List<Map<String, dynamic>> quantities;
  final String sourceText;
  final double confidence;
  final bool needsConfirmation;

  bool get isAvoidedPurchase =>
      transactionType == 'expense' &&
      num.tryParse(userNetAmount) == 0 &&
      amountMentions.any((mention) => mention.role == 'saved_decision') &&
      amountMentions.every((mention) => !mention.countedInUserTotal);

  SpendingEvent withEventDate(String eventDate) => SpendingEvent(
        title: title,
        category: category,
        transactionType: transactionType,
        eventDate: eventDate,
        merchant: merchant,
        payerType: payerType,
        paidByName: paidByName,
        settlementStatus: settlementStatus,
        userNetAmount: userNetAmount,
        currency: currency,
        amountMentions: amountMentions,
        quantities: quantities,
        sourceText: sourceText,
        confidence: confidence,
        needsConfirmation: needsConfirmation,
      );

  SpendingEvent edited({
    required String amount,
    required String category,
    required String payerType,
    required String? merchant,
    required String? eventDate,
  }) {
    final userBearsCost = payerType == 'user' ||
        payerType == 'shared' ||
        (payerType == 'other_person' && settlementStatus == 'repaid_by_user');
    final canonicalAmount = userBearsCost ? amount : '0';
    final mentions = amountMentions
        .map((mention) => AmountMention(
              amount: mention.amount,
              currency: mention.currency,
              role: mention.role,
              countedInUserTotal: false,
              sourceText: mention.sourceText,
              confidence: mention.confidence,
              explanation: mention.explanation,
            ))
        .toList();
    if (userBearsCost) {
      mentions.add(AmountMention(
        amount: canonicalAmount,
        currency: currency,
        role: 'user_net_expense',
        countedInUserTotal: true,
        sourceText: sourceText,
        confidence: 1,
        explanation: 'Amount confirmed by the user.',
      ));
    }
    return SpendingEvent(
      title: title,
      category: category,
      transactionType: transactionType,
      eventDate: eventDate,
      merchant: merchant,
      payerType: payerType,
      paidByName: paidByName,
      settlementStatus:
          payerType == 'other_person' ? settlementStatus : 'not_applicable',
      userNetAmount: canonicalAmount,
      currency: currency,
      amountMentions: mentions,
      quantities: quantities,
      sourceText: sourceText,
      confidence: confidence,
      needsConfirmation: needsConfirmation,
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'category': category,
        'transaction_type': transactionType,
        'event_date': eventDate,
        'merchant': merchant,
        'payer_type': payerType,
        'paid_by_name': paidByName,
        'settlement_status': settlementStatus,
        'user_net_amount': userNetAmount,
        'currency': currency,
        'amount_mentions': amountMentions.map((item) => item.toJson()).toList(),
        'quantities': quantities,
        'source_text': sourceText,
        'confidence': confidence,
        'needs_confirmation': needsConfirmation,
      };
}

class StoryParseResponse {
  const StoryParseResponse(this.json);

  factory StoryParseResponse.fromJson(Map<String, dynamic> json) =>
      StoryParseResponse(Map<String, dynamic>.from(json));

  final Map<String, dynamic> json;
  List<SpendingEvent> get events =>
      (json['spending_events'] as List<dynamic>? ?? [])
          .map((item) => SpendingEvent.fromJson(item as Map<String, dynamic>))
          .toList();
  Map<String, dynamic> toJson() => json;
}

class FinancialDraftEvent {
  const FinancialDraftEvent({
    required this.id,
    required this.position,
    required this.disposition,
    required this.event,
  });

  factory FinancialDraftEvent.fromJson(Map<String, dynamic> json) =>
      FinancialDraftEvent(
        id: json['id'] as String,
        position: json['position'] as int,
        disposition:
            DraftEventDisposition.values.byName(json['disposition'] as String),
        event: SpendingEvent.fromJson(json['event'] as Map<String, dynamic>),
      );

  final String id;
  final int position;
  final DraftEventDisposition disposition;
  final SpendingEvent event;
}

class FinancialDraft {
  const FinancialDraft({
    required this.id,
    required this.status,
    required this.version,
    required this.summary,
    required this.confirmationQuestions,
    required this.events,
    required this.totalsByCurrency,
  });

  factory FinancialDraft.fromJson(Map<String, dynamic> json) => FinancialDraft(
        id: json['id'] as String,
        status: DraftStatus.values.byName(json['status'] as String),
        version: json['version'] as int,
        summary: json['summary'] as String,
        confirmationQuestions:
            (json['confirmation_questions'] as List<dynamic>? ?? [])
                .map((item) => Map<String, dynamic>.from(item as Map))
                .toList(),
        events: (json['events'] as List<dynamic>? ?? [])
            .map((item) =>
                FinancialDraftEvent.fromJson(item as Map<String, dynamic>))
            .toList(),
        totalsByCurrency: Map<String, dynamic>.from(
          json['totals_by_currency'] as Map? ?? const {},
        ).map((key, value) => MapEntry(key, _money(value))),
      );

  final String id;
  final DraftStatus status;
  final int version;
  final String summary;
  final List<Map<String, dynamic>> confirmationQuestions;
  final List<FinancialDraftEvent> events;
  final Map<String, String> totalsByCurrency;
}

class FinancialDraftConfirmation {
  const FinancialDraftConfirmation(
      {required this.draft, required this.transactionIds});

  factory FinancialDraftConfirmation.fromJson(Map<String, dynamic> json) =>
      FinancialDraftConfirmation(
        draft: FinancialDraft.fromJson(json['draft'] as Map<String, dynamic>),
        transactionIds: (json['transaction_ids'] as List<dynamic>).cast<int>(),
      );

  final FinancialDraft draft;
  final List<int> transactionIds;
}

class ClarificationOption {
  const ClarificationOption({required this.optionKey, required this.label});

  factory ClarificationOption.fromJson(Map<String, dynamic> json) =>
      ClarificationOption(
        optionKey: json['option_key'] as String,
        label: json['label'] as String,
      );

  final String optionKey;
  final String label;
}

class DraftClarification {
  const DraftClarification({
    required this.id,
    required this.sequence,
    required this.roundNumber,
    required this.requirement,
    required this.status,
    required this.question,
    required this.reason,
    required this.options,
    required this.answer,
  });

  factory DraftClarification.fromJson(Map<String, dynamic> json) =>
      DraftClarification(
        id: json['id'] as String,
        sequence: json['sequence'] as int,
        roundNumber: json['round_number'] as int,
        requirement: json['requirement'] as String,
        status: json['status'] as String,
        question: json['question'] as String,
        reason: json['reason'] as String,
        options: (json['options'] as List<dynamic>)
            .map((item) =>
                ClarificationOption.fromJson(item as Map<String, dynamic>))
            .toList(),
        answer: json['answer'] == null
            ? null
            : Map<String, dynamic>.from(json['answer'] as Map),
      );

  final String id;
  final int sequence;
  final int roundNumber;
  final String requirement;
  final String status;
  final String question;
  final String reason;
  final List<ClarificationOption> options;
  final Map<String, dynamic>? answer;
}

class ClarifyingFinancialDraft {
  const ClarifyingFinancialDraft({
    required this.draft,
    required this.clarificationState,
    required this.clarifications,
  });

  factory ClarifyingFinancialDraft.fromJson(Map<String, dynamic> json) =>
      ClarifyingFinancialDraft(
        draft: FinancialDraft.fromJson(json['draft'] as Map<String, dynamic>),
        clarificationState: json['clarification_state'] as String,
        clarifications: (json['clarifications'] as List<dynamic>)
            .map((item) =>
                DraftClarification.fromJson(item as Map<String, dynamic>))
            .toList(),
      );

  final FinancialDraft draft;
  final String clarificationState;
  final List<DraftClarification> clarifications;
}
