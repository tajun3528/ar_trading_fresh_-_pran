import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

/// Mix into any ConsumerState that loads its own data (`late Future<...>
/// _future` + a `_load()`/`_reload()` pair) to have it automatically refetch
/// whenever *any* write happens anywhere in the app.
///
/// This matters because several screens are kept alive in memory by the
/// router (StatefulShellRoute's bottom-nav tabs, and any screen sitting under
/// a pushed detail route) — without this, saving something on one screen
/// would leave other already-built screens showing stale data until a full
/// page reload.
mixin AutoRefreshMixin<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  /// Reload this screen's data. Usually just `setState(() { _future = _load(); });`
  void refreshData();

  void _onDataChanged() {
    if (mounted) refreshData();
  }

  // Captured in initState — `ref` is not safe to use in dispose() (Riverpod
  // invalidates it for this element before dispose runs, especially when a
  // whole subtree unmounts at once, e.g. a router redirect swapping shells).
  // Reading it fresh in dispose() threw here, and since the throw happened
  // before removeListener ran, the listener was never actually removed —
  // every disposed screen leaked a permanent listener on this app-wide
  // notifier. Storing the notifier itself sidesteps `ref` entirely.
  late final ValueNotifier<int> _dataVersion;

  @override
  void initState() {
    super.initState();
    _dataVersion = ref.read(insforgeClientProvider).dataVersion;
    _dataVersion.addListener(_onDataChanged);
  }

  @override
  void dispose() {
    _dataVersion.removeListener(_onDataChanged);
    super.dispose();
  }
}
