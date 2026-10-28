import 'package:serverpod/serverpod.dart';

import '../../resolver/table_column_resolver.dart';
import '../ast/sort_direction.dart';
import '../ast/sort_specification.dart';

/// Translates a validated [SortSpecification] AST into native Serverpod [Order] objects
/// that can be used directly in `orderByList:` queries.
///
/// Features:
/// - Zero manual metadata required: automatically inspects Serverpod's generated
///   [Table] descriptor (`columns` and `getRelationTable`).
/// - Multi-hop relational dot notation: resolves relation tables dynamically
///   (e.g., `'customer.country.name'`).
/// - Column name normalization: matches camelCase and snake_case seamlessly.
/// - Security whitelisting: verifies fields against an optional [allowedFields] set.
/// - Field remapping: translates client field names using an optional [fieldMap].
class SortExpressionTranslator {
  const SortExpressionTranslator({
    this.columnResolver = const TableColumnResolver(),
  });

  final TableColumnResolver columnResolver;

  /// Translates [spec] into a list of Serverpod [Order] objects for [table].
  List<Order> translate(
    SortSpecification spec,
    Table table, {
    Set<String>? allowedFields,
    Map<String, String>? fieldMap,
    bool strict = false,
  }) {
    var effectiveSpec = spec;

    if (fieldMap != null && fieldMap.isNotEmpty) {
      effectiveSpec = effectiveSpec.withFieldMap(fieldMap);
    }

    if (allowedFields != null && allowedFields.isNotEmpty) {
      effectiveSpec = effectiveSpec.filterAllowed(
        allowedFields,
        strict: strict,
      );
    }

    final orders = <Order>[];

    for (final criterion in effectiveSpec.criteria) {
      final column = columnResolver.resolveColumn(table, criterion.field);

      final order = switch (criterion.direction) {
        SortDirection.ascending => column.asc(),
        SortDirection.descending => column.desc(),
      };

      orders.add(order);
    }

    return orders;
  }
}
