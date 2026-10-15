/// An area a salesman travels — a simple Owner-maintained label attached to
/// a daily summary, not a full territory/shop system. Named `SalesRoute`
/// (not `Route`) to avoid colliding with Flutter's own routing `Route` class.
class SalesRoute {
  SalesRoute({required this.id, required this.name, required this.isActive});

  factory SalesRoute.fromJson(Map<String, dynamic> json) {
    return SalesRoute(
      id: json['id'] as String,
      name: json['name'] as String,
      isActive: json['is_active'] as bool,
    );
  }

  final String id;
  final String name;
  final bool isActive;
}
