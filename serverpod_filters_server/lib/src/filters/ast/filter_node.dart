import 'filter_operator.dart';

/// Explicit reference to another database column used as a filter value.
///
/// JSON filters can represent this as `{'field': 'user.companyId'}`.
final class FilterColumnReference {
  const FilterColumnReference(this.field);

  final String field;

  @override
  String toString() => 'column($field)';

  @override
  bool operator ==(Object other) =>
      other is FilterColumnReference && field == other.field;

  @override
  int get hashCode => field.hashCode;
}

/// Visitor pattern interface for traversing and transforming the filter AST.
abstract interface class FilterVisitor<R, C> {
  R visitCriterion(FilterCriterion criterion, C context);
  R visitAnd(AndFilter andFilter, C context);
  R visitOr(OrFilter orFilter, C context);
  R visitNot(NotFilter notFilter, C context);
  R visitTrue(TrueFilter trueFilter, C context);
  R visitFalse(FalseFilter falseFilter, C context);
}

/// Abstract base class for all nodes in a filter AST.
sealed class FilterNode {
  const FilterNode();

  /// Accepts a [FilterVisitor] to perform operations or transformations.
  R accept<R, C>(FilterVisitor<R, C> visitor, C context);

  /// Recursively simplifies tautologies and double negatives.
  FilterNode simplify();

  /// Returns all criteria leaves in this sub-tree.
  List<FilterCriterion> get criteria;

  /// Whether this node represents a constant truth condition.
  bool get isAlwaysTrue => false;

  /// Whether this node represents a constant false condition.
  bool get isAlwaysFalse => false;
}

/// A leaf criterion representing a field condition (e.g. `['customer.name', 'ilike', 'Acme']`).
final class FilterCriterion extends FilterNode {
  const FilterCriterion({
    required this.field,
    required this.operator,
    required this.value,
  });

  /// The field path (simple like `'status'` or relational dot-notation like `'customer.country.code'`).
  final String field;

  /// The comparison operator.
  final FilterOperator operator;

  /// The operand value.
  final dynamic value;

  /// Returns the dot-separated segments of the field path.
  List<String> get pathSegments => field.split('.');

  /// Whether this criterion navigates across a relational table.
  bool get isRelational => field.contains('.');

  /// The root relation field name (e.g., `'customer'` in `'customer.country.code'`).
  String get rootField => pathSegments.first;

  /// The trailing target column name (e.g., `'code'` in `'customer.country.code'`).
  String get targetField => pathSegments.last;

  @override
  R accept<R, C>(FilterVisitor<R, C> visitor, C context) =>
      visitor.visitCriterion(this, context);

  @override
  FilterNode simplify() => this;

  @override
  List<FilterCriterion> get criteria => [this];

  @override
  String toString() => '[$field, ${operator.symbol}, $value]';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FilterCriterion &&
          field == other.field &&
          operator == other.operator &&
          value == other.value;

  @override
  int get hashCode => Object.hash(field, operator, value);
}

/// Logical AND combinator with one or more child filters.
final class AndFilter extends FilterNode {
  const AndFilter(this.children);

  final List<FilterNode> children;

  @override
  R accept<R, C>(FilterVisitor<R, C> visitor, C context) =>
      visitor.visitAnd(this, context);

  @override
  FilterNode simplify() {
    final simplifiedChildren = <FilterNode>[];
    for (final child in children) {
      final s = child.simplify();
      if (s is FalseFilter) {
        return const FalseFilter();
      }
      if (s is TrueFilter) {
        continue;
      }
      if (s is AndFilter) {
        simplifiedChildren.addAll(s.children);
      } else {
        simplifiedChildren.add(s);
      }
    }

    if (simplifiedChildren.isEmpty) return const TrueFilter();
    if (simplifiedChildren.length == 1) return simplifiedChildren.first;
    return AndFilter(simplifiedChildren);
  }

  @override
  List<FilterCriterion> get criteria =>
      children.expand((child) => child.criteria).toList(growable: false);

  @override
  String toString() => '&(${children.join(', ')})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AndFilter &&
          children.length == other.children.length &&
          const _ListEquality<FilterNode>().equals(children, other.children);

  @override
  int get hashCode => Object.hashAll(children);
}

/// Logical OR combinator with one or more child filters.
final class OrFilter extends FilterNode {
  const OrFilter(this.children);

  final List<FilterNode> children;

  @override
  R accept<R, C>(FilterVisitor<R, C> visitor, C context) =>
      visitor.visitOr(this, context);

  @override
  FilterNode simplify() {
    final simplifiedChildren = <FilterNode>[];
    for (final child in children) {
      final s = child.simplify();
      if (s is TrueFilter) {
        return const TrueFilter();
      }
      if (s is FalseFilter) {
        continue;
      }
      if (s is OrFilter) {
        simplifiedChildren.addAll(s.children);
      } else {
        simplifiedChildren.add(s);
      }
    }

    if (simplifiedChildren.isEmpty) return const FalseFilter();
    if (simplifiedChildren.length == 1) return simplifiedChildren.first;
    return OrFilter(simplifiedChildren);
  }

  @override
  List<FilterCriterion> get criteria =>
      children.expand((child) => child.criteria).toList(growable: false);

  @override
  String toString() => '|(${children.join(', ')})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OrFilter &&
          children.length == other.children.length &&
          const _ListEquality<FilterNode>().equals(children, other.children);

  @override
  int get hashCode => Object.hashAll(children);
}

/// Logical NOT combinator (inverts child filter).
final class NotFilter extends FilterNode {
  const NotFilter(this.child);

  final FilterNode child;

  @override
  R accept<R, C>(FilterVisitor<R, C> visitor, C context) =>
      visitor.visitNot(this, context);

  @override
  FilterNode simplify() {
    final s = child.simplify();
    if (s is TrueFilter) return const FalseFilter();
    if (s is FalseFilter) return const TrueFilter();
    if (s is NotFilter) return s.child; // Double negation elimination
    return NotFilter(s);
  }

  @override
  List<FilterCriterion> get criteria => child.criteria;

  @override
  String toString() => '!($child)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is NotFilter && child == other.child;

  @override
  int get hashCode => child.hashCode ^ 0x55555555;
}

/// Represents an unconditionally true condition (e.g. empty filter `[]`).
final class TrueFilter extends FilterNode {
  const TrueFilter();

  @override
  R accept<R, C>(FilterVisitor<R, C> visitor, C context) =>
      visitor.visitTrue(this, context);

  @override
  FilterNode simplify() => this;

  @override
  List<FilterCriterion> get criteria => const [];

  @override
  bool get isAlwaysTrue => true;

  @override
  String toString() => 'TRUE';

  @override
  bool operator ==(Object other) => other is TrueFilter;

  @override
  int get hashCode => 1;
}

/// Represents an unconditionally false condition.
final class FalseFilter extends FilterNode {
  const FalseFilter();

  @override
  R accept<R, C>(FilterVisitor<R, C> visitor, C context) =>
      visitor.visitFalse(this, context);

  @override
  FilterNode simplify() => this;

  @override
  List<FilterCriterion> get criteria => const [];

  @override
  bool get isAlwaysFalse => true;

  @override
  String toString() => 'FALSE';

  @override
  bool operator ==(Object other) => other is FalseFilter;

  @override
  int get hashCode => 0;
}

class _ListEquality<E> {
  const _ListEquality();

  bool equals(List<E> a, List<E> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
