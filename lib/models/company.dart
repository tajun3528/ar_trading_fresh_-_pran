enum CompanyCatalogStyle {
  simple,
  tradePricing;

  static CompanyCatalogStyle parse(String value) {
    switch (value) {
      case 'trade_pricing':
        return CompanyCatalogStyle.tradePricing;
      default:
        return CompanyCatalogStyle.simple;
    }
  }
}

/// Which price a company's profit is measured against. Every vendor settles
/// on a different one: Fresh on the ETP they publish each month, Pran on the
/// After Trade TP from their sheet.
enum CompanyCostBasis {
  dp('DP'),
  afterTradeTp('After Trade TP'),
  etp('ETP');

  const CompanyCostBasis(this.label);

  final String label;

  static CompanyCostBasis parse(String? value) {
    switch (value) {
      case 'etp':
        return CompanyCostBasis.etp;
      case 'after_trade_tp':
        return CompanyCostBasis.afterTradeTp;
      default:
        return CompanyCostBasis.dp;
    }
  }
}

/// The vendor/brand a product catalog belongs to (e.g. Fresh, Pran
/// Chocolate). [catalogStyle] picks which product-detail/order
/// representation the app renders for this company's products.
class Company {
  Company({
    required this.id,
    required this.name,
    required this.catalogStyle,
    required this.costBasis,
    required this.isActive,
  });

  factory Company.fromJson(Map<String, dynamic> json) {
    return Company(
      id: json['id'] as String,
      name: json['name'] as String,
      catalogStyle: CompanyCatalogStyle.parse(json['catalog_style'] as String),
      costBasis: CompanyCostBasis.parse(json['cost_basis'] as String?),
      isActive: json['is_active'] as bool,
    );
  }

  final String id;
  final String name;
  final CompanyCatalogStyle catalogStyle;
  final CompanyCostBasis costBasis;
  final bool isActive;

  static Company? findById(List<Company> companies, String? id) {
    if (id == null) return null;
    for (final c in companies) {
      if (c.id == id) return c;
    }
    return null;
  }
}
