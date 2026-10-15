import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/company.dart';
import '../models/sales_route.dart';
import 'insforge/insforge_client.dart';

/// Single shared InsForge client for the whole app.
final insforgeClientProvider = Provider<InsforgeClient>((ref) => InsforgeClient());

/// Every company (vendor) in the system — Fresh, Pran Chocolate, etc. Open
/// to every signed-in user (needed so a salesman's own company name can be
/// shown). Companies change rarely, so screens needing a fresher read after
/// adding one can `ref.invalidate(companiesProvider)`.
final companiesProvider = FutureProvider<List<Company>>((ref) async {
  final client = ref.watch(insforgeClientProvider);
  final rows = await client.from('companies').select().order('name').get();
  return rows.map(Company.fromJson).toList();
});

/// Every sales route (area) the Owner has set up — a simple label a
/// salesman picks when starting a daily summary.
final routesProvider = FutureProvider<List<SalesRoute>>((ref) async {
  final client = ref.watch(insforgeClientProvider);
  final rows = await client.from('routes').select().order('name').get();
  return rows.map(SalesRoute.fromJson).toList();
});
