import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/viz/status_palette.dart';

/// Entry point for starting a new daily summary — two different order
/// forms depending on what the salesman needs today.
class NewOrderChoiceScreen extends StatelessWidget {
  const NewOrderChoiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Text('New order', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            const Text(
              'Choose how you want to build today\'s order.',
              style: TextStyle(color: VizChrome.muted),
            ),
            const SizedBox(height: 24),
            _OrderTypeCard(
              icon: Icons.flash_on,
              title: 'Quick order',
              subtitle: 'Your most-ordered products with quantity fields — fastest for a routine day.',
              onTap: () => context.go('/salesman/new-summary/quick'),
            ),
            const SizedBox(height: 16),
            _OrderTypeCard(
              icon: Icons.storefront,
              title: 'Full catalog order',
              subtitle: 'Browse every in-stock product and add whatever you need.',
              onTap: () => context.go('/salesman/new-summary/full'),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderTypeCard extends StatelessWidget {
  const _OrderTypeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: colorScheme.primaryContainer, borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: const TextStyle(color: VizChrome.muted, fontSize: 13)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
