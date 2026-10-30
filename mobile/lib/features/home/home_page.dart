import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../financial_review/journal_entry_page.dart';
import '../transactions/transactions_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({this.api, super.key});

  final FinPilotApi? api;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FinPilot Assistant'),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            onPressed: () {},
            icon: const Icon(Icons.notifications_none_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: const [
          Text('August overview', style: TextStyle(fontSize: 16)),
          SizedBox(height: 12),
          _SummaryCard(),
          SizedBox(height: 24),
          Text(
            'Budget categories',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 12),
          _BudgetRow(label: 'Grocery', spent: 312, budget: 450),
          _BudgetRow(label: 'Dining', spent: 148, budget: 250),
          _BudgetRow(label: 'Transportation', spent: 86, budget: 180),
          _BudgetRow(label: 'Entertainment', spent: 52, budget: 120),
          SizedBox(height: 24),
          Text(
            'Next pay allocation',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 12),
          _AllocationCard(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        onDestinationSelected: (index) {
          if (index == 1) {
            Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => TransactionsPage(api: api ?? HttpFinPilotApi()),
            ));
          } else if (index == 3) {
            Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => JournalEntryPage(api: api ?? HttpFinPilotApi()),
            ));
          }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined), label: 'Transactions'),
          NavigationDestination(
              icon: Icon(Icons.pie_chart_outline), label: 'Budget'),
          NavigationDestination(
              icon: Icon(Icons.auto_awesome_outlined), label: 'Assistant'),
          NavigationDestination(
              icon: Icon(Icons.settings_outlined), label: 'Settings'),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Available this month'),
            SizedBox(height: 6),
            Text('\$1,284.60',
                style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800)),
            SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _Metric(label: 'Spent', value: '\$598.00'),
                _Metric(label: 'Investing', value: '\$500.00'),
                _Metric(label: 'Next pay', value: '12 days'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _BudgetRow extends StatelessWidget {
  const _BudgetRow(
      {required this.label, required this.spent, required this.budget});
  final String label;
  final double spent;
  final double budget;

  @override
  Widget build(BuildContext context) {
    final progress = (spent / budget).clamp(0.0, 1.0);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                    '\$${spent.toStringAsFixed(0)} / \$${budget.toStringAsFixed(0)}'),
              ],
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(value: progress),
          ],
        ),
      ),
    );
  }
}

class _AllocationCard extends StatelessWidget {
  const _AllocationCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(18),
        child: Column(
          children: [
            _AllocationRow(label: 'Fixed expenses', value: '\$825'),
            _AllocationRow(label: 'Investment', value: '\$500'),
            _AllocationRow(label: 'Essential spending', value: '\$475'),
            Divider(),
            _AllocationRow(
                label: 'Flexible spending', value: '\$400', emphasized: true),
          ],
        ),
      ),
    );
  }
}

class _AllocationRow extends StatelessWidget {
  const _AllocationRow(
      {required this.label, required this.value, this.emphasized = false});
  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: emphasized
                  ? const TextStyle(fontWeight: FontWeight.w700)
                  : null),
          Text(value,
              style: TextStyle(
                  fontWeight: emphasized ? FontWeight.w800 : FontWeight.w600)),
        ],
      ),
    );
  }
}
