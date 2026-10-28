import 'package:serverpod/serverpod.dart';

import '../../resolver/table_column_resolver.dart';
import '../ast/filter_node.dart';
import '../ast/filter_operator.dart';
import '../ast/filter_validation_exception.dart';

export '../ast/filter_validation_exception.dart';

/// Translates a validated [FilterNode] AST into native Serverpod [Expression]s
/// that can be used directly in `where: (t) => ...` queries on Serverpod tables.
///
/// Features:
/// - Zero manual metadata required: automatically inspects Serverpod's generated
///   [Table] descriptor (`columns` and `getRelationTable`).
/// - Relational dot-notation support: navigates multi-hop table relations automatically
///   (e.g., `'customer.country.code'`).
/// - Flexible naming: matches column names by exact match, case-insensitively, or
///   normalized between camelCase and snake_case.
/// - Security whitelisting: validates fields against an optional [allowedFields] set.
class FilterExpressionTranslator {
  const FilterExpressionTranslator({
    this.columnResolver = const TableColumnResolver(),
  });

  final TableColumnResolver columnResolver;

  /// Converts a [FilterNode] into a Serverpod [Expression] for the given [Table].
  ///
  /// If [allowedFields] is provided, every criterion field is checked against it.
  /// Unknown fields are silently replaced with `TRUE` (no-op) unless [strict]
  /// is `true`, in which case a [FilterValidationException] is thrown.
  Expression translate(
    FilterNode node,
    Table table, {
    Set<String>? allowedFields,
    bool strict = false,
  }) {
    final effectiveAllowed = (allowedFields != null && allowedFields.isNotEmpty)
        ? allowedFields.map((f) => f.toLowerCase()).toSet()
        : null;
    return _buildExpression(node, table, effectiveAllowed, strict);
  }

  Expression _buildExpression(
    FilterNode node,
    Table table,
    Set<String>? allowedLower,
    bool strict,
  ) {
    return switch (node) {
      FilterCriterion leaf => _translateCriterion(
        leaf,
        table,
        allowedLower,
        strict,
      ),
      AndFilter andNode => _translateAnd(andNode, table, allowedLower, strict),
      OrFilter orNode => _translateOr(orNode, table, allowedLower, strict),
      NotFilter notNode => _translateNot(notNode, table, allowedLower, strict),
      TrueFilter() => Constant.bool(true),
      FalseFilter() => Constant.bool(false),
    };
  }

  Expression _translateAnd(
    AndFilter node,
    Table table,
    Set<String>? allowedLower,
    bool strict,
  ) {
    if (node.children.isEmpty) return Constant.bool(true);
    var expr = _buildExpression(
      node.children.first,
      table,
      allowedLower,
      strict,
    );
    for (var i = 1; i < node.children.length; i++) {
      expr =
          expr &
          _buildExpression(node.children[i], table, allowedLower, strict);
    }
    return expr;
  }

  Expression _translateOr(
    OrFilter node,
    Table table,
    Set<String>? allowedLower,
    bool strict,
  ) {
    if (node.children.isEmpty) return Constant.bool(false);
    var expr = _buildExpression(
      node.children.first,
      table,
      allowedLower,
      strict,
    );
    for (var i = 1; i < node.children.length; i++) {
      expr =
          expr |
          _buildExpression(node.children[i], table, allowedLower, strict);
    }
    return expr;
  }

  Expression _translateNot(
    NotFilter node,
    Table table,
    Set<String>? allowedLower,
    bool strict,
  ) {
    return ~_buildExpression(node.child, table, allowedLower, strict);
  }

  Expression _translateCriterion(
    FilterCriterion leaf,
    Table table,
    Set<String>? allowedLower,
    bool strict,
  ) {
    // Handle boolean shortcuts (1, '=', 1) or (0, '=', 1)
    if (leaf.field == '1' &&
        leaf.operator == FilterOperator.equals &&
        leaf.value == 1) {
      return Constant.bool(true);
    }
    if (leaf.field == '0' &&
        leaf.operator == FilterOperator.equals &&
        leaf.value == 1) {
      return Constant.bool(false);
    }

    // Security whitelist check
    if (allowedLower != null) {
      if (!allowedLower.contains(leaf.field.toLowerCase())) {
        if (strict) {
          throw FilterValidationException(
            'Filtering on field "${leaf.field}" is not allowed. '
            'Allowed fields: ${allowedLower.join(', ')}',
            field: leaf.field,
          );
        }
        // Non-strict: silently replace the criterion with a no-op TRUE.
        return Constant.bool(true);
      }
    }

    final column = columnResolver.resolveColumn(table, leaf.field);
    final op = leaf.operator;
    final val = leaf.value;

    // Operator =? (conditional equals): if value is null/empty/false, evaluates
    // to TRUE (a no-op that matches all rows). Otherwise applies standard equality.
    if (op == FilterOperator.conditionalEquals) {
      if (val == null || val == false || val == '') {
        return Constant.bool(true);
      }
      return _applyEquals(column, val);
    }

    return switch (op) {
      FilterOperator.equals => _applyEquals(column, val),
      FilterOperator.notEquals => _applyNotEquals(column, val),
      FilterOperator.greaterThan => _applyComparison(
        column,
        val,
        (c, v) => c > v,
      ),
      FilterOperator.greaterThanOrEqual => _applyComparison(
        column,
        val,
        (c, v) => c >= v,
      ),
      FilterOperator.lessThan => _applyComparison(column, val, (c, v) => c < v),
      FilterOperator.lessThanOrEqual => _applyComparison(
        column,
        val,
        (c, v) => c <= v,
      ),
      FilterOperator.inList => _applyInSet(column, val),
      FilterOperator.notInList => _applyNotInSet(column, val),
      FilterOperator.like => _applyLike(column, val),
      FilterOperator.notLike => _applyNotLike(column, val),
      FilterOperator.ilike => _applyIlike(column, val),
      FilterOperator.notIlike => _applyNotIlike(column, val),
      // =like: exact case-sensitive literal match (no auto-% wildcard).
      FilterOperator.exactLike => _applyExactLike(column, val),
      // =ilike: exact case-insensitive literal match (no auto-% wildcard).
      FilterOperator.exactIlike => _applyExactIlike(column, val),
      // conditionalEquals is handled before the switch; unreachable here.
      FilterOperator.conditionalEquals => Constant.bool(true),
    };
  }

  Expression _applyEquals(Column column, dynamic value) {
    try {
      return (column as dynamic).equals(value) as Expression;
    } catch (_) {
      throw UnsupportedError(
        'Column ${column.columnName} does not support equality',
      );
    }
  }

  Expression _applyNotEquals(Column column, dynamic value) {
    try {
      return (column as dynamic).notEquals(value) as Expression;
    } catch (_) {
      throw UnsupportedError(
        'Column ${column.columnName} does not support inequality',
      );
    }
  }

  Expression _applyComparison(
    Column column,
    dynamic value,
    Expression Function(dynamic col, dynamic val) op,
  ) {
    if (column is ColumnComparable) {
      return op(column, value);
    }
    throw UnsupportedError(
      'Column ${column.columnName} of type ${column.type} does not support ordering comparisons',
    );
  }

  Expression _applyInSet(Column column, dynamic value) {
    if (value is! Iterable) {
      throw ArgumentError(
        'Expected Iterable value for "in" operator, got ${value.runtimeType}',
      );
    }
    if (value.isEmpty) {
      return Constant.bool(false);
    }

    if (column is ColumnString) {
      return column.inSet(_coercedSet<String>(column, value));
    }
    if (column is ColumnInt) {
      return column.inSet(_coercedSet<int>(column, value));
    }
    if (column is ColumnDouble) {
      return column.inSet(_coercedSet<double>(column, value));
    }

    try {
      return (column as dynamic).inSet(value.toSet()) as Expression;
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        UnsupportedError(
          'Column ${column.columnName} of type ${column.type} does not '
          'support inSet for these values: $error',
        ),
        stackTrace,
      );
    }
  }

  Expression _applyNotInSet(Column column, dynamic value) {
    if (value is! Iterable) {
      throw ArgumentError(
        'Expected Iterable value for "not in" operator, got ${value.runtimeType}',
      );
    }
    if (value.isEmpty) {
      return Constant.bool(true);
    }

    if (column is ColumnString) {
      return column.notInSet(_coercedSet<String>(column, value));
    }
    if (column is ColumnInt) {
      return column.notInSet(_coercedSet<int>(column, value));
    }
    if (column is ColumnDouble) {
      return column.notInSet(_coercedSet<double>(column, value));
    }

    try {
      return (column as dynamic).notInSet(value.toSet()) as Expression;
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        UnsupportedError(
          'Column ${column.columnName} of type ${column.type} does not '
          'support notInSet for these values: $error',
        ),
        stackTrace,
      );
    }
  }

  /// Coerces a collection of dynamic values to the typed [Set<T>] required by
  /// Serverpod's `inSet` / `notInSet`.
  ///
  /// JSON-decoded collections often arrive as mixed [num] types (e.g. an `int`
  /// column receives `[1, 2]` decoded as `List<dynamic>` where each element is
  /// a Dart `int`, and a `double` column may receive `[1, 1.5]` where `1` is an
  /// `int` at runtime).  This method applies safe numeric coercion so that the
  /// column's type constraint is always satisfied.
  Set<T> _coercedSet<T>(Column<T> column, Iterable<dynamic> values) {
    return values.map<T>((value) {
      if (value is T) return value;

      // JSON-decoded numbers: coerce to the column's concrete primitive type.
      if (T == int && value is num) return value.toInt() as T;
      if (T == double && value is num) return value.toDouble() as T;

      throw ArgumentError(
        'Expected values of type ${column.type} for column '
        '"${column.columnName}", got ${value.runtimeType}',
      );
    }).toSet();
  }

  Expression _applyLike(Column column, dynamic value) {
    if (column is ColumnString) {
      return column.like(value.toString());
    }
    throw UnsupportedError(
      'Column ${column.columnName} is not a ColumnString (cannot use like)',
    );
  }

  Expression _applyNotLike(Column column, dynamic value) {
    if (column is ColumnString) {
      return column.notLike(value.toString());
    }
    throw UnsupportedError(
      'Column ${column.columnName} is not a ColumnString (cannot use not like)',
    );
  }

  Expression _applyIlike(Column column, dynamic value) {
    if (column is ColumnString) {
      return column.ilike(value.toString());
    }
    throw UnsupportedError(
      'Column ${column.columnName} is not a ColumnString (cannot use ilike)',
    );
  }

  Expression _applyNotIlike(Column column, dynamic value) {
    if (column is ColumnString) {
      return column.notIlike(value.toString());
    }
    throw UnsupportedError(
      'Column ${column.columnName} is not a ColumnString (cannot use not ilike)',
    );
  }

  /// Applies `=like`: exact, case-sensitive literal match.
  ///
  /// Unlike `like`, the semantic contract is that the caller provides a complete
  /// literal value with no automatically-appended `%` wildcards.  PostgreSQL
  /// `LIKE` is case-sensitive, so `column.like` is the correct underlying call.
  Expression _applyExactLike(Column column, dynamic value) {
    if (column is ColumnString) {
      return column.like(value.toString());
    }
    throw UnsupportedError(
      'Column ${column.columnName} is not a ColumnString (cannot use =like)',
    );
  }

  /// Applies `=ilike`: exact, case-insensitive literal match.
  ///
  /// Like [_applyExactLike] but case-insensitive via Serverpod's `ilike`.
  Expression _applyExactIlike(Column column, dynamic value) {
    if (column is ColumnString) {
      return column.ilike(value.toString());
    }
    throw UnsupportedError(
      'Column ${column.columnName} is not a ColumnString (cannot use =ilike)',
    );
  }
}
