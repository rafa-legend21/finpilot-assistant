class RecordedTransaction {
  const RecordedTransaction({
    required this.id,
    required this.amount,
    required this.currency,
    required this.category,
    required this.transactionDate,
    this.merchant,
    this.note,
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
      );

  final int id;
  final String amount;
  final String currency;
  final String category;
  final String transactionDate;
  final String? merchant;
  final String? note;
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
  const RecordedExpenseSummary(this.totalsByCurrency);

  factory RecordedExpenseSummary.fromJson(Map<String, dynamic> json) =>
      RecordedExpenseSummary(
        (json['totals_by_currency'] as Map<String, dynamic>).map(
          (currency, amount) => MapEntry(currency, amount.toString()),
        ),
      );

  final Map<String, String> totalsByCurrency;
}
