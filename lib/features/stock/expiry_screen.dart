import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auto_refresh_mixin.dart';
import '../../core/company_selector.dart';
import '../../core/insforge/insforge_exception.dart';
import '../../core/providers.dart';
import '../../core/viz/bold_stat_card.dart';
import '../../core/viz/status_palette.dart';
import '../../models/company.dart';
import '../../models/notification.dart';
import '../../models/product.dart';
import '../dashboard/stat_tile.dart';
import '../../core/design/design_tokens.dart';
import '../../core/motion/skeleton.dart';

final _date = DateFormat('d MMM yyyy');

/// Buckets, worst first. Matches the status strings product_expiry_watch
/// returns, so the two can't drift apart.
const _order = ['expired', 'critical', 'warning', 'ok', 'unknown'];

class _ExpiryData {
  _ExpiryData({required this.batches, required this.products});

  final List<ExpiryBatch> batches;
  final List<Product> products;

  int countOf(String status) => batches.where((b) => b.status == status).length;
}

/// Expiry watch — for a distributor of biscuits and chocolate, knowing what
/// goes out of date next month is the difference between selling it and
/// collecting it back as damage.
class ExpiryScreen extends ConsumerStatefulWidget {
  const ExpiryScreen({super.key});

  @override
  ConsumerState<ExpiryScreen> createState() => _ExpiryScreenState();
}

class _ExpiryScreenState extends ConsumerState<ExpiryScreen> with AutoRefreshMixin<ExpiryScreen> {
  Company? _company;
  Future<_ExpiryData>? _future;
  final _searchController = TextEditingController();
  String _search = '';
  bool _onlyAttention = false;

  @override
  void refreshData() => _reload();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<_ExpiryData> _load(String companyId) async {
    final client = ref.read(insforgeClientProvider);
    final batchRows = await client
        .from('product_expiry_watch')
        .select()
        .eq('company_id', companyId)
        .order('expiry_date')
        .get();
    final productRows =
        await client.from('products').select().eq('company_id', companyId).eq('is_active', true).order('name').get();

    final batches = batchRows.map(ExpiryBatch.fromJson).toList()
      ..sort((a, b) {
        final byStatus = _order.indexOf(a.status).compareTo(_order.indexOf(b.status));
        if (byStatus != 0) return byStatus;
        final ad = a.expiryDate, bd = b.expiryDate;
        if (ad == null && bd == null) return a.productName.compareTo(b.productName);
        if (ad == null) return 1;
        if (bd == null) return -1;
        return ad.compareTo(bd);
      });

    return _ExpiryData(batches: batches, products: productRows.map(Product.fromJson).toList());
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

  static StatusLevel _levelFor(String status) {
    switch (status) {
      case 'expired':
        return StatusLevel.critical;
      case 'critical':
        return StatusLevel.serious;
      case 'warning':
        return StatusLevel.warning;
      default:
        return StatusLevel.good;
    }
  }

  static String _labelFor(ExpiryBatch b) {
    switch (b.status) {
      case 'expired':
        return 'Expired ${(-b.daysRemaining!).abs()}d ago';
      case 'critical':
        return '${b.daysRemaining}d left';
      case 'warning':
        return '${b.daysRemaining}d left';
      case 'unknown':
        return 'No date set';
      default:
        return '${b.daysRemaining}d left';
    }
  }

  Future<void> _showBatchDialog(_ExpiryData data, {ExpiryBatch? existing}) async {
    Product? product = existing == null
        ? null
        : data.products.where((p) => p.id == existing.productId).firstOrNull;
    final batchController = TextEditingController(text: existing?.batchNo ?? '');
    DateTime? mfg = existing?.mfgDate;
    DateTime? expiry = existing?.expiryDate;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) {
          Future<void> pick(bool isExpiry) async {
            final now = DateTime.now();
            final initial = (isExpiry ? expiry : mfg) ?? now;
            final picked = await showDatePicker(
              context: context,
              initialDate: initial,
              firstDate: DateTime(now.year - 5),
              lastDate: DateTime(now.year + 6),
            );
            if (picked != null) setLocal(() => isExpiry ? expiry = picked : mfg = picked);
          }

          return AlertDialog(
            title: Text(existing == null ? 'New batch' : 'Edit batch'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<Product>(
                    initialValue: product,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Product', border: OutlineInputBorder()),
                    items: [
                      for (final p in data.products)
                        DropdownMenuItem(value: p, child: Text(p.name, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: existing != null ? null : (p) => setLocal(() => product = p),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: batchController,
                    decoration: const InputDecoration(
                      labelText: 'Batch number',
                      border: OutlineInputBorder(),
                      helperText: "As printed on the carton",
                    ),
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: () => pick(false),
                    icon: const Icon(Icons.event, size: 16),
                    label: Text(mfg == null ? 'Manufactured (optional)' : 'Mfg: ${_date.format(mfg!)}'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => pick(true),
                    icon: const Icon(Icons.event_busy, size: 16),
                    label: Text(expiry == null ? 'Expires on' : 'Expires: ${_date.format(expiry!)}'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
            ],
          );
        },
      ),
    );

    // Read before disposing — a disposed controller throws on .text.
    final batchNo = batchController.text.trim();
    batchController.dispose();
    if (saved != true || !mounted) return;

    final chosen = product;
    if (chosen == null || batchNo.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick a product and enter a batch number')),
      );
      return;
    }

    try {
      final client = ref.read(insforgeClientProvider);
      final payload = <String, dynamic>{
        'batch_no': batchNo,
        'mfg_date': mfg == null ? null : DateFormat('yyyy-MM-dd').format(mfg!),
        'expiry_date': expiry == null ? null : DateFormat('yyyy-MM-dd').format(expiry!),
      };
      if (existing == null) {
        await client.from('product_batches').insert([
          {'product_id': chosen.id, ...payload},
        ]);
      } else {
        await client.from('product_batches').eq('id', existing.batchId).update(payload);
      }
      if (mounted) _reload();
    } on InsforgeException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _deleteBatch(ExpiryBatch batch) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete batch ${batch.batchNo}?'),
        content: Text('${batch.productName} — this only removes the expiry record, not any stock.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton.tonal(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(insforgeClientProvider).from('product_batches').eq('id', batch.batchId).delete();
      if (mounted) _reload();
    } on InsforgeException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          CompanySelector(selectedId: _company?.id, onChanged: _onCompanyChanged),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search products or batch numbers',
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: _search.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () => setState(() {
                                _searchController.clear();
                                _search = '';
                              }),
                            ),
                    ),
                    onChanged: (v) => setState(() => _search = v),
                  ),
                ),
                const SizedBox(width: 10),
                FilterChip(
                  label: const Text('Needs attention'),
                  selected: _onlyAttention,
                  onSelected: (v) => setState(() => _onlyAttention = v),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _future == null
                ? const SizedBox.shrink()
                : FutureBuilder<_ExpiryData>(
                    future: _future,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return Padding(padding: const EdgeInsets.all(AppSpace.md), child: const SkeletonDashboard());
                      }
                      if (snapshot.hasError) {
                        return Center(child: Text('Failed to load batches: ${snapshot.error}'));
                      }
                      return _buildBody(snapshot.data!);
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: _future == null
          ? null
          : FutureBuilder<_ExpiryData>(
              future: _future,
              builder: (context, snapshot) => FloatingActionButton.extended(
                onPressed: snapshot.hasData ? () => _showBatchDialog(snapshot.data!) : null,
                icon: const Icon(Icons.add),
                label: const Text('Add batch'),
              ),
            ),
    );
  }

  Widget _buildBody(_ExpiryData data) {
    final query = _search.trim().toLowerCase();
    var visible = data.batches;
    if (query.isNotEmpty) {
      visible = visible
          .where((b) =>
              b.productName.toLowerCase().contains(query) || b.batchNo.toLowerCase().contains(query))
          .toList();
    }
    if (_onlyAttention) visible = visible.where((b) => b.needsAttention).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
      children: [
        StatGrid(tiles: [
          BoldStatCard(
            label: 'Expired',
            value: '${data.countOf('expired')}',
            icon: Icons.dangerous,
            color: StatusLevel.critical.color,
          ),
          BoldStatCard(
            label: 'Within 30 days',
            value: '${data.countOf('critical')}',
            icon: Icons.timer,
            color: StatusLevel.serious.color,
          ),
          BoldStatCard(
            label: 'Within 90 days',
            value: '${data.countOf('warning')}',
            icon: Icons.schedule,
            color: StatusLevel.warning.color,
          ),
          BoldStatCard(
            label: 'Batches tracked',
            value: '${data.batches.length}',
            icon: Icons.inventory,
            color: VizChrome.accentSlate,
          ),
        ]),
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Card(
            color: VizChrome.info.withValues(alpha: 0.08),
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Quantities shown are what was received under a batch, not what is left — stock is not '
                'counted per batch, so this warns you in time to push a product rather than enforcing '
                'oldest-first loading.',
                style: TextStyle(fontSize: 12, color: VizChrome.secondaryInk),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (data.batches.isEmpty)
          _empty(
            'No batches recorded yet.',
            'Add a batch with its expiry date and it will be watched here. '
                'Batch numbers are printed on the carton.',
          )
        else if (visible.isEmpty)
          _empty('Nothing matches.', 'Try a different search, or clear the "needs attention" filter.')
        else
          for (final batch in visible) _batchTile(batch),
      ],
    );
  }

  Widget _empty(String title, String body) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.event_available, size: 34, color: VizChrome.secondaryInk),
            const SizedBox(height: 10),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, color: VizChrome.secondaryInk),
            ),
          ],
        ),
      ),
    );
  }

  Widget _batchTile(ExpiryBatch batch) {
    final level = _levelFor(batch.status);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
        child: ListTile(
          leading: Container(
            width: 5,
            height: 42,
            decoration: BoxDecoration(color: level.color, borderRadius: BorderRadius.circular(3)),
          ),
          title: Text(batch.productName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 2),
              Text(
                'Batch ${batch.batchNo}'
                '${batch.expiryDate == null ? '' : ' · expires ${_date.format(batch.expiryDate!)}'}',
                style: const TextStyle(fontSize: 12.5),
              ),
              if (batch.received != null)
                Text(
                  'Received ${batch.received}'
                  '${batch.lastReceivedOn == null ? '' : ' · last ${_date.format(batch.lastReceivedOn!)}'}',
                  style: const TextStyle(fontSize: 11.5, color: VizChrome.secondaryInk),
                ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: level.color.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  _labelFor(batch),
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: level.color),
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (v) async {
                  final data = await _future;
                  if (!mounted || data == null) return;
                  if (v == 'edit') {
                    await _showBatchDialog(data, existing: batch);
                  } else {
                    await _deleteBatch(batch);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
