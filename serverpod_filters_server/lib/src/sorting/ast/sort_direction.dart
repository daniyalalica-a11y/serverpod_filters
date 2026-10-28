/// Defines the ordering direction for sorting.
enum SortDirection {
  /// Sort in ascending order (A to Z, 0 to 9, oldest to newest).
  ascending,

  /// Sort in descending order (Z to A, 9 to 0, newest to oldest).
  descending;

  /// Whether this direction is ascending.
  bool get isAscending => this == SortDirection.ascending;

  /// Whether this direction is descending.
  bool get isDescending => this == SortDirection.descending;

  /// SQL keyword for this direction (`ASC` or `DESC`).
  String get sql => isAscending ? 'ASC' : 'DESC';

  /// Prefix symbol convention (`+` or `-`).
  String get symbol => isAscending ? '+' : '-';

  /// Returns the inverted direction.
  SortDirection reversed() =>
      isAscending ? SortDirection.descending : SortDirection.ascending;

  /// Parses a value into a [SortDirection].
  ///
  /// Supports:
  /// - `SortDirection` enum instances directly.
  /// - Strings: `'asc'`, `'ascending'`, `'+'`, `'up'` -> [SortDirection.ascending].
  /// - Strings: `'desc'`, `'descending'`, `'-'`, `'down'` -> [SortDirection.descending].
  /// - Booleans: `true` -> [SortDirection.descending] (when flag represents `descending`),
  ///   `false` -> [SortDirection.ascending].
  /// - Numbers: negative (< 0) -> [SortDirection.descending], non-negative (>= 0) -> [SortDirection.ascending].
  static SortDirection parse(dynamic value) {
    if (value == null) return SortDirection.ascending;
    if (value is SortDirection) return value;
    if (value is bool) {
      return value ? SortDirection.descending : SortDirection.ascending;
    }
    if (value is num) {
      return value < 0 ? SortDirection.descending : SortDirection.ascending;
    }
    if (value is String) {
      final s = value.trim().toLowerCase();
      if (s == 'desc' || s == 'descending' || s == '-' || s == 'down') {
        return SortDirection.descending;
      }
      if (s == 'asc' || s == 'ascending' || s == '+' || s == 'up') {
        return SortDirection.ascending;
      }
    }
    throw FormatException('Invalid sort direction: "$value"');
  }
}
