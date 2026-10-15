import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/company.dart';
import 'providers.dart';

/// Lets an Owner-facing screen pick which company's catalog it's managing.
/// Defaults to the first company (alphabetically) once loaded and reports it
/// via [onChanged], so the caller never has to separately seed a default.
class CompanySelector extends ConsumerWidget {
  const CompanySelector({required this.selectedId, required this.onChanged, super.key});

  final String? selectedId;
  final ValueChanged<Company> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final companiesAsync = ref.watch(companiesProvider);
    return companiesAsync.when(
      data: (companies) {
        if (companies.isEmpty) return const SizedBox.shrink();
        if (selectedId == null || !companies.any((c) => c.id == selectedId)) {
          WidgetsBinding.instance.addPostFrameCallback((_) => onChanged(companies.first));
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: DropdownButtonFormField<String>(
            initialValue: selectedId,
            decoration: const InputDecoration(labelText: 'Company', border: OutlineInputBorder()),
            items: [for (final c in companies) DropdownMenuItem(value: c.id, child: Text(c.name))],
            onChanged: (id) {
              if (id == null) return;
              onChanged(companies.firstWhere((c) => c.id == id));
            },
          ),
        );
      },
      loading: () => const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
      error: (e, _) => Padding(padding: const EdgeInsets.all(16), child: Text('Failed to load companies: $e')),
    );
  }
}
