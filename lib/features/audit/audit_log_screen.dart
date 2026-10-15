import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auto_refresh_mixin.dart';
import '../../core/providers.dart';
import '../../core/viz/status_palette.dart';
import '../../models/audit_log_entry.dart';
import '../../core/design/design_tokens.dart';
import '../../core/motion/skeleton.dart';

/// How many rows come back per fetch. The log grows forever, so it is read a
/// page at a time rather than capped at a number that silently hides the rest.
const _pageSize = 100;

class AuditLogScreen extends ConsumerStatefulWidget {
  const AuditLogScreen({super.key});

  @override
  ConsumerState<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends ConsumerState<AuditLogScreen> with AutoRefreshMixin<AuditLogScreen> {
  final List<AuditLogEntry> _entries = [];
  final Map<String, String> _userNames = {};

  late DateTimeRange _range;
  String? _table;
  List<String> _tables = const [];

  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  Object? _error;

  @override
  void refreshData() => _reload();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    // A month back by default — enough to cover "what changed recently"
    // without pulling the whole history on every visit.
    _range = DateTimeRange(start: DateTime(now.year, now.month, now.day).subtract(const Duration(days: 30)), end: now);
    _reload();
  }

  String _iso(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  Future<void> _reload() async {
    setState(() {
      _entries.clear();
      _loading = true;
      _hasMore = true;
      _error = null;
    });
    await _fetch();
  }

  Future<void> _fetch() async {
    final client = ref.read(insforgeClientProvider);
    try {
      var query = client
          .from('audit_log')
          .select()
          .gte('occurred_at', _iso(_range.start))
          // The end day is inclusive, so reach past midnight on it.
          .lt('occurred_at', _iso(_range.end.add(const Duration(days: 1))));
      if (_table != null) query = query.eq('table_name', _table!);

      final rows = await query
          .order('occurred_at', ascending: false)
          .range(_entries.length, _entries.length + _pageSize - 1)
          .get();

      final batch = rows.map(AuditLogEntry.fromJson).toList();
      await _resolveNames(batch);

      if (!mounted) return;
      setState(() {
        _entries.addAll(batch);
        _hasMore = batch.length == _pageSize;
        _loading = false;
        _loadingMore = false;
      });
      if (_tables.isEmpty) unawaited(_loadTableList());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  /// The log stores only a user id; a name makes it readable.
  Future<void> _resolveNames(List<AuditLogEntry> batch) async {
    final missing = batch
        .map((e) => e.userId)
        .whereType<String>()
        .where((id) => !_userNames.containsKey(id))
        .toSet()
        .toList();
    if (missing.isEmpty) return;
    try {
      final rows =
          await ref.read(insforgeClientProvider).from('profiles').select('user_id,name').inList('user_id', missing).get();
      for (final r in rows) {
        _userNames[r['user_id'] as String] = (r['name'] as String?) ?? 'Someone';
      }
    } catch (_) {
      // A missing name is cosmetic — never fail the page over it.
    }
  }

  /// The distinct tables in range, so the filter offers only what's there.
  Future<void> _loadTableList() async {
    try {
      final rows = await ref
          .read(insforgeClientProvider)
          .from('audit_log')
          .select('table_name')
          .order('table_name')
          .limit(1000)
          .get();
      final names = rows.map((r) => r['table_name'] as String).toSet().toList()..sort();
      if (mounted) setState(() => _tables = names);
    } catch (_) {
      // Filter stays empty; the list itself still works.
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    await _fetch();
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: _range,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 1),
    );
    if (picked == null) return;
    setState(() => _range = picked);
    await _reload();
  }

  static IconData _iconFor(String action) {
    switch (action) {
      case 'INSERT':
        return Icons.add_circle_outline;
      case 'UPDATE':
        return Icons.edit_outlined;
      case 'DELETE':
        return Icons.delete_outline;
      default:
        return Icons.history;
    }
  }

  static Color _colorFor(String action) {
    switch (action) {
      case 'INSERT':
        return StatusLevel.good.color;
      case 'UPDATE':
        return VizChrome.info;
      case 'DELETE':
        return StatusLevel.critical.color;
      default:
        return VizChrome.secondaryInk;
    }
  }

  /// Table names are how the database spells things; people don't.
  static String _prettyTable(String table) {
    const names = {
      'products': 'product',
      'product_units': 'product price',
      'product_monthly_etp': 'monthly ETP',
      'product_batches': 'batch',
      'salesman_monthly_prices': 'salesman price',
      'daily_summaries': 'order',
      'daily_summary_items': 'order line',
      'deliveries': 'delivery',
      'delivery_items': 'delivery line',
      'delivery_damages': 'damage entry',
      'monthly_targets': 'target',
      'stock': 'stock',
      'stock_ins': 'stock-in',
      'profiles': 'user',
      'categories': 'category',
      'routes': 'route',
      'companies': 'company',
    };
    return names[table] ?? table.replaceAll('_', ' ');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: _pickRange,
                icon: const Icon(Icons.date_range, size: 16),
                label: Text('${DateFormat.yMMMd().format(_range.start)} — ${DateFormat.yMMMd().format(_range.end)}'),
              ),
              SizedBox(
                width: 210,
                child: DropdownButtonFormField<String?>(
                  initialValue: _table,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'What changed',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Everything')),
                    for (final t in _tables)
                      DropdownMenuItem(value: t, child: Text(_prettyTable(t), overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) {
                    setState(() => _table = v);
                    _reload();
                  },
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _body() {
    if (_loading) return Padding(padding: const EdgeInsets.all(AppSpace.md), child: const SkeletonTable());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Failed to load audit log: $_error'),
        ),
      );
    }
    if (_entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.history_toggle_off, size: 38, color: VizChrome.secondaryInk),
              const SizedBox(height: 10),
              const Text('Nothing changed in this range.', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                _table == null ? 'Try a wider date range.' : 'Try a wider date range, or "Everything".',
                style: const TextStyle(fontSize: 12.5, color: VizChrome.secondaryInk),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
        itemCount: _entries.length + 1,
        itemBuilder: (context, index) {
          if (index == _entries.length) return _footer();
          final e = _entries[index];
          final who = e.userId == null ? null : _userNames[e.userId];
          return ListTile(
            dense: true,
            leading: Icon(_iconFor(e.actionType), color: _colorFor(e.actionType), size: 20),
            title: Text(
              '${_actionVerb(e.actionType)} ${_prettyTable(e.tableName)}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              '${who ?? 'System'} · ${DateFormat.yMMMd().add_jm().format(e.occurredAt)}',
              style: const TextStyle(fontSize: 12),
            ),
          );
        },
      ),
    );
  }

  static String _actionVerb(String action) {
    switch (action) {
      case 'INSERT':
        return 'Added';
      case 'UPDATE':
        return 'Changed';
      case 'DELETE':
        return 'Deleted';
      default:
        return action;
    }
  }

  Widget _footer() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Column(
        children: [
          Text(
            _hasMore
                ? 'Showing the ${_entries.length} most recent changes in this range.'
                : 'That is all ${_entries.length} change${_entries.length == 1 ? '' : 's'} in this range.',
            style: const TextStyle(fontSize: 12, color: VizChrome.secondaryInk),
            textAlign: TextAlign.center,
          ),
          if (_hasMore) ...[
            const SizedBox(height: 10),
            _loadingMore
                ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : OutlinedButton.icon(
                    onPressed: _loadMore,
                    icon: const Icon(Icons.expand_more, size: 16),
                    label: const Text('Load older'),
                  ),
          ],
        ],
      ),
    );
  }
}