enum UnitType {
  pcs,
  jar,
  box,
  poli,
  carton;

  static UnitType parse(String value) => UnitType.values.byName(value);

  String get label {
    switch (this) {
      case UnitType.pcs:
        return 'Piece';
      case UnitType.jar:
        return 'Jar';
      case UnitType.box:
        return 'Box';
      case UnitType.poli:
        return 'Poli';
      case UnitType.carton:
        return 'Carton';
    }
  }
}
