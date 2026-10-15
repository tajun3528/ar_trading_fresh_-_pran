import 'unit_type.dart';

/// Stock is tracked per (product, unit type) — pieces, jars, and cartons are
/// independent counts, none derived from another.
class Stock {
  Stock({
    required this.productId,
    required this.unitType,
    required this.availableQty,
    required this.damagedQty,
  });

  factory Stock.fromJson(Map<String, dynamic> json) {
    return Stock(
      productId: json['product_id'] as String,
      unitType: UnitType.parse(json['unit_type'] as String),
      availableQty: json['available_qty'] as int,
      damagedQty: json['damaged_qty'] as int,
    );
  }

  final String productId;
  final UnitType unitType;
  final int availableQty;
  final int damagedQty;
}

class StockIn {
  StockIn({
    required this.id,
    required this.productId,
    required this.unitType,
    required this.quantity,
    required this.entryDate,
    required this.enteredBy,
  });

  factory StockIn.fromJson(Map<String, dynamic> json) {
    return StockIn(
      id: json['id'] as String,
      productId: json['product_id'] as String,
      unitType: UnitType.parse(json['unit_type'] as String),
      quantity: json['quantity'] as int,
      entryDate: DateTime.parse(json['entry_date'] as String),
      enteredBy: json['entered_by'] as String,
    );
  }

  final String id;
  final String productId;
  final UnitType unitType;
  final int quantity;
  final DateTime entryDate;
  final String enteredBy;
}
