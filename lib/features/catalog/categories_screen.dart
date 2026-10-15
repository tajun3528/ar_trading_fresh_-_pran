import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auto_refresh_mixin.dart';
import '../../core/company_selector.dart';
import '../../core/insforge/insforge_exception.dart';
import '../../core/providers.dart';
import '../../models/category.dart';
import '../../models/company.dart';
import '../../core/design/design_tokens.dart';
import '../../core/motion/skeleton.dart';

class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen> with AutoRefreshMixin<CategoriesScreen> {
  Company? _company;
  Future<List<Category>>? _future;

  @override
  void refreshData() => _reload();

  Future<List<Category>> _load(String companyId) async {
    final client = ref.read(insforgeClientProvider);
    final rows = await client.from('categories').select().eq('company_id', companyId).order('name').get();
    return rows.map(Category.fromJson).toList();
  }

  void _reload() {
    final company = _company;
    if (company != null) setState(() { _future = _load(company.id); });
  }

  void _onCompanyChanged(Company company) {
    setState(() {
      _company = company;
      _future = _load(company.id);
    });
  }

  Future<void> _showForm({Category? existing}) async {
    final company = _company;
    if (company == null) return;
    final controller = TextEditingController(text: existing?.name ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? 'New category' : 'Rename category'),
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
        await client.from('categories').insert([
          {'name': result, 'company_id': company.id}
        ]);
      } else {
        await client.from('categories').eq('id', existing.id).update({'name': result});
      }
      _reload();
    } on InsforgeException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _toggleActive(Category category) async {
    final client = ref.read(insforgeClientProvider);
    try {
      await client.from('categories').eq('id', category.id).update({'is_active': !category.isActive});
      _reload();
    } on InsforgeException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _delete(Category category) async {
    final client = ref.read(insforgeClientProvider);
    try {
      await client.from('categories').eq('id', category.id).delete();
      _reload();
    } on InsforgeException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cannot delete "${category.name}": it is in use. Deactivate it instead.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          CompanySelector(selectedId: _company?.id, onChanged: _onCompanyChanged),
          Expanded(
            child: _future == null
                ? const SizedBox.shrink()
                : FutureBuilder<List<Category>>(
                    future: _future,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return Padding(padding: const EdgeInsets.all(AppSpace.md), child: const SkeletonTable());
                      }
                      if (snapshot.hasError) {
                        return Center(child: Text('Failed to load categories: ${snapshot.error}'));
                      }
                      final categories = snapshot.data!;
                      if (categories.isEmpty) {
                        return const Center(child: Text('No categories yet. Tap + to add one.'));
                      }
                      return ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: categories.length,
                        itemBuilder: (context, index) {
                          final category = categories[index];
                          return Card(
                            child: ListTile(
                              title: Text(category.name),
                              subtitle: Text(category.isActive ? 'Active' : 'Inactive'),
                              onTap: () => _showForm(existing: category),
                              trailing: PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'toggle') _toggleActive(category);
                                  if (value == 'delete') _delete(category);
                                },
                                itemBuilder: (context) => [
                                  PopupMenuItem(
                                      value: 'toggle', child: Text(category.isActive ? 'Deactivate' : 'Activate')),
                                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(onPressed: () => _showForm(), child: const Icon(Icons.add)),
    );
  }
}
