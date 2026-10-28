import 'package:serverpod/serverpod.dart';

import 'ast/sort_specification.dart';
import 'parser/sort_parser.dart';
import 'translator/sort_expression_translator.dart';

export 'ast/sort_criterion.dart';
export 'ast/sort_direction.dart';
export 'ast/sort_specification.dart';
export 'parser/sort_parse_exception.dart';
export 'parser/sort_parser.dart';
export 'translator/sort_expression_translator.dart';

/// Top-level facade for parsing and compiling client sort specifications into
/// native Serverpod [OrderByListBuilder] callbacks and [Order] expressions.
///
/// Features:
/// - **Zero Manual Metadata:** Resolves columns and multi-hop relation tables
///   (`'customer.country.name'`) directly from Serverpod [Table] descriptors.
/// - **Every Client Format:** Supports strings (`'-name'`, `'name:desc'`, `'name, -age'`),
///   lists (`['name', 'desc']`, `[['name', 'asc'], ['age', 'desc']]`),
///   maps (DevExtreme, AG Grid, TanStack Table, key-value dictionaries),
///   and JSON strings.
/// - **Security & Whitelisting:** Validates fields against an optional `allowedFields` set.
/// - **Field Remapping:** Translates custom client fields to database paths via `fieldMap`.
/// - **Default Fallbacks:** Automatically applies `defaultSort` when no client sort is provided.
class ServerpodSorting {
  ServerpodSorting._();

  static const SortParser _parser = SortParser();
  static const SortExpressionTranslator _translator =
      SortExpressionTranslator();

  /// Parses raw sort input into a validated [SortSpecification].
  static SortSpecification parse(dynamic rawSort) => _parser.parse(rawSort);

  /// Translates sort input into a list of Serverpod [Order] objects for [table].
  ///
  /// If [rawSort] resolves to an empty specification and [defaultSort] is provided,
  /// [defaultSort] is evaluated instead.
  static List<Order> toOrderByList<T extends Table>(
    dynamic rawSort,
    T table, {
    dynamic defaultSort,
    Set<String>? allowedFields,
    Map<String, String>? fieldMap,
    bool strict = false,
  }) {
    var spec = parse(rawSort);
    if (spec.isEmpty && defaultSort != null) {
      spec = parse(defaultSort);
    }

    return _translator.translate(
      spec,
      table,
      allowedFields: allowedFields,
      fieldMap: fieldMap,
      strict: strict,
    );
  }

  /// Returns an [OrderByListBuilder] callback that can be passed directly to
  /// `orderByList:` in Serverpod's `find`, `findFirstRow`, and `deleteWhere`.
  ///
  /// Returns `null` if the resolved sort specification is empty and no [defaultSort]
  /// is provided. This allows clean fallback chaining using `??`:
  /// ```dart
  /// final orders = await Order.db.find(
  ///   session,
  ///   orderByList: ServerpodSorting.orderByList(sort) ?? ((t) => [t.id.desc()]),
  /// );
  /// ```
  static OrderByListBuilder<T>? orderByList<T extends Table>(
    dynamic rawSort, {
    dynamic defaultSort,
    Set<String>? allowedFields,
    Map<String, String>? fieldMap,
    bool strict = false,
  }) {
    final spec = parse(rawSort);
    final fallbackSpec = (spec.isEmpty && defaultSort != null)
        ? parse(defaultSort)
        : null;

    if (spec.isEmpty && (fallbackSpec == null || fallbackSpec.isEmpty)) {
      return null;
    }

    final effectiveSpec = spec.isNotEmpty ? spec : fallbackSpec!;

    return (T table) => _translator.translate(
      effectiveSpec,
      table,
      allowedFields: allowedFields,
      fieldMap: fieldMap,
      strict: strict,
    );
  }

  /// Convenient alias for [orderByList].
  static OrderByListBuilder<T>? orderBy<T extends Table>(
    dynamic rawSort, {
    dynamic defaultSort,
    Set<String>? allowedFields,
    Map<String, String>? fieldMap,
    bool strict = false,
  }) => orderByList<T>(
    rawSort,
    defaultSort: defaultSort,
    allowedFields: allowedFields,
    fieldMap: fieldMap,
    strict: strict,
  );
}

/// Alias for [ServerpodSorting].
typedef SortEngine = ServerpodSorting;
