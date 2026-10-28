import 'package:serverpod/serverpod.dart';

import '../sorting/serverpod_sorting.dart';
import 'ast/filter_node.dart';
import 'parser/filter_parser.dart';
import 'translator/filter_expression_translator.dart';

export '../sorting/serverpod_sorting.dart';
export 'ast/filter_node.dart';
export 'ast/filter_operator.dart';
export 'ast/filter_validation_exception.dart';
export 'parser/filter_parser.dart';
export 'translator/filter_expression_translator.dart';

/// Top-level facade for parsing and compiling filter expressions and sorting
/// specifications into native Serverpod ORM expressions and callbacks.
///
/// Features:
/// - Pure Serverpod ORM: produces native [Expression]s for `where: (t) => ...`
///   and [OrderByListBuilder] callbacks for `orderByList: (t) => ...`.
/// - Zero manual metadata: automatically resolves columns and multi-hop
///   relational paths (`customer.country.code`) from Serverpod [Table] descriptors.
/// - Advanced filtering: prefix Polish notation (`&`, `|`, `!`), implicit sequential `AND`s,
///   null equality, pattern matching (`like`, `ilike`), and conditional equals (`=?`).
/// - Advanced sorting: multi-field sorting, directional prefixes (`-`/`+`), suffixes (`asc`/`desc`),
///   DevExtreme/AG-Grid/TanStack maps, whitelisting, and field remapping.
/// - Security whitelisting: [allowedFields] and [strict] on both filter and sort helpers
///   prevent clients from probing sensitive columns.
class ServerpodFilters {
  ServerpodFilters._();

  static const FilterParser _parser = FilterParser();
  static const FilterExpressionTranslator _translator =
      FilterExpressionTranslator();

  /// Parses a raw filter list or JSON string into a validated [FilterNode] AST.
  static FilterNode parse(dynamic rawFilter) => _parser.parse(rawFilter);

  /// Converts a filter expression directly into a Serverpod [Expression]
  /// for the specified [table].
  ///
  /// If [allowedFields] is provided, criteria targeting unlisted fields are
  /// silently treated as `TRUE` (no-op). Set [strict] to `true` to throw a
  /// [FilterValidationException] instead.
  ///
  /// Example:
  /// ```dart
  /// final orders = await Order.db.find(
  ///   session,
  ///   where: (t) => ServerpodFilters.toWhere(filter, t,
  ///     allowedFields: {'state', 'amount', 'customer.name'},
  ///   ),
  /// );
  /// ```
  static Expression toWhere<T extends Table>(
    dynamic rawFilter,
    T table, {
    Set<String>? allowedFields,
    bool strict = false,
  }) {
    final ast = parse(rawFilter);
    return _translator.translate(
      ast,
      table,
      allowedFields: allowedFields,
      strict: strict,
    );
  }

  /// Returns a [WhereExpressionBuilder] callback that can be passed directly
  /// to `where:` in Serverpod's `find`, `findFirstRow`, `count`, and `deleteWhere`.
  ///
  /// If [allowedFields] is provided, criteria targeting unlisted fields are
  /// silently treated as `TRUE` (no-op). Set [strict] to `true` to throw a
  /// [FilterValidationException] instead.
  ///
  /// Example:
  /// ```dart
  /// final orders = await Order.db.find(
  ///   session,
  ///   where: ServerpodFilters.where(filter,
  ///     allowedFields: {'state', 'amount', 'customer.name'},
  ///   ),
  /// );
  /// ```
  static WhereExpressionBuilder<T> where<T extends Table>(
    dynamic rawFilter, {
    Set<String>? allowedFields,
    bool strict = false,
  }) {
    return (T t) =>
        toWhere(rawFilter, t, allowedFields: allowedFields, strict: strict);
  }

  /// Parses raw sort input into a validated [SortSpecification].
  static SortSpecification parseSort(dynamic rawSort) =>
      ServerpodSorting.parse(rawSort);

  /// Translates sort input into a list of Serverpod [Order] objects for [table].
  static List<Order> toOrderByList<T extends Table>(
    dynamic rawSort,
    T table, {
    dynamic defaultSort,
    Set<String>? allowedFields,
    Map<String, String>? fieldMap,
    bool strict = false,
  }) => ServerpodSorting.toOrderByList(
    rawSort,
    table,
    defaultSort: defaultSort,
    allowedFields: allowedFields,
    fieldMap: fieldMap,
    strict: strict,
  );

  /// Returns an [OrderByListBuilder] callback that can be passed directly to
  /// `orderByList:` in Serverpod's `find`, `findFirstRow`, and `deleteWhere`.
  ///
  /// Returns `null` if the resolved sort specification is empty and no
  /// [defaultSort] is provided. This allows clean fallback chaining using `??`:
  /// ```dart
  /// final orders = await Order.db.find(
  ///   session,
  ///   where: ServerpodFilters.where(filter),
  ///   orderByList: ServerpodFilters.orderByList(sort) ?? ((t) => [t.id.desc()]),
  /// );
  /// ```
  static OrderByListBuilder<T>? orderByList<T extends Table>(
    dynamic rawSort, {
    dynamic defaultSort,
    Set<String>? allowedFields,
    Map<String, String>? fieldMap,
    bool strict = false,
  }) => ServerpodSorting.orderByList(
    rawSort,
    defaultSort: defaultSort,
    allowedFields: allowedFields,
    fieldMap: fieldMap,
    strict: strict,
  );

  /// Convenient alias for [orderByList].
  static OrderByListBuilder<T>? orderBy<T extends Table>(
    dynamic rawSort, {
    dynamic defaultSort,
    Set<String>? allowedFields,
    Map<String, String>? fieldMap,
    bool strict = false,
  }) => ServerpodSorting.orderBy(
    rawSort,
    defaultSort: defaultSort,
    allowedFields: allowedFields,
    fieldMap: fieldMap,
    strict: strict,
  );
}

/// Alias for [ServerpodFilters].
typedef FilterEngine = ServerpodFilters;
