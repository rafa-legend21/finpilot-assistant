import 'package:finpilot_assistant/core/api_client.dart';
import 'package:finpilot_assistant/features/home/home_page.dart';
import 'package:finpilot_assistant/features/transactions/transaction_models.dart';
import 'package:finpilot_assistant/features/transactions/transactions_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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

  @override
  Future<RecordedTransactionPage> getTransactions({
    int limit = 50,
    int offset = 0,
  }) async {
    if (fail) {
      throw const ApiException('Unable to reach FinPilot. Please try again.');
    }
    lastOffset = offset;
    return offset == 0 ? firstPage : nextPage!;
  }

  @override
  Future<RecordedExpenseSummary> getTransactionSummary() async => summary;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
