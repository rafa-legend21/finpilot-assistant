import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../financial_review/iso_date_input_formatter.dart';
import '../financial_review/models/financial_review_models.dart';
import 'transaction_models.dart';

class TransactionCorrectionPage extends StatefulWidget {
  const TransactionCorrectionPage(
      {required this.api, required this.transaction, super.key});

  final FinPilotApi api;
  final RecordedTransaction transaction;

  @override
  State<TransactionCorrectionPage> createState() =>
      _TransactionCorrectionPageState();
}

class _TransactionCorrectionPageState extends State<TransactionCorrectionPage> {
  late RecordedTransaction _transaction;
  late final TextEditingController _amount;
  late final TextEditingController _date;
  late final TextEditingController _merchant;
  late final TextEditingController _note;
  late final TextEditingController _reason;
  late String _currency;
  late String _category;
  List<RecordedCorrection> _history = [];
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _transaction = widget.transaction;
    _amount = TextEditingController(text: _transaction.amount);
    _date = TextEditingController(text: _transaction.transactionDate);
    _merchant = TextEditingController(text: _transaction.merchant ?? '');
    _note = TextEditingController(text: _transaction.note ?? '');
    _reason = TextEditingController();
    _currency = _transaction.currency;
    _category = _transaction.category;
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final history = await widget.api.getTransactionHistory(_transaction.id);
      if (mounted) {
        setState(() => _history = history);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not load correction history.');
      }
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _date.dispose();
    _merchant.dispose();
    _note.dispose();
    _reason.dispose();
    super.dispose();
  }

  String? _validate({required bool voiding}) {
    if (_reason.text.trim().length < 3) {
      return 'Please explain the correction in at least 3 characters.';
    }
    if (voiding) return null;
    final amount = double.tryParse(_amount.text.trim());
    if (amount == null ||
        amount <= 0 ||
        !RegExp(r'^\d{1,10}(\.\d{1,2})?$').hasMatch(_amount.text.trim())) {
      return 'Enter a positive amount with no more than 2 decimal places.';
    }
    final date = _date.text.trim();
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
        DateTime.tryParse(date)?.toIso8601String().substring(0, 10) != date) {
      return 'Enter a real date in YYYY-MM-DD format.';
    }
    return null;
  }

  Future<void> _submit({required bool voiding}) async {
    final error = _validate(voiding: voiding);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(voiding ? 'Remove from spending?' : 'Save correction?'),
        content: Text(voiding
            ? 'This record stays in the history, but no longer counts toward spending totals.'
            : 'The updated record will replace this amount in your spending totals. The previous values stay in the history.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(voiding ? 'Remove' : 'Save')),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final updated = voiding
          ? await widget.api.voidTransaction(
              transaction: _transaction, reason: _reason.text.trim())
          : await widget.api.editTransaction(
              transaction: _transaction,
              reason: _reason.text.trim(),
              amount: _amount.text.trim(),
              currency: _currency,
              category: _category,
              transactionDate: _date.text.trim(),
              merchant: _merchant.text.trim(),
              note: _note.text.trim(),
            );
      if (!mounted) return;
      setState(() {
        _transaction = updated;
        _reason.clear();
      });
      await _loadHistory();
      if (!mounted) return;
      if (voiding) Navigator.pop(context, true);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
            () => _error = 'Could not save this correction. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Correct a record')),
        body: Center(
            child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 650),
          child: ListView(padding: const EdgeInsets.all(20), children: [
            const Text(
                'Changes are saved with a reason and previous values. Check who actually paid before changing a total.'),
            const SizedBox(height: 16),
            TextField(
                controller: _amount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Amount')),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
                initialValue: _currency,
                decoration: const InputDecoration(labelText: 'Currency'),
                items: const ['CAD', 'USD', 'CNY', 'GBP', 'EUR']
                    .map((value) =>
                        DropdownMenuItem(value: value, child: Text(value)))
                    .toList(),
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _currency = value!)),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: expenseCategories
                    .where((value) =>
                        value == _category ||
                        !{'income', 'transfer', 'investment'}.contains(value))
                    .map((value) =>
                        DropdownMenuItem(value: value, child: Text(value)))
                    .toList(),
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _category = value!)),
            const SizedBox(height: 12),
            TextField(
                controller: _date,
                inputFormatters: const [IsoDateInputFormatter()],
                keyboardType: TextInputType.datetime,
                decoration:
                    const InputDecoration(labelText: 'Date (YYYY-MM-DD)')),
            const SizedBox(height: 12),
            TextField(
                controller: _merchant,
                maxLength: 150,
                decoration:
                    const InputDecoration(labelText: 'Merchant (optional)')),
            const SizedBox(height: 12),
            TextField(
                controller: _note,
                maxLength: 500,
                decoration:
                    const InputDecoration(labelText: 'Note (optional)')),
            const SizedBox(height: 12),
            TextField(
                controller: _reason,
                maxLength: 500,
                decoration: const InputDecoration(
                    labelText: 'Why are you changing this?',
                    hintText: 'For example: receipt says 12.50, not 18.00')),
            if (_error != null)
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error))),
            FilledButton(
                onPressed: _busy || _transaction.voidedAt != null
                    ? null
                    : () => _submit(voiding: false),
                child: Text(_busy ? 'Saving…' : 'Save correction')),
            const SizedBox(height: 8),
            OutlinedButton(
                onPressed: _busy || _transaction.voidedAt != null
                    ? null
                    : () => _submit(voiding: true),
                child: const Text('Remove from spending')),
            const SizedBox(height: 24),
            Text('Change history',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (_history.isEmpty) const Text('No corrections yet.'),
            ..._history.map((item) => Card(
                    child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            '${item.action == 'void' ? 'Removed' : 'Corrected'} · ${item.createdAt.substring(0, 10)}',
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        Text(item.reason),
                        Text(
                            'Before: ${item.beforeState['currency']} ${item.beforeState['amount']} · ${item.beforeState['category']} · ${item.beforeState['transaction_date']}'),
                        Text(
                            'After: ${item.afterState['currency']} ${item.afterState['amount']} · ${item.afterState['category']} · ${item.afterState['transaction_date']}'),
                      ]),
                ))),
          ]),
        )),
      );
}
