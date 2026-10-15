import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/preferences/preferences_controller.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/viz/status_palette.dart';
import '../../models/company.dart';
import '../../models/profile.dart';
import '../../models/user_preferences.dart';
import '../../core/design/design_tokens.dart';
import '../../core/motion/skeleton.dart';

/// Everything a person can change about their own copy of the app, in one
/// place — their details, how it looks, where it opens, and what it tells
/// them. Anything the owner controls (role, company, pairing) is shown here
/// but read-only, so it is obvious who to ask.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _mobile = TextEditingController();
  final _email = TextEditingController();

  bool _editingDetails = false;
  bool _savingDetails = false;
  String? _seededFor;

  /// Where the text-size slider's thumb is mid-drag, before it is saved.
  double? _pendingScale;

  @override
  void dispose() {
    _name.dispose();
    _mobile.dispose();
    _email.dispose();
    super.dispose();
  }

  /// Fills the fields from the signed-in profile once, and again if a
  /// different person signs in — but never while they are mid-edit.
  void _seed(Profile profile) {
    if (_seededFor == profile.userId || _editingDetails) return;
    _seededFor = profile.userId;
    _name.text = profile.name;
    _mobile.text = profile.mobile ?? '';
    _email.text = profile.email ?? '';
  }

  void _toast(String message, {bool bad = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: bad ? StatusLevel.critical.color : null,
      ),
    );
  }

  Future<void> _saveDetails() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _savingDetails = true);
    try {
      await ref.read(insforgeClientProvider).rpc('update_my_profile', {
        'p_name': _name.text.trim(),
        'p_mobile': _mobile.text.trim(),
        'p_email': _email.text.trim().isEmpty ? null : _email.text.trim(),
      });
      await ref.read(authControllerProvider.notifier).refresh();
      if (!mounted) return;
      setState(() {
        _editingDetails = false;
        _savingDetails = false;
      });
      _toast('Details saved');
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingDetails = false);
      _toast(_clean(e), bad: true);
    }
  }

  /// Postgres errors arrive wrapped; show the sentence, not the stack.
  static String _clean(Object error) {
    final text = error.toString();
    final match = RegExp(r'([a-z].*)$', multiLine: true).firstMatch(text.replaceAll('Exception: ', ''));
    return match?.group(1)?.trim() ?? text;
  }

  Future<void> _apply(Future<void> Function() action, String done) async {
    try {
      await action();
      _toast(done);
    } catch (e) {
      _toast(_clean(e), bad: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(authControllerProvider).valueOrNull;
    final prefs = ref.watch(effectivePreferencesProvider);
    if (profile == null) return Padding(padding: const EdgeInsets.all(AppSpace.md), child: const SkeletonTable());
    _seed(profile);

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
      children: [
        _Header(profile: profile),
        const SizedBox(height: 12),
        _details(profile),
        const SizedBox(height: 12),
        _appearance(prefs),
        const SizedBox(height: 12),
        _startup(profile, prefs),
        const SizedBox(height: 12),
        _notifications(prefs),
        const SizedBox(height: 12),
        _account(profile),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
          icon: const Icon(Icons.logout, size: 17),
          label: const Text('Sign out'),
          style: OutlinedButton.styleFrom(
            foregroundColor: StatusLevel.critical.color,
            side: BorderSide(color: StatusLevel.critical.color.withValues(alpha: 0.45)),
            minimumSize: const Size.fromHeight(44),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- details
  Widget _details(Profile profile) {
    return _Section(
      title: 'Your details',
      caption: 'How you sign in, and what other people see next to your orders.',
      icon: Icons.badge_outlined,
      trailing: _editingDetails
          ? null
          : TextButton(
              onPressed: () => setState(() => _editingDetails = true),
              child: const Text('Edit'),
            ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!_editingDetails) ...[
              _ReadRow(label: 'Name', value: profile.name),
              _ReadRow(label: 'Mobile', value: profile.mobile ?? '—'),
              _ReadRow(label: 'Email', value: profile.email?.isNotEmpty == true ? profile.email! : 'Not set'),
            ] else ...[
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Full name', border: OutlineInputBorder()),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _mobile,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Mobile number',
                  border: OutlineInputBorder(),
                  helperText: 'This is what you sign in with.',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  if (!RegExp(r'^[0-9+][0-9\- ]{6,}$').hasMatch(v.trim())) return 'Enter a valid mobile number';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email (optional)', border: OutlineInputBorder()),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim())) return 'Enter a valid email';
                  return null;
                },
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _savingDetails
                          ? null
                          : () {
                              setState(() {
                                _editingDetails = false;
                                _seededFor = null;
                              });
                              _seed(profile);
                            },
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _savingDetails ? null : _saveDetails,
                      child: _savingDetails
                          ? const SizedBox(
                              height: 17, width: 17, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Save'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------- appearance
  Widget _appearance(UserPreferences prefs) {
    final controller = ref.read(preferencesProvider.notifier);

    return _Section(
      title: 'Appearance',
      caption: 'Only you see these — they follow you to any device you sign in on.',
      icon: Icons.palette_outlined,
      trailing: TextButton(
        onPressed: () => _apply(controller.resetAppearance, 'Appearance reset'),
        child: const Text('Reset'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Label('Theme'),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.system, label: Text('System'), icon: Icon(Icons.brightness_auto, size: 15)),
              ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode, size: 15)),
              ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode, size: 15)),
            ],
            selected: {prefs.themeMode},
            showSelectedIcon: false,
            onSelectionChanged: (s) => _apply(() => controller.setThemeMode(s.first), 'Theme changed'),
          ),
          const SizedBox(height: 18),

          const _Label('Accent colour'),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final accent in AppAccent.values)
                _AccentSwatch(
                  accent: accent,
                  selected: prefs.accent == accent,
                  onTap: () => _apply(() => controller.setAccent(accent), '${accent.label} accent'),
                ),
            ],
          ),
          const SizedBox(height: 18),

          const _Label('Text size'),
          Row(
            children: [
              const Text('A', style: TextStyle(fontSize: 11, color: VizChrome.secondaryInk)),
              Expanded(
                child: Slider(
                  // Follows the thumb locally while dragging, so the label
                  // tracks the finger without a write per pixel.
                  value: (_pendingScale ?? prefs.textScale).clamp(0.75, 1.30),
                  min: 0.75,
                  max: 1.30,
                  divisions: 11,
                  label: '${((_pendingScale ?? prefs.textScale) * 100).round()}%',
                  onChanged: (v) => setState(() => _pendingScale = v),
                  onChangeEnd: (v) async {
                    await _apply(() => controller.setTextScale(v), 'Text size ${(v * 100).round()}%');
                    // Hand control back to the saved value once it lands.
                    if (mounted) setState(() => _pendingScale = null);
                  },
                ),
              ),
              const Text('A', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              SizedBox(
                width: 42,
                child: Text(
                  '${((_pendingScale ?? prefs.textScale) * 100).round()}%',
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                ),
              ),
            ],
          ),
          const Text(
            'The app ships at 88%, which fits the most on screen.',
            style: TextStyle(fontSize: 11.5, color: VizChrome.secondaryInk),
          ),
          const SizedBox(height: 18),

          _Toggle(
            title: 'Reduce motion',
            caption: 'Switch off animations across the app. Useful if you find movement '
                'distracting, or if your phone feels slow with it.',
            value: prefs.reduceMotion,
            onChanged: (v) => _apply(
              () => controller.setReduceMotion(v),
              v ? 'Animations off' : 'Animations on',
            ),
          ),
          const SizedBox(height: 10),

          const _Label('Spacing'),
          for (final density in AppDensity.values)
            _ChoiceRow(
              label: density.label,
              caption: density.caption,
              selected: prefs.density == density,
              onTap: () => _apply(() => controller.setDensity(density), '${density.label} spacing'),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- startup
  Widget _startup(Profile profile, UserPreferences prefs) {
    final controller = ref.read(preferencesProvider.notifier);
    final options = _landingOptions(profile);

    return _Section(
      title: 'When you sign in',
      caption: 'The page the app opens on.',
      icon: Icons.home_outlined,
      child: DropdownButtonFormField<String?>(
        initialValue: options.any((o) => o.$1 == prefs.landingRoute) ? prefs.landingRoute : null,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Open on', border: OutlineInputBorder()),
        items: [
          const DropdownMenuItem(value: null, child: Text('Dashboard (default)')),
          for (final (route, label) in options.skip(1))
            DropdownMenuItem(value: route, child: Text(label, overflow: TextOverflow.ellipsis)),
        ],
        onChanged: (route) => _apply(
          () => controller.setLandingRoute(route),
          route == null ? 'Opens on your dashboard' : 'Opens on that page',
        ),
      ),
    );
  }

  /// The pages this person is actually allowed to open, so nobody can pick a
  /// landing page the router would immediately bounce them out of.
  List<(String?, String)> _landingOptions(Profile profile) {
    switch (profile.role) {
      case UserRole.owner:
        return const [
          (null, 'Dashboard (default)'),
          ('/owner/stock', 'Stock'),
          ('/owner/summaries', 'Daily Summaries'),
          ('/owner/deliveries', 'Deliveries'),
          ('/owner/profit', 'Profit & Targets'),
          ('/owner/product-sales', 'Sales by Product'),
          ('/owner/performance', 'Salesmen & Routes'),
          ('/owner/reports', 'Reports'),
        ];
      case UserRole.salesman:
        return const [
          (null, 'Dashboard (default)'),
          ('/salesman/new-summary', 'New Summary'),
          ('/salesman/summaries', 'My Summaries'),
          ('/salesman/sales', 'Sales'),
          ('/salesman/stock', 'Stock'),
        ];
      case UserRole.deliveryman:
        return const [
          (null, 'Dashboard (default)'),
          ('/delivery/deliveries', 'Deliveries'),
          ('/delivery/history', 'History'),
        ];
    }
  }

  // ----------------------------------------------------------- notifications
  Widget _notifications(UserPreferences prefs) {
    final controller = ref.read(preferencesProvider.notifier);
    final role = ref.watch(authControllerProvider).valueOrNull?.role;

    return _Section(
      title: 'Notifications',
      caption: 'What reaches the bell in the top bar.',
      icon: Icons.notifications_outlined,
      child: Column(
        children: [
          // Owners hear about every order; a delivery man hears about the
          // orders he will be loading.
          if (role == UserRole.owner || role == UserRole.deliveryman)
            _Toggle(
              title: role == UserRole.owner
                  ? 'Order booked, changed or cancelled'
                  : 'An order you will deliver changed',
              caption: role == UserRole.owner
                  ? 'When a salesman books, edits or cancels an order — or a delivery '
                      'man adds products to one in the field.'
                  : 'When a salesman books, changes or cancels an order for your route, '
                      'so you know before you load the van.',
              value: prefs.notifyOrderChanges,
              onChanged: (v) => _apply(
                () => controller.setNotify(orderChanges: v),
                v ? 'You will be told' : 'Turned off',
              ),
            ),
          if (role == UserRole.owner)
            _Toggle(
              title: 'Round awaiting approval',
              caption: 'When a delivery man finishes a round and it needs your approval.',
              value: prefs.notifyAwaitingApproval,
              onChanged: (v) => _apply(
                () => controller.setNotify(awaitingApproval: v),
                v ? 'You will be told' : 'Turned off',
              ),
            ),
          _Toggle(
            title: 'Report sent back',
            caption: 'When a delivery report is rejected and needs redoing.',
            value: prefs.notifyRejected,
            onChanged: (v) => _apply(
              () => controller.setNotify(rejected: v),
              v ? 'You will be told' : 'Turned off',
            ),
          ),
          _Toggle(
            title: 'Round approved',
            caption: 'When a delivery is approved and its profit is counted.',
            value: prefs.notifyApproved,
            onChanged: (v) => _apply(
              () => controller.setNotify(approved: v),
              v ? 'You will be told' : 'Turned off',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showChangePasswordDialog() async {
    final current = TextEditingController();
    final next = TextEditingController();
    final again = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var obscure = true;
    var busy = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) {
          InputDecoration box(String label) => InputDecoration(
                labelText: label,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18),
                  tooltip: obscure ? 'Show' : 'Hide',
                  onPressed: () => setLocal(() => obscure = !obscure),
                ),
              );

          return AlertDialog(
            title: const Text('Change password'),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: current,
                      obscureText: obscure,
                      decoration: box('Current password'),
                      validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: next,
                      obscureText: obscure,
                      decoration: box('New password'),
                      validator: (v) => (v == null || v.length < 6) ? 'At least 6 characters' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: again,
                      obscureText: obscure,
                      decoration: box('New password again'),
                      validator: (v) => v != next.text ? 'The two do not match' : null,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) return;
                        setLocal(() => busy = true);
                        try {
                          await ref.read(insforgeClientProvider).rpc('change_my_password', {
                            'p_current': current.text,
                            'p_new': next.text,
                          });
                          if (context.mounted) Navigator.pop(context);
                          _toast('Password changed');
                        } catch (e) {
                          setLocal(() => busy = false);
                          _toast(_clean(e), bad: true);
                        }
                      },
                child: busy
                    ? const SizedBox(height: 17, width: 17, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Change'),
              ),
            ],
          );
        },
      ),
    );

    current.dispose();
    next.dispose();
    again.dispose();
  }

  // ---------------------------------------------------------------- account
  Widget _account(Profile profile) {
    final companies = ref.watch(companiesProvider).valueOrNull ?? const <Company>[];
    final company = Company.findById(companies, profile.companyId);

    return _Section(
      title: 'Your account',
      caption: 'Set by the owner — ask them if any of this is wrong.',
      icon: Icons.lock_outline,
      child: Column(
        children: [
          _ReadRow(label: 'Role', value: _roleLabel(profile.role)),
          if (profile.role == UserRole.salesman)
            _ReadRow(label: 'Company', value: company?.name ?? 'Not assigned yet'),
          _ReadRow(label: 'Status', value: profile.isActive ? 'Active' : 'Not active'),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: _showChangePasswordDialog,
            icon: const Icon(Icons.lock_reset, size: 17),
            label: const Text('Change password'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
          ),
        ],
      ),
    );
  }

  static String _roleLabel(UserRole role) {
    switch (role) {
      case UserRole.owner:
        return 'Owner';
      case UserRole.salesman:
        return 'Salesman';
      case UserRole.deliveryman:
        return 'Delivery Man';
    }
  }
}

// ----------------------------------------------------------------- widgets

class _Header extends StatelessWidget {
  const _Header({required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 27,
              backgroundColor: scheme.primary,
              child: Text(
                profile.name.isNotEmpty ? profile.name[0].toUpperCase() : '?',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: scheme.onPrimary),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.name,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    profile.mobile ?? profile.email ?? '',
                    style: const TextStyle(fontSize: 12.5, color: VizChrome.secondaryInk),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.caption,
    required this.icon,
    required this.child,
    this.trailing,
  });

  final String title;
  final String caption;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 17, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                      Text(caption, style: const TextStyle(fontSize: 11.5, color: VizChrome.secondaryInk)),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: VizChrome.secondaryInk),
      ),
    );
  }
}

class _ReadRow extends StatelessWidget {
  const _ReadRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(label, style: const TextStyle(fontSize: 12.5, color: VizChrome.secondaryInk)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.title,
    required this.caption,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String caption;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      title: Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
      subtitle: Text(caption, style: const TextStyle(fontSize: 11.5)),
      contentPadding: EdgeInsets.zero,
      dense: true,
    );
  }
}

class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({required this.accent, required this.selected, required this.onTap});

  final AppAccent accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: accent.label,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: accent.seed,
            border: Border.all(
              color: selected ? Theme.of(context).colorScheme.onSurface : Colors.transparent,
              width: 2.5,
            ),
          ),
          child: selected ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
        ),
      ),
    );
  }
}

/// A radio-style option that carries a caption, without the deprecated
/// RadioListTile group API.
class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.label,
    required this.caption,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String caption;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 19,
              color: selected ? scheme.primary : VizChrome.muted,
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: selected ? scheme.primary : null,
                    ),
                  ),
                  Text(caption, style: const TextStyle(fontSize: 11.5, color: VizChrome.secondaryInk)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
