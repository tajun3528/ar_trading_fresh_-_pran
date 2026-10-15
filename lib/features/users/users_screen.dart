import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auto_refresh_mixin.dart';
import '../../core/insforge/insforge_exception.dart';
import '../../core/providers.dart';
import '../../models/company.dart';
import '../../models/profile.dart';
import '../../core/design/design_tokens.dart';
import '../../core/motion/skeleton.dart';

class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});

  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen> with AutoRefreshMixin<UsersScreen> {
  late Future<List<Profile>> _future;

  @override
  void refreshData() => setState(() { _future = _load(); });

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Profile>> _load() async {
    final client = ref.read(insforgeClientProvider);
    final rows = await client.from('profiles').select().order('created_at', ascending: false).get();
    return rows.map(Profile.fromJson).toList();
  }

  Future<void> _updateUser(
    Profile profile, {
    UserStatus? status,
    UserRole? role,
    String? pairedDeliverymanId,
    bool clearPairing = false,
    String? companyId,
    bool clearCompany = false,
  }) async {
    final client = ref.read(insforgeClientProvider);
    try {
      final patch = <String, dynamic>{};
      if (status != null) patch['status'] = status.name;
      if (role != null) patch['role'] = role.name;
      if (clearPairing) {
        patch['paired_deliveryman_id'] = null;
      } else if (pairedDeliverymanId != null) {
        patch['paired_deliveryman_id'] = pairedDeliverymanId;
      }
      if (clearCompany) {
        patch['company_id'] = null;
      } else if (companyId != null) {
        patch['company_id'] = companyId;
      }
      await client.from('profiles').eq('user_id', profile.userId).update(patch);
      setState(() { _future = _load(); });
    } on InsforgeException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _showPairDialog(Profile salesman, List<Profile> deliverymen) async {
    String? selected = salesman.pairedDeliverymanId;
    final result = await showDialog<String?>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Pair ${salesman.name} with a delivery man'),
          content: deliverymen.isEmpty
              ? const Text('No active delivery men yet.')
              : DropdownButtonFormField<String?>(
                  initialValue: selected,
                  decoration: const InputDecoration(labelText: 'Delivery man'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Unassigned')),
                    for (final d in deliverymen) DropdownMenuItem(value: d.userId, child: Text(d.name)),
                  ],
                  onChanged: (v) => setDialogState(() => selected = v),
                ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, selected ?? ''), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (result == null) return;
    if (result.isEmpty) {
      await _updateUser(salesman, clearPairing: true);
    } else {
      await _updateUser(salesman, pairedDeliverymanId: result);
    }
  }

  /// Most accounts here have no email, so there is no reset link to send —
  /// the owner is the way back in when someone forgets their password.
  Future<void> _showResetPasswordDialog(Profile user) async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var obscure = false;
    var busy = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text('Reset password for ${user.name}'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'They will sign in with this straight away. Tell it to them directly, '
                  'and have them change it in their own Profile.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: controller,
                  obscureText: obscure,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'New password',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18),
                      tooltip: obscure ? 'Show' : 'Hide',
                      onPressed: () => setLocal(() => obscure = !obscure),
                    ),
                  ),
                  validator: (v) => (v == null || v.length < 6) ? 'At least 6 characters' : null,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setLocal(() => busy = true);
                      try {
                        await ref.read(insforgeClientProvider).rpc('owner_reset_password', {
                          'p_user_id': user.userId,
                          'p_new': controller.text,
                        });
                        if (context.mounted) Navigator.pop(context);
                        if (mounted) {
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            SnackBar(content: Text('Password reset for ${user.name}')),
                          );
                        }
                      } catch (e) {
                        setLocal(() => busy = false);
                        if (mounted) {
                          ScaffoldMessenger.of(this.context)
                              .showSnackBar(SnackBar(content: Text('$e')));
                        }
                      }
                    },
              child: busy
                  ? const SizedBox(height: 17, width: 17, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Reset'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
  }

  Future<void> _showCompanyDialog(Profile salesman, List<Company> companies) async {
    String? selected = salesman.companyId;
    final result = await showDialog<String?>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Assign ${salesman.name} to a company'),
          content: companies.isEmpty
              ? const Text('No companies set up yet.')
              : DropdownButtonFormField<String?>(
                  initialValue: selected,
                  decoration: const InputDecoration(labelText: 'Company'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Unassigned')),
                    for (final c in companies) DropdownMenuItem(value: c.id, child: Text(c.name)),
                  ],
                  onChanged: (v) => setDialogState(() => selected = v),
                ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, selected ?? ''), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (result == null) return;
    if (result.isEmpty) {
      await _updateUser(salesman, clearCompany: true);
    } else {
      await _updateUser(salesman, companyId: result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final companies = ref.watch(companiesProvider).valueOrNull ?? const <Company>[];
    return RefreshIndicator(
      onRefresh: () async => setState(() { _future = _load(); }),
      child: FutureBuilder<List<Profile>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Padding(padding: const EdgeInsets.all(AppSpace.md), child: const SkeletonTable());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Failed to load users: ${snapshot.error}'));
          }
          final users = snapshot.data!;
          if (users.isEmpty) {
            return const Center(child: Text('No users yet.'));
          }
          final deliverymen =
              users.where((u) => u.role == UserRole.deliveryman && u.status == UserStatus.active).toList();
          final deliverymanNames = {for (final d in deliverymen) d.userId: d.name};
          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: users.length,
            itemBuilder: (context, index) => _UserTile(
              profile: users[index],
              pairedDeliverymanName: users[index].pairedDeliverymanId == null
                  ? null
                  : deliverymanNames[users[index].pairedDeliverymanId!],
              companyName: Company.findById(companies, users[index].companyId)?.name,
              onUpdate: (status, role) => _updateUser(users[index], status: status, role: role),
              onPair: () => _showPairDialog(users[index], deliverymen),
              onAssignCompany: () => _showCompanyDialog(users[index], companies),
              onResetPassword: () => _showResetPasswordDialog(users[index]),
            ),
          );
        },
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({
    required this.profile,
    required this.pairedDeliverymanName,
    required this.companyName,
    required this.onUpdate,
    required this.onPair,
    required this.onAssignCompany,
    required this.onResetPassword,
  });

  final Profile profile;
  final String? pairedDeliverymanName;
  final String? companyName;
  final void Function(UserStatus? status, UserRole? role) onUpdate;
  final VoidCallback onPair;
  final VoidCallback onAssignCompany;
  final VoidCallback onResetPassword;

  Color _statusColor(BuildContext context) {
    switch (profile.status) {
      case UserStatus.active:
        return Colors.green;
      case UserStatus.pending:
        return Colors.orange;
      case UserStatus.inactive:
        return Theme.of(context).colorScheme.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOwner = profile.role == UserRole.owner;
    final isSalesman = profile.role == UserRole.salesman;
    return Card(
      child: ListTile(
        title: Text(profile.name.isEmpty ? '(no name)' : profile.name),
        subtitle: Text(
          '${profile.mobile ?? '-'} • ${profile.role.name}'
          '${isSalesman ? ' • ${companyName ?? 'no company'} • paired with ${pairedDeliverymanName ?? 'nobody'}' : ''}',
        ),
        leading: CircleAvatar(
          backgroundColor: _statusColor(context).withValues(alpha: 0.15),
          child: Icon(Icons.person, color: _statusColor(context)),
        ),
        trailing: isOwner
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Chip(label: Text('Owner')),
                  PopupMenuButton<String>(
                    onSelected: (_) => onResetPassword(),
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'reset_password', child: Text('Reset password')),
                    ],
                  ),
                ],
              )
            : PopupMenuButton<String>(
                onSelected: (value) {
                  switch (value) {
                    case 'activate':
                      onUpdate(UserStatus.active, null);
                    case 'deactivate':
                      onUpdate(UserStatus.inactive, null);
                    case 'role_salesman':
                      onUpdate(null, UserRole.salesman);
                    case 'role_deliveryman':
                      onUpdate(null, UserRole.deliveryman);
                    case 'pair':
                      onPair();
                    case 'company':
                      onAssignCompany();
                    case 'reset_password':
                      onResetPassword();
                  }
                },
                itemBuilder: (context) => [
                  if (profile.status != UserStatus.active)
                    const PopupMenuItem(value: 'activate', child: Text('Approve / Activate')),
                  if (profile.status == UserStatus.active)
                    const PopupMenuItem(value: 'deactivate', child: Text('Deactivate')),
                  const PopupMenuDivider(),
                  if (profile.role != UserRole.salesman)
                    const PopupMenuItem(value: 'role_salesman', child: Text('Set role: Salesman')),
                  if (profile.role != UserRole.deliveryman)
                    const PopupMenuItem(value: 'role_deliveryman', child: Text('Set role: Delivery Man')),
                  const PopupMenuDivider(),
                  const PopupMenuItem(value: 'reset_password', child: Text('Reset password')),
                  if (isSalesman) ...[
                    const PopupMenuDivider(),
                    const PopupMenuItem(value: 'company', child: Text('Assign company')),
                    const PopupMenuItem(value: 'pair', child: Text('Assign delivery man')),
                  ],
                ],
              ),
      ),
    );
  }
}
