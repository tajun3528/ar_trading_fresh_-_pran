import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auto_refresh_mixin.dart';
import '../../core/insforge/insforge_exception.dart';
import '../../core/providers.dart';
import '../../models/sales_route.dart';
import '../../core/design/design_tokens.dart';
import '../../core/motion/skeleton.dart';

/// Owner-managed list of sales routes (areas) — a simple name list, not a
/// shop/territory system. Salesmen pick one of these when starting a daily
/// summary (see SubmitSummaryScreen).
class RoutesScreen extends ConsumerStatefulWidget {
  const RoutesScreen({super.key});

  @override
  ConsumerState<RoutesScreen> createState() => _RoutesScreenState();
}

class _RoutesScreenState extends ConsumerState<RoutesScreen> with AutoRefreshMixin<RoutesScreen> {
  late Future<List<SalesRoute>> _future;

  @override
  void refreshData() => _reload();

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<SalesRoute>> _load() async {
    final client = ref.read(insforgeClientProvider);
    final rows = await client.from('routes').select().order('name').get();
    return rows.map(SalesRoute.fromJson).toList();
  }

  void _reload() => setState(() { _future = _load(); });

  Future<void> _showForm({SalesRoute? existing}) async {
    final controller = TextEditingController(text: existing?.name ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? 'New route' : 'Rename route'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (result == null || result.isEmpty) return;

    final client = ref.read(insforgeClientProvider);
    try {
      if (existing == null) {
        await client.from('routes').insert([
          {'name': result}
        ]);
      } else {
        await client.from('routes').eq('id', existing.id).update({'name': result});
      }
      _reload();
    } on InsforgeException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _toggleActive(SalesRoute route) async {
    final client = ref.read(insforgeClientProvider);
    try {
      await client.from('routes').eq('id', route.id).update({'is_active': !route.isActive});
      _reload();
    } on InsforgeException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _delete(SalesRoute route) async {
    final client = ref.read(insforgeClientProvider);
    try {
      await client.from('routes').eq('id', route.id).delete();
      _reload();
    } on InsforgeException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cannot delete "${route.name}": it is in use. Deactivate it instead.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<List<SalesRoute>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Padding(padding: const EdgeInsets.all(AppSpace.md), child: const SkeletonTable());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Failed to load routes: ${snapshot.error}'));
          }
          final routes = snapshot.data!;
          if (routes.isEmpty) {
            return const Center(child: Text('No routes yet. Tap + to add one.'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: routes.length,
            itemBuilder: (context, index) {
              final route = routes[index];
              return Card(
                child: ListTile(
                  title: Text(route.name),
                  subtitle: Text(route.isActive ? 'Active' : 'Inactive'),
                  onTap: () => _showForm(existing: route),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'toggle') _toggleActive(route);
                      if (value == 'delete') _delete(route);
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(value: 'toggle', child: Text(route.isActive ? 'Deactivate' : 'Activate')),
                      const PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(onPressed: () => _showForm(), child: const Icon(Icons.add)),
    );
  }
}
