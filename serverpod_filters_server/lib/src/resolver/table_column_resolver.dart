import 'package:serverpod/serverpod.dart';

/// Shared utility for resolving database columns and relations across
/// Serverpod [Table] descriptors without requiring manual metadata or schemas.
class TableColumnResolver {
  const TableColumnResolver();

  /// Resolves a [Column] from a [rootTable], automatically traversing
  /// multi-hop dot-notation relations (e.g. `'customer.country.code'`).
  Column resolveColumn(Table rootTable, String fieldPath) {
    final segments = fieldPath.split('.');
    var currentTable = rootTable;

    for (var i = 0; i < segments.length - 1; i++) {
      final seg = segments[i];
      final relTable = currentTable.getRelationTable(seg);
      if (relTable == null) {
        throw ArgumentError(
          'Cannot resolve relation "$seg" on table "${currentTable.tableName}". '
          'Ensure the relation is defined in Serverpod .spy.yaml and generated.',
        );
      }
      currentTable = relTable;
    }

    final targetFieldName = segments.last;
    for (final col in currentTable.columns) {
      if (matchesColumn(col, targetFieldName)) {
        return col;
      }
    }

    throw ArgumentError(
      'Column "$targetFieldName" not found on table "${currentTable.tableName}". '
      'Available columns: ${currentTable.columns.map((c) => c.fieldName).join(', ')}',
    );
  }

  /// Matches a [Column] against a requested field name, supporting exact matches,
  /// case-insensitive comparisons, and normalization between camelCase and snake_case.
  bool matchesColumn(Column col, String queryName) {
    if (col.fieldName == queryName || col.columnName == queryName) return true;
    final normQuery = queryName.replaceAll('_', '').toLowerCase();
    final normField = col.fieldName.replaceAll('_', '').toLowerCase();
    final normCol = col.columnName.replaceAll('_', '').toLowerCase();
    return normQuery == normField || normQuery == normCol;
  }
}
