import 'dart:collection';

import '../parser/sort_parse_exception.dart';
import 'sort_criterion.dart';

/// Represents a validated, compound sorting specification comprising one or
/// more [SortCriterion] items applied in order of priority.
class SortSpecification with IterableMixin<SortCriterion> {
  /// Creates a sort specification from a list of [criteria].
  const SortSpecification(this.criteria);

  /// Creates an empty sort specification.
  const SortSpecification.empty() : criteria = const [];

  /// The list of sort criteria ordered by precedence.
  final List<SortCriterion> criteria;

  @override
  Iterator<SortCriterion> get iterator => criteria.iterator;

  @override
  bool get isEmpty => criteria.isEmpty;

  @override
  bool get isNotEmpty => criteria.isNotEmpty;

  @override
  int get length => criteria.length;

  /// Checks if a criterion exists for the given [field] (case-insensitively).
  bool hasField(String field) {
    final lower = field.toLowerCase();
    return criteria.any((c) => c.field.toLowerCase() == lower);
  }

  /// Finds the first [SortCriterion] for [field] (case-insensitively), or null if none.
  SortCriterion? findCriterion(String field) {
    final lower = field.toLowerCase();
    for (final c in criteria) {
      if (c.field.toLowerCase() == lower) return c;
    }
    return null;
  }

  /// Inverts the sorting direction of all criteria.
  SortSpecification reversed() =>
      SortSpecification(criteria.map((c) => c.reversed()).toList());

  /// Returns a new [SortSpecification] containing only criteria whose fields
  /// match the [allowedFields] whitelist.
  ///
  /// If [strict] is `true` and any criterion targets a field not in [allowedFields],
  /// a [SortValidationException] is thrown.
  SortSpecification filterAllowed(
    Set<String> allowedFields, {
    bool strict = false,
  }) {
    final allowedLower = allowedFields.map((f) => f.toLowerCase()).toSet();
    final filtered = <SortCriterion>[];

    for (final c in criteria) {
      if (allowedLower.contains(c.field.toLowerCase())) {
        filtered.add(c);
      } else if (strict) {
        throw SortValidationException(
          'Sorting on field "${c.field}" is not allowed. '
          'Allowed fields: ${allowedFields.join(', ')}',
          field: c.field,
        );
      }
    }

    return SortSpecification(filtered);
  }

  /// Returns a new [SortSpecification] where field names are remapped according
  /// to [fieldMap] (e.g. `{'clientName': 'customer.name'}`).
  SortSpecification withFieldMap(Map<String, String> fieldMap) {
    if (fieldMap.isEmpty) return this;

    final remapped = criteria.map((c) {
      final mappedField =
          fieldMap[c.field] ?? fieldMap[c.field.toLowerCase()] ?? c.field;
      return SortCriterion(mappedField, c.direction);
    }).toList();

    return SortSpecification(remapped);
  }

  /// Serializes criteria to a list of standard JSON maps.
  List<Map<String, dynamic>> toJson() =>
      criteria.map((c) => c.toJson()).toList();

  @override
  String toString() {
    if (criteria.isEmpty) return 'SortSpecification(empty)';
    return 'SortSpecification(${criteria.map((c) => c.toString()).join(', ')})';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SortSpecification) return false;
    if (criteria.length != other.criteria.length) return false;
    for (var i = 0; i < criteria.length; i++) {
      if (criteria[i] != other.criteria[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(criteria);
}
