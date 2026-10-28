import 'sort_direction.dart';

/// Represents a single sort criterion (a field and an ordering direction).
///
/// Supports simple fields (`'amount'`), prefixed fields (`'-createdAt'`),
/// and multi-hop relational paths (`'customer.country.name'`).
class SortCriterion {
  /// Creates a sort criterion for [field] with optional [direction] (defaults to ascending).
  const SortCriterion(this.field, [this.direction = SortDirection.ascending]);

  /// The field path (e.g. `'name'` or `'customer.country.code'`).
  final String field;

  /// The sort direction (ascending or descending).
  final SortDirection direction;

  /// Whether this criterion sorts across a relational table.
  bool get isRelational => field.contains('.');

  /// The dot-separated segments of the field path.
  List<String> get pathSegments => field.split('.');

  /// The root relation field name (e.g. `'customer'` in `'customer.country.code'`).
  String get rootField => pathSegments.first;

  /// The trailing target column name (e.g. `'code'` in `'customer.country.code'`).
  String get targetField => pathSegments.last;

  /// Whether this criterion is sorted in ascending order.
  bool get isAscending => direction.isAscending;

  /// Whether this criterion is sorted in descending order.
  bool get isDescending => direction.isDescending;

  /// Returns a new [SortCriterion] with inverted direction.
  SortCriterion reversed() => SortCriterion(field, direction.reversed());

  /// Serializes to a standard JSON-compatible Map.
  Map<String, dynamic> toJson() => {
    'field': field,
    'direction': direction.name,
  };

  @override
  String toString() => '$field ${direction.sql}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SortCriterion &&
          field == other.field &&
          direction == other.direction;

  @override
  int get hashCode => Object.hash(field, direction);
}
