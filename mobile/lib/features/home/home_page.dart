import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/finpilot_theme.dart';
import '../financial_review/journal_entry_page.dart';
import '../transactions/transactions_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({this.api, super.key});

  final FinPilotApi? api;

  void _openAssistant(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => JournalEntryPage(api: api ?? HttpFinPilotApi()),
      ));

  void _openTransactions(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => TransactionsPage(api: api ?? HttpFinPilotApi()),
      ));

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
