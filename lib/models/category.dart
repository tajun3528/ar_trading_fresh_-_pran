class Category {
  Category({required this.id, required this.name, required this.isActive, required this.companyId});

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id'] as String,
      name: json['name'] as String,
      isActive: json['is_active'] as bool,
      companyId: json['company_id'] as String,
    );
  }

  final String id;
  final String name;
  final bool isActive;
  final String companyId;
}
