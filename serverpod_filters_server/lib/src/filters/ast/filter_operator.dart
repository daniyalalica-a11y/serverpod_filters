/// Supported comparison and collection operators in filter expressions.
enum FilterOperator {
  equals('='),
  notEquals('!='),
  greaterThan('>'),
  greaterThanOrEqual('>='),
  lessThan('<'),
  lessThanOrEqual('<='),
  inList('in'),
  notInList('not in'),
  like('like'),
  notLike('not like'),
  ilike('ilike'),
  notIlike('not ilike'),
  exactLike('=like'),
  exactIlike('=ilike'),
  conditionalEquals('=?');

  const FilterOperator(this.symbol);

  /// String symbol representing the operator.
  final String symbol;

  /// Whether the operator checks equality or inequality.
  bool get isEquality =>
      this == FilterOperator.equals ||
      this == FilterOperator.notEquals ||
      this == FilterOperator.conditionalEquals;

  /// Whether the operator checks ordering (<, <=, >, >=).
  bool get isComparison =>
      this == FilterOperator.greaterThan ||
      this == FilterOperator.greaterThanOrEqual ||
      this == FilterOperator.lessThan ||
      this == FilterOperator.lessThanOrEqual;

  /// Whether the operator is a pattern matching operator (like, ilike, etc.).
  bool get isPatternMatching =>
      this == FilterOperator.like ||
      this == FilterOperator.notLike ||
      this == FilterOperator.ilike ||
      this == FilterOperator.notIlike ||
      this == FilterOperator.exactLike ||
      this == FilterOperator.exactIlike;

  /// Whether the operator checks collection membership (in, not in).
  bool get isCollection =>
      this == FilterOperator.inList || this == FilterOperator.notInList;

  /// Parses an operator string into a [FilterOperator].
  ///
  /// Throws [ArgumentError] if the operator string is unknown.
  static FilterOperator fromString(String op) {
    final normalized = op.trim().toLowerCase();
    switch (normalized) {
      case '=':
      case '==':
        return FilterOperator.equals;
      case '!=':
      case '<>':
        return FilterOperator.notEquals;
      case '>':
        return FilterOperator.greaterThan;
      case '>=':
        return FilterOperator.greaterThanOrEqual;
      case '<':
        return FilterOperator.lessThan;
      case '<=':
        return FilterOperator.lessThanOrEqual;
      case 'in':
        return FilterOperator.inList;
      case 'not in':
      case 'not_in':
        return FilterOperator.notInList;
      case 'like':
        return FilterOperator.like;
      case 'not like':
      case 'not_like':
        return FilterOperator.notLike;
      case 'ilike':
        return FilterOperator.ilike;
      case 'not ilike':
      case 'not_ilike':
        return FilterOperator.notIlike;
      case '=like':
        return FilterOperator.exactLike;
      case '=ilike':
        return FilterOperator.exactIlike;
      case '=?':
        return FilterOperator.conditionalEquals;
      default:
        throw ArgumentError.value(
          op,
          'operator',
          'Unsupported or unknown filter operator: "$op"',
        );
    }
  }
}
