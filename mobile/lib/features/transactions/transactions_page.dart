import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/finpilot_theme.dart';
import 'transaction_models.dart';
import 'transaction_correction_page.dart';

class TransactionsPage extends StatefulWidget {
  const TransactionsPage({required this.api, super.key});

  final FinPilotApi api;

  @override
  State<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends State<TransactionsPage> {
  static const _pageSize = 20;

  List<RecordedTransaction> _transactions = [];
  RecordedExpenseSummary? _summary;
  int _totalCount = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  String? _moreError;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
      _moreError = null;
    });
    try {
      final page = await widget.api.getTransactions(limit: _pageSize);
      final summary = await widget.api.getTransactionSummary();
      if (!mounted) return;
      setState(() {
        _transactions = page.transactions;
        _totalCount = page.totalCount;
        _summary = summary;
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Unable to load recorded expenses right now.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _transactions.length >= _totalCount) return;
    setState(() {
      _loadingMore = true;
      _moreError = null;
    });
    try {
      final page = await widget.api.getTransactions(
        limit: _pageSize,
        offset: _transactions.length,
      );
      if (!mounted) return;
      setState(() {
        _transactions = [..._transactions, ...page.transactions];
        _totalCount = page.totalCount;
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _moreError = error.message);
    } catch (_) {
      if (mounted) setState(() => _moreError = 'Unable to load more records.');
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Transactions'),
          actions: [
            IconButton(
              tooltip: 'Refresh recorded expenses',
              onPressed: _loading ? null : _reload,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _errorView()
                : RefreshIndicator(
                    onRefresh: _reload,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                          children: [
                            Text('Confirmed expenses',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w800)),
                            const SizedBox(height: 4),
                            const Text(
                                'Only expenses you reviewed and recorded appear here.'),
                            if (_summary != null &&
                                _summary!.totalsByCurrency.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              _summaryCard(),
                            ],
                            const SizedBox(height: 18),
                            if (_transactions.isEmpty)
                              _emptyCard()
                            else ...[
                              Text(
                                  'Showing ${_transactions.length} of $_totalCount'),
                              const SizedBox(height: 8),
                              ..._transactions.map(_transactionCard),
                              if (_moreError != null)
                                Text(_moreError!,
                                    style:
                                        TextStyle(color: Colors.red.shade700)),
                              if (_transactions.length < _totalCount)
                                TextButton(
                                  onPressed: _loadingMore ? null : _loadMore,
                                  child: Text(
                                      _loadingMore ? 'Loading…' : 'Load more'),
                                ),
                            ],
                            const SizedBox(height: 12),
                            const Text(
                                'Tap a record to correct it or review its history.',
                                textAlign: TextAlign.center),
                          ],
                        ),
                      ),
                    ),
                  ),
      );

  Widget _summaryCard() {
    final totals = _summary!.totalsByCurrency.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return Card(
      color: FinPilotColors.mint,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Total recorded spending'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: totals
                  .map((item) => Chip(label: Text('${item.key} ${item.value}')))
                  .toList(),
            ),
            const SizedBox(height: 4),
            const Text('All dates · currencies are kept separate'),
          ],
        ),
      ),
    );
  }

  Widget _transactionCard(RecordedTransaction transaction) {
    final merchant = transaction.merchant?.trim();
    final note = transaction.note?.trim();
    final title = merchant != null && merchant.isNotEmpty
        ? merchant
        : note != null && note.isNotEmpty
            ? note
            : 'Recorded expense';
    return Card(
      key: Key('transaction-${transaction.id}'),
      child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            await Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => TransactionCorrectionPage(
                  api: widget.api, transaction: transaction),
            ));
            if (mounted) _reload();
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text('${transaction.currency} ${transaction.amount}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                    '${transaction.transactionDate} · ${transaction.category}'),
                if (merchant != null &&
                    merchant.isNotEmpty &&
                    note != null &&
                    note.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(note),
                ],
              ],
            ),
          )),
    );
  }

  Widget _emptyCard() => const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(Icons.receipt_long_outlined, size: 36),
              SizedBox(height: 12),
              Text('No recorded expenses yet'),
              SizedBox(height: 6),
              Text(
                'Confirm a reviewed expense in Assistant and it will appear here.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _reload, child: const Text('Try again')),
            ],
          ),
        ),
      );
}
