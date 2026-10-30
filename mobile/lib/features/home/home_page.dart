import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/finpilot_theme.dart';
import '../financial_review/journal_entry_page.dart';
import '../transactions/transactions_page.dart';
import '../transactions/transaction_models.dart';

class HomePage extends StatefulWidget {
  const HomePage({this.api, super.key});

  final FinPilotApi? api;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final FinPilotApi _api = widget.api ?? HttpFinPilotApi();
  RecordedExpenseSummary? _summary;
  DateTime? _fetchedAt;
  String? _summaryError;

  @override
  void initState() {
    super.initState();
    _refreshSummary();
  }

  Future<void> _refreshSummary() async {
    try {
      final summary = await _api.getTransactionSummary();
      if (mounted) {
        setState(() {
          _summary = summary;
          _fetchedAt = DateTime.now();
          _summaryError = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
            () => _summaryError = 'Could not refresh spending. Tap to retry.');
      }
    }
  }

  Future<void> _openAssistant(BuildContext context) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => JournalEntryPage(api: _api),
    ));
    _refreshSummary();
  }

  Future<void> _openTransactions(BuildContext context) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => TransactionsPage(api: _api),
    ));
    _refreshSummary();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('FinPilot',
            style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.4)),
        leading: const Icon(Icons.auto_awesome_rounded,
            color: FinPilotColors.forest),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
            children: [
              Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF174E43), Color(0xFF2F7662)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.spa_outlined,
                        color: Color(0xFFC9E9D4), size: 32),
                    const SizedBox(height: 18),
                    const Text('Your money, in your hands',
                        style: TextStyle(
                            color: Color(0xFFC9E9D4),
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5)),
                    const SizedBox(height: 8),
                    const Text('Understand the story behind your spending.',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            height: 1.18,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 12),
                    const Text(
                      'Tell FinPilot what happened. You decide what becomes a recorded expense.',
                      style: TextStyle(color: Color(0xFFE3F0E7), height: 1.4),
                    ),
                    const SizedBox(height: 22),
                    FilledButton.icon(
                      onPressed: () => _openAssistant(context),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: FinPilotColors.forest,
                      ),
                      icon: const Icon(Icons.edit_note_rounded),
                      label: const Text('Tell your story'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              _spendingOverview(theme),
              const SizedBox(height: 28),
              Text('Your next step',
                  style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800, color: FinPilotColors.ink)),
              const SizedBox(height: 12),
              _ActionCard(
                icon: Icons.receipt_long_outlined,
                title: 'View confirmed spending',
                description:
                    'See only the expenses you reviewed and confirmed.',
                onTap: () => _openTransactions(context),
              ),
              const SizedBox(height: 12),
              _ActionCard(
                icon: Icons.auto_awesome_outlined,
                title: 'Start a new story',
                description:
                    'Write or speak naturally, then review every detail.',
                onTap: () => _openAssistant(context),
              ),
              const SizedBox(height: 28),
              Text('How it works',
                  style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800, color: FinPilotColors.ink)),
              const SizedBox(height: 12),
              const _HowItWorksCard(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        onDestinationSelected: (index) {
          if (index == 1) _openTransactions(context);
          if (index == 2) _openAssistant(context);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined), label: 'Transactions'),
          NavigationDestination(
              icon: Icon(Icons.auto_awesome_outlined), label: 'Assistant'),
        ],
      ),
    );
  }

  Widget _spendingOverview(ThemeData theme) {
    final summary = _summary;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
            child: Text('Confirmed spending',
                style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800, color: FinPilotColors.ink))),
        IconButton(
            tooltip: 'Refresh spending summary',
            onPressed: _refreshSummary,
            icon: const Icon(Icons.refresh_rounded)),
      ]),
      const Text(
          'From records you confirmed. Currencies are shown separately.'),
      if (_fetchedAt != null)
        Text(
            'Checked at ${TimeOfDay.fromDateTime(_fetchedAt!).format(context)} · No bank feed connected',
            style: theme.textTheme.bodySmall),
      const SizedBox(height: 12),
      if (summary == null && _summaryError == null)
        const Card(
            child: Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator())))
      else if (_summaryError != null)
        Card(
            child: ListTile(
                title: Text(_summaryError!),
                trailing: const Icon(Icons.refresh_rounded),
                onTap: _refreshSummary))
      else if (summary!.totalsByCurrency.isEmpty)
        const Card(
            child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                    'No confirmed expenses yet. Your overview will fill in as you review records.')))
      else
        ..._currencyCards(summary),
    ]);
  }

  List<Widget> _currencyCards(RecordedExpenseSummary summary) {
    final currencies = summary.totalsByCurrency.keys.toList()..sort();
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day)
        .subtract(const Duration(days: 6));
    return currencies.map((currency) {
      final categories = summary.byCategory
          .where((entry) => entry.currency == currency)
          .toList()
        ..sort((a, b) => (double.tryParse(b.amount) ?? 0)
            .compareTo(double.tryParse(a.amount) ?? 0));
      final recent = summary.byDate.where((entry) {
        final day = DateTime.tryParse(entry.date);
        return entry.currency == currency &&
            day != null &&
            !day.isBefore(start);
      }).toList();
      return Card(
          child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$currency ${summary.totalsByCurrency[currency]}',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const Text('All confirmed dates'),
          const Divider(height: 24),
          const Text('By category',
              style: TextStyle(fontWeight: FontWeight.w700)),
          ...categories.map((entry) => Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  Expanded(child: Text(entry.category)),
                  Text('$currency ${entry.amount}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ]),
              )),
          const Divider(height: 24),
          const Text('Last 7 days with recorded spending',
              style: TextStyle(fontWeight: FontWeight.w700)),
          if (recent.isEmpty)
            const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('No confirmed spending in the last 7 days.')),
          ...recent.map((entry) => Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  Expanded(child: Text(entry.date)),
                  Text('$currency ${entry.amount}'),
                ]),
              )),
        ]),
      ));
    }).toList();
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: FinPilotColors.mint,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: FinPilotColors.forest),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(description,
                          style: TextStyle(
                              height: 1.35,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_ios_rounded, size: 16),
              ],
            ),
          ),
        ),
      );
}

class _HowItWorksCard extends StatelessWidget {
  const _HowItWorksCard();

  @override
  Widget build(BuildContext context) => const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            children: [
              _Step(
                  icon: Icons.chat_bubble_outline_rounded,
                  title: '1. Share your story',
                  detail: 'Describe what happened in your own words.'),
              Divider(height: 26),
              _Step(
                  icon: Icons.fact_check_outlined,
                  title: '2. Review the facts',
                  detail: 'Check amounts, dates and who actually paid.'),
              Divider(height: 26),
              _Step(
                  icon: Icons.check_circle_outline_rounded,
                  title: '3. Confirm with confidence',
                  detail: 'Only confirmed expenses enter your records.'),
            ],
          ),
        ),
      );
}

class _Step extends StatelessWidget {
  const _Step({required this.icon, required this.title, required this.detail});

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, color: FinPilotColors.forest),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(detail),
              ],
            ),
          ),
        ],
      );
}
