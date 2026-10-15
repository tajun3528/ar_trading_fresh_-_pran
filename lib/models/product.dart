import 'unit_type.dart';

class Product {
  Product({
    required this.id,
    required this.name,
    required this.categoryId,
    required this.companyId,
    this.description,
    required this.isActive,
    required this.lowStockThreshold,
    this.pcsPerCarton,
    this.poliPerCarton,
    this.jarPerCarton,
    this.boxPerCarton,
    this.itemCode,
    this.factor,
    this.dpPrice,
    this.tpPrice,
    this.mrpPrice,
    this.skuQty,
    this.tradeQty,
    this.jarBoxSize,
    this.afterTradeDpPrice,
    this.afterTradeTpPrice,
    this.perPcsDpPrice,
    this.perPcsTpPrice,
    this.mrpPricePerPcs,
    this.tradeNote,
    this.soNote,
    this.ermPercent,
    this.etpPerCarton,
    this.etpPerPcs,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'] as String,
      name: json['name'] as String,
      categoryId: json['category_id'] as String,
      companyId: json['company_id'] as String,
      description: json['description'] as String?,
      isActive: json['is_active'] as bool,
      lowStockThreshold: json['low_stock_threshold'] as int,
      pcsPerCarton: json['pcs_per_carton'] as int?,
      poliPerCarton: json['poli_per_carton'] as int?,
      jarPerCarton: json['jar_per_carton'] as int?,
      boxPerCarton: json['box_per_carton'] as int?,
      itemCode: json['item_code'] as String?,
      factor: json['factor'] as int?,
      dpPrice: (json['dp_price'] as num?)?.toDouble(),
      tpPrice: (json['tp_price'] as num?)?.toDouble(),
      mrpPrice: (json['mrp_price'] as num?)?.toDouble(),
      skuQty: json['sku_qty'] as int?,
      tradeQty: json['trade_qty'] as int?,
      jarBoxSize: json['jar_box_size'] as int?,
      afterTradeDpPrice: (json['after_trade_dp_price'] as num?)?.toDouble(),
      afterTradeTpPrice: (json['after_trade_tp_price'] as num?)?.toDouble(),
      perPcsDpPrice: (json['per_pcs_dp_price'] as num?)?.toDouble(),
      perPcsTpPrice: (json['per_pcs_tp_price'] as num?)?.toDouble(),
      mrpPricePerPcs: (json['mrp_price_per_pcs'] as num?)?.toDouble(),
      tradeNote: json['trade_note'] as String?,
      soNote: json['so_note'] as String?,
      ermPercent: (json['erm_percent'] as num?)?.toDouble(),
      etpPerCarton: (json['etp_per_carton'] as num?)?.toDouble(),
      etpPerPcs: (json['etp_per_pcs'] as num?)?.toDouble(),
    );
  }

  final String id;
  final String name;
  final String categoryId;
  final String companyId;
  final String? description;
  // Optional — only set for products where loose pieces/poli should
  // automatically roll up into full cartons on stock-in or order (see
  // stock_in() and _apply_summary_item()). Null means no rollup for that
  // unit; a product can have either, both, or neither set.
  final int? pcsPerCarton;
  final int? poliPerCarton;
  /// The company's effective trade price — what profit is measured against
  /// for an ETP-basis company. Superseded month by month in
  /// product_monthly_etp; this is the original sheet figure.
  final double? etpPerCarton;
  final double? etpPerPcs;
  final int? jarPerCarton;
  final int? boxPerCarton;
  final bool isActive;
  final int lowStockThreshold;

  // Vendor price-list reference fields — populated whenever the Owner has
  // imported a vendor price sheet for this product's company (Fresh and
  // Pran Chocolate both have one, with different column shapes; a company
  // could have none). Read-only reference data for the Owner;
  // product_units.price (fetched separately) remains the one authoritative,
  // editable selling price used by orders.
  final String? itemCode;
  final int? factor;
  final double? dpPrice;
  final double? tpPrice;
  final double? mrpPrice;
  final int? skuQty;
  final int? tradeQty;
  final int? jarBoxSize;
  final double? afterTradeDpPrice;
  final double? afterTradeTpPrice;
  final double? perPcsDpPrice;
  final double? perPcsTpPrice;
  final double? mrpPricePerPcs;
  final String? tradeNote;
  final String? soNote;
  final double? ermPercent;

  /// Whether this product carries any vendor price-sheet reference data at
  /// all — drives whether Product Detail shows the reference card.
  bool get hasVendorReferenceData =>
      itemCode != null ||
      factor != null ||
      dpPrice != null ||
      mrpPrice != null ||
      skuQty != null ||
      tradeQty != null ||
      jarBoxSize != null ||
      afterTradeDpPrice != null ||
      afterTradeTpPrice != null ||
      perPcsDpPrice != null ||
      perPcsTpPrice != null ||
      mrpPricePerPcs != null ||
      tradeNote != null ||
      soNote != null ||
      ermPercent != null;

  static const _unset = Object();

  /// The per-carton counts can legitimately be cleared to null (the Product
  /// Detail screen's "leave blank" option) — pass them explicitly (including
  /// `null`) to change one; omit to leave it untouched.
  Product copyWith({
    bool? isActive,
    Object? pcsPerCarton = _unset,
    Object? poliPerCarton = _unset,
    Object? jarPerCarton = _unset,
    Object? boxPerCarton = _unset,
  }) {
    return Product(
      id: id,
      name: name,
      categoryId: categoryId,
      companyId: companyId,
      description: description,
      isActive: isActive ?? this.isActive,
      lowStockThreshold: lowStockThreshold,
      pcsPerCarton: identical(pcsPerCarton, _unset) ? this.pcsPerCarton : pcsPerCarton as int?,
      poliPerCarton: identical(poliPerCarton, _unset) ? this.poliPerCarton : poliPerCarton as int?,
      jarPerCarton: identical(jarPerCarton, _unset) ? this.jarPerCarton : jarPerCarton as int?,
      boxPerCarton: identical(boxPerCarton, _unset) ? this.boxPerCarton : boxPerCarton as int?,
      itemCode: itemCode,
      factor: factor,
      dpPrice: dpPrice,
      tpPrice: tpPrice,
      mrpPrice: mrpPrice,
      skuQty: skuQty,
      tradeQty: tradeQty,
      jarBoxSize: jarBoxSize,
      afterTradeDpPrice: afterTradeDpPrice,
      afterTradeTpPrice: afterTradeTpPrice,
      perPcsDpPrice: perPcsDpPrice,
      perPcsTpPrice: perPcsTpPrice,
      mrpPricePerPcs: mrpPricePerPcs,
      tradeNote: tradeNote,
      soNote: soNote,
      ermPercent: ermPercent,
      etpPerCarton: etpPerCarton,
      etpPerPcs: etpPerPcs,
    );
  }
}

class ProductUnit {
  ProductUnit({required this.id, required this.productId, required this.unitType, required this.price});

  factory ProductUnit.fromJson(Map<String, dynamic> json) {
    return ProductUnit(
      id: json['id'] as String,
      productId: json['product_id'] as String,
      unitType: UnitType.parse(json['unit_type'] as String),
      price: (json['price'] as num).toDouble(),
    );
  }

  final String id;
  final String productId;
  final UnitType unitType;
  final double price;
}

/// One row per product per unit type that has ever been stocked — pieces,
/// jars, and cartons are independent stock counts, none derived from another.
class ProductStock {
  ProductStock({
    required this.productId,
    required this.name,
    required this.categoryId,
    required this.lowStockThreshold,
    required this.unitType,
    required this.availableQty,
    required this.damagedQty,
    required this.isLowStock,
    required this.companyId,
  });

  factory ProductStock.fromJson(Map<String, dynamic> json) {
    return ProductStock(
      productId: json['product_id'] as String,
      name: json['name'] as String,
      categoryId: json['category_id'] as String,
      lowStockThreshold: json['low_stock_threshold'] as int,
      unitType: UnitType.parse(json['unit_type'] as String),
      availableQty: json['available_qty'] as int,
      damagedQty: json['damaged_qty'] as int,
      isLowStock: json['is_low_stock'] as bool,
      companyId: json['company_id'] as String,
    );
  }

  final String productId;
  final String name;
  final String categoryId;
  final int lowStockThreshold;
  final UnitType unitType;
  final int availableQty;
  final int damagedQty;
  final bool isLowStock;
  final String companyId;
}
