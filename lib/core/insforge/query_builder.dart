import 'insforge_client.dart';

/// A small subset of PostgREST's filter/query grammar — just what this app
/// needs (equality-style filters, ordering, pagination, CRUD). InsForge's
/// `/api/database/records/{table}` endpoint speaks real PostgREST, so this
/// stays wire-compatible with the full syntax if more is needed later.
class QueryBuilder {
  QueryBuilder(this._client, this._table);

  final InsforgeClient _client;
  final String _table;
  String _select = '*';
  final Map<String, String> _filters = {};
  String? _order;
  int? _limit;
  int? _offset;

  QueryBuilder select([String columns = '*']) {
    _select = columns;
    return this;
  }

  QueryBuilder eq(String column, Object value) => _filter(column, 'eq', value);
  QueryBuilder neq(String column, Object value) => _filter(column, 'neq', value);
  QueryBuilder gt(String column, Object value) => _filter(column, 'gt', value);
  QueryBuilder gte(String column, Object value) => _filter(column, 'gte', value);
  QueryBuilder lt(String column, Object value) => _filter(column, 'lt', value);
  QueryBuilder lte(String column, Object value) => _filter(column, 'lte', value);
  QueryBuilder like(String column, String pattern) => _filter(column, 'like', pattern);
  QueryBuilder ilike(String column, String pattern) => _filter(column, 'ilike', pattern);
  QueryBuilder isFilter(String column, String value) => _filter(column, 'is', value);

  QueryBuilder inList(String column, List<Object> values) {
    _filters[column] = 'in.(${values.join(',')})';
    return this;
  }

  QueryBuilder order(String column, {bool ascending = true}) {
    _order = '$column.${ascending ? 'asc' : 'desc'}';
    return this;
  }

  QueryBuilder limit(int count) {
    _limit = count;
    return this;
  }

  QueryBuilder range(int from, int to) {
    _offset = from;
    _limit = to - from + 1;
    return this;
  }

  QueryBuilder _filter(String column, String op, Object value) {
    _filters[column] = '$op.$value';
    return this;
  }

  Map<String, dynamic> _params({required bool includeSelect}) {
    final params = <String, dynamic>{...
        _filters};
    if (includeSelect) params['select'] = _select;
    if (_order != null) params['order'] = _order;
    if (_limit != null) params['limit'] = _limit.toString();
    if (_offset != null) params['offset'] = _offset.toString();
    return params;
  }

  /// Runs the SELECT and returns the matching rows.
  Future<List<Map<String, dynamic>>> get() async {
    final data = await _client.getRecords(_table, _params(includeSelect: true));
    return data;
  }

  /// Runs the SELECT and returns the first row, or null if there are none.
  Future<Map<String, dynamic>?> maybeSingle() async {
    final rows = await limit(1).get();
    return rows.isEmpty ? null : rows.first;
  }

  /// Runs the SELECT and returns the first row, throwing if there are none.
  Future<Map<String, dynamic>> single() async {
    final row = await maybeSingle();
    if (row == null) {
      throw StateError('Expected a row from $_table but found none');
    }
    return row;
  }

  /// Inserts one or more rows and returns the inserted rows.
  Future<List<Map<String, dynamic>>> insert(List<Map<String, dynamic>> rows) {
    return _client.insertRecords(_table, rows);
  }

  /// Updates rows matching the filters already applied on this builder.
  Future<List<Map<String, dynamic>>> update(Map<String, dynamic> patch) {
    return _client.updateRecords(_table, patch, _params(includeSelect: false));
  }

  /// Deletes rows matching the filters already applied on this builder.
  Future<void> delete() {
    return _client.deleteRecords(_table, _params(includeSelect: false));
  }
}
