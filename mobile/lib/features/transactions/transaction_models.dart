class RecordedTransaction {
  const RecordedTransaction({
    required this.id,
    required this.amount,
    required this.currency,
    required this.category,
    required this.transactionDate,
    this.merchant,
    this.note,
    this.version = 1,
    this.voidedAt,
  });

  factory RecordedTransaction.fromJson(Map<String, dynamic> json) =>
      RecordedTransaction(
        id: (json['id'] as num).toInt(),
        amount: json['amount'].toString(),
        currency: json['currency'] as String,
        category: json['category'] as String,
        transactionDate: json['transaction_date'] as String,
        merchant: json['merchant'] as String?,
        note: json['note'] as String?,
        version: (json['version'] as num?)?.toInt() ?? 1,
        voidedAt: json['voided_at'] as String?,
      );

  final int id;
  final String amount;
  final String currency;
  final String category;
  final String transactionDate;
  final String? merchant;
  final String? note;
  final int version;
  final String? voidedAt;
}

class RecordedTransactionPage {
  const RecordedTransactionPage({
    required this.transactions,
    required this.totalCount,
  });

  factory RecordedTransactionPage.fromJson(Map<String, dynamic> json) =>
      RecordedTransactionPage(
        transactions: (json['transactions'] as List<dynamic>)
            .map((item) =>
                RecordedTransaction.fromJson(item as Map<String, dynamic>))
            .toList(),
        totalCount: (json['total_count'] as num).toInt(),
      );

  final List<RecordedTransaction> transactions;
  final int totalCount;
}

class RecordedExpenseSummary {
  const RecordedExpenseSummary(this.totalsByCurrency,
      {this.byDate = const [], this.byCategory = const []});

  factory RecordedExpenseSummary.fromJson(Map<String, dynamic> json) =>
      RecordedExpenseSummary(
        (json['totals_by_currency'] as Map<String, dynamic>).map(
          (currency, amount) => MapEntry(currency, amount.toString()),
        ),
        byDate: (json['by_date'] as List<dynamic>? ?? [])
            .map((item) =>
                RecordedDailyTotal.fromJson(item as Map<String, dynamic>))
            .toList(),
        byCategory: (json['by_category'] as List<dynamic>? ?? [])
            .map((item) =>
                RecordedCategoryTotal.fromJson(item as Map<String, dynamic>))
            .toList(),
      );

  final Map<String, String> totalsByCurrency;
  final List<RecordedDailyTotal> byDate;
  final List<RecordedCategoryTotal> byCategory;
}

class RecordedDailyTotal {
  const RecordedDailyTotal(this.date, this.currency, this.amount);
  factory RecordedDailyTotal.fromJson(Map<String, dynamic> json) =>
      RecordedDailyTotal(json['date'] as String, json['currency'] as String,
          json['amount'].toString());
  final String date;
  final String currency;
  final String amount;
}

class RecordedCategoryTotal {
  const RecordedCategoryTotal(this.category, this.currency, this.amount);
  factory RecordedCategoryTotal.fromJson(Map<String, dynamic> json) =>
      RecordedCategoryTotal(json['category'] as String,
          json['currency'] as String, json['amount'].toString());
  final String category;
  final String currency;
  final String amount;
}

class RecordedCorrection {
  const RecordedCorrection(
      {required this.action,
      required this.reason,
      required this.beforeState,
      required this.afterState,
      required this.createdAt});
  factory RecordedCorrection.fromJson(Map<String, dynamic> json) =>
      RecordedCorrection(
        action: json['action'] as String,
        reason: json['reason'] as String,
        beforeState: Map<String, dynamic>.from(json['before_state'] as Map),
        afterState: Map<String, dynamic>.from(json['after_state'] as Map),
        createdAt: json['created_at'] as String,
      );
  final String action;
  final String reason;
  final Map<String, dynamic> beforeState;
  final Map<String, dynamic> afterState;
  final String createdAt;
}
