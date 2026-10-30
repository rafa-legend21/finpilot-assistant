import 'package:finpilot_assistant/core/api_client.dart';
import 'package:finpilot_assistant/features/home/home_page.dart';
import 'package:finpilot_assistant/features/transactions/transaction_models.dart';
import 'package:finpilot_assistant/features/transactions/transactions_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Home shows confirmed category and date totals by currency',
      (tester) async {
    final api = _FakeApi(
      firstPage: const RecordedTransactionPage(transactions: [], totalCount: 0),
      summary: const RecordedExpenseSummary(
        {'CAD': '80.00', 'USD': '25.00'},
        byCategory: [
          RecordedCategoryTotal('dining', 'CAD', '80.00'),
          RecordedCategoryTotal('grocery', 'USD', '25.00'),
        ],
        byDate: [RecordedDailyTotal('2026-10-30', 'CAD', '80.00')],
      ),
    );
    await tester.pumpWidget(MaterialApp(home: HomePage(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('Confirmed spending'), findsOneWidget);
    expect(find.text('By category'), findsNWidgets(2));
    expect(find.text('dining'), findsOneWidget);
    expect(find.text('grocery'), findsOneWidget);
    expect(find.textContaining('No bank feed connected'), findsOneWidget);
  });

  testWidgets(
      'Transactions navigation shows recorded entries and separate currencies',
      (tester) async {
    final api = _FakeApi(
      firstPage: const RecordedTransactionPage(
        transactions: [
          RecordedTransaction(
            id: 1,
            amount: '80.00',
            currency: 'CAD',
            category: 'dining',
            transactionDate: '2026-10-30',
            merchant: 'Cafe',
          ),
          RecordedTransaction(
            id: 2,
            amount: '25.00',
            currency: 'USD',
            category: 'grocery',
            transactionDate: '2026-10-29',
            note: 'Coffee beans',
          ),
        ],
        totalCount: 2,
      ),
      summary: const RecordedExpenseSummary(
        {'CAD': '80.00', 'USD': '25.00'},
      ),
    );
    await tester.pumpWidget(MaterialApp(home: HomePage(api: api)));

    await tester.tap(find.text('Transactions'));
    await tester.pumpAndSettle();

    expect(find.text('Confirmed expenses'), findsOneWidget);
    expect(find.text('CAD 80.00'), findsNWidgets(2));
    expect(find.text('USD 25.00'), findsNWidgets(2));
    expect(find.text('Cafe'), findsOneWidget);
    expect(find.text('Coffee beans'), findsOneWidget);
    expect(find.text('Showing 2 of 2'), findsOneWidget);
  });

  testWidgets('empty ledger has a calm next step', (tester) async {
    final api = _FakeApi(
      firstPage: const RecordedTransactionPage(transactions: [], totalCount: 0),
      summary: const RecordedExpenseSummary({}),
    );
    await tester.pumpWidget(MaterialApp(home: TransactionsPage(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('No recorded expenses yet'), findsOneWidget);
    expect(find.textContaining('Confirm a reviewed expense'), findsOneWidget);
    expect(find.text('Total recorded spending'), findsNothing);
  });

  testWidgets('a corrected amount retains a reason and refreshes the list',
      (tester) async {
    final api = _FakeApi(
      firstPage: const RecordedTransactionPage(transactions: [
        RecordedTransaction(
            id: 7,
            amount: '18.00',
            currency: 'CAD',
            category: 'dining',
            transactionDate: '2026-10-30',
            merchant: 'Cafe'),
      ], totalCount: 1),
      summary: const RecordedExpenseSummary({'CAD': '18.00'}),
    );
    await tester.pumpWidget(MaterialApp(home: TransactionsPage(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('transaction-7')));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Amount'), '12.50');
    await tester.scrollUntilVisible(
        find.text('Why are you changing this?'), 240,
        scrollable: find.byType(Scrollable).first);
    await tester.enterText(
        find.widgetWithText(TextField, 'Why are you changing this?'),
        'Receipt shows a lower total');
    await tester.ensureVisible(find.text('Save correction'));
    await tester.tap(find.text('Save correction'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(api.edited?.amount, '12.50');
    expect(api.lastReason, 'Receipt shows a lower total');
    expect(find.text('Change history'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('CAD 12.50'), findsOneWidget);
  });

  testWidgets('load more appends the next page', (tester) async {
    final api = _FakeApi(
      firstPage: const RecordedTransactionPage(
        transactions: [
          RecordedTransaction(
            id: 1,
            amount: '10.00',
            currency: 'CAD',
            category: 'dining',
            transactionDate: '2026-10-30',
          ),
        ],
        totalCount: 2,
      ),
      nextPage: const RecordedTransactionPage(
        transactions: [
          RecordedTransaction(
            id: 2,
            amount: '20.00',
            currency: 'CAD',
            category: 'grocery',
            transactionDate: '2026-10-29',
          ),
        ],
        totalCount: 2,
      ),
      summary: const RecordedExpenseSummary({'CAD': '30.00'}),
    );
    await tester.pumpWidget(MaterialApp(home: TransactionsPage(api: api)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();

    expect(api.lastOffset, 1);
    expect(find.byKey(const Key('transaction-2')), findsOneWidget);
    expect(find.text('Showing 2 of 2'), findsOneWidget);
    expect(find.text('Load more'), findsNothing);
  });

  testWidgets('load failure offers retry', (tester) async {
    final api = _FakeApi(
      firstPage: const RecordedTransactionPage(transactions: [], totalCount: 0),
      summary: const RecordedExpenseSummary({}),
    )..fail = true;
    await tester.pumpWidget(MaterialApp(home: TransactionsPage(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('Unable to reach FinPilot. Please try again.'),
        findsOneWidget);
    api.fail = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.text('No recorded expenses yet'), findsOneWidget);
  });
}

class _FakeApi implements FinPilotApi {
  _FakeApi({required this.firstPage, required this.summary, this.nextPage});

  final RecordedTransactionPage firstPage;
  final RecordedTransactionPage? nextPage;
  final RecordedExpenseSummary summary;
  bool fail = false;
  int? lastOffset;
  RecordedTransaction? edited;
  String? lastReason;

  @override
  Future<RecordedTransactionPage> getTransactions({
    int limit = 50,
    int offset = 0,
  }) async {
    if (fail) {
      throw const ApiException('Unable to reach FinPilot. Please try again.');
    }
    lastOffset = offset;
    if (offset == 0 && edited != null) {
      return RecordedTransactionPage(transactions: [edited!], totalCount: 1);
    }
    return offset == 0 ? firstPage : nextPage!;
  }

  @override
  Future<RecordedExpenseSummary> getTransactionSummary() async => summary;

  @override
  Future<List<RecordedCorrection>> getTransactionHistory(
          int transactionId) async =>
      [];

  @override
  Future<RecordedTransaction> editTransaction({
    required RecordedTransaction transaction,
    required String reason,
    required String amount,
    required String currency,
    required String category,
    required String transactionDate,
    String? merchant,
    String? note,
  }) async {
    lastReason = reason;
    edited = RecordedTransaction(
        id: transaction.id,
        amount: amount,
        currency: currency,
        category: category,
        transactionDate: transactionDate,
        merchant: merchant,
        note: note,
        version: transaction.version + 1);
    return edited!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
