import 'dart:convert';
import '../ast/filter_node.dart';
import '../ast/filter_operator.dart';

/// Exception thrown when filter syntax is malformed or invalid.
class FilterParseException implements Exception {
  FilterParseException(this.message, {this.index, this.element});

  final String message;
  final int? index;
  final dynamic element;

  @override
  String toString() {
    final buffer = StringBuffer('FilterParseException: $message');
    if (index != null) buffer.write(' at index $index');
    if (element != null) buffer.write(' (element: $element)');
    return buffer.toString();
  }
}

/// High-performance parser that transforms serializable filter expressions
/// into a validated Abstract Syntax Tree ([FilterNode]).
///
/// Features:
/// - Prefix Polish notation support (`&`, `|`, `!`).
/// - Implicit `AND` support for sequential criteria without explicit combinators.
/// - Dot-notation relational field validation.
/// - Safe JSON string parsing.
/// - Memory-efficient recursive descent cursor.
class FilterParser {
  const FilterParser();

  static final RegExp _validFieldPattern = RegExp(
    r'^[a-zA-Z_][a-zA-Z0-9_]*(\.[a-zA-Z_][a-zA-Z0-9_]*)*$',
  );

  /// Parses a raw filter object (List, JSON String, or Iterable) into a [FilterNode] AST.
  FilterNode parse(dynamic rawFilter) {
    if (rawFilter == null) {
      return const TrueFilter();
    }

    List<dynamic> tokens;
    if (rawFilter is String) {
      final trimmed = rawFilter.trim();
      if (trimmed.isEmpty || trimmed == '[]') {
        return const TrueFilter();
      }
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is! List) {
          throw FilterParseException(
            'Filter JSON root must be a list, found ${decoded.runtimeType}',
          );
        }
        tokens = decoded;
      } catch (e) {
        if (e is FilterParseException) rethrow;
        throw FilterParseException('Invalid JSON string for filter: $e');
      }
    } else if (rawFilter is List) {
      tokens = rawFilter;
    } else if (rawFilter is Iterable) {
      tokens = rawFilter.toList(growable: false);
    } else {
      throw FilterParseException(
        'Filter must be a List or JSON string, found ${rawFilter.runtimeType}',
      );
    }

    if (tokens.isEmpty) {
      return const TrueFilter();
    }

    // Parse tokens using Polish prefix notation with implicit AND support
    final cursor = _Cursor(tokens);
    final forest = <FilterNode>[];

    while (cursor.hasNext) {
      forest.add(_parseSubtree(cursor));
    }

    if (forest.isEmpty) {
      return const TrueFilter();
    }
    if (forest.length == 1) {
      return forest.first.simplify();
    }

    // Sequence of expressions without an explicit top-level combinator is an implicit AND
    return AndFilter(forest).simplify();
  }

  FilterNode _parseSubtree(_Cursor cursor) {
    final idx = cursor.index;
    final item = cursor.next();

    // Check for logical operators in Polish notation
    if (item is String) {
      final trimmed = item.trim();
      if (trimmed == '&') {
        if (!cursor.hasNext) {
          throw FilterParseException(
            'Prefix operator "&" requires 2 operands, but stream ended',
            index: idx,
            element: item,
          );
        }
        final left = _parseSubtree(cursor);
        if (!cursor.hasNext) {
          throw FilterParseException(
            'Prefix operator "&" requires 2 operands, but second operand is missing',
            index: idx,
            element: item,
          );
        }
        final right = _parseSubtree(cursor);
        return AndFilter([left, right]);
      } else if (trimmed == '|') {
        if (!cursor.hasNext) {
          throw FilterParseException(
            'Prefix operator "|" requires 2 operands, but stream ended',
            index: idx,
            element: item,
          );
        }
        final left = _parseSubtree(cursor);
        if (!cursor.hasNext) {
          throw FilterParseException(
            'Prefix operator "|" requires 2 operands, but second operand is missing',
            index: idx,
            element: item,
          );
        }
        final right = _parseSubtree(cursor);
        return OrFilter([left, right]);
      } else if (trimmed == '!') {
        if (!cursor.hasNext) {
          throw FilterParseException(
            'Prefix operator "!" requires 1 operand, but stream ended',
            index: idx,
            element: item,
          );
        }
        final child = _parseSubtree(cursor);
        return NotFilter(child);
      } else if (trimmed == 'TRUE' || trimmed == '1') {
        return const TrueFilter();
      } else if (trimmed == 'FALSE' || trimmed == '0') {
        return const FalseFilter();
      }
    }

    // Boolean literals
    if (item is bool) {
      return item ? const TrueFilter() : const FalseFilter();
    }

    // Criterion tuple/list: [field, operator, value]
    if (item is List) {
      return _parseCriterion(item, idx);
    }

    throw FilterParseException(
      'Unexpected token in filter: expected criterion list or logical operator',
      index: idx,
      element: item,
    );
  }

  FilterCriterion _parseCriterion(List<dynamic> criterion, int index) {
    if (criterion.length != 3) {
      // Check for boolean shortcut: (1, '=', 1) or (0, '=', 1)
      if (criterion.length == 3 &&
          (criterion[0] == 1 || criterion[0] == 0) &&
          criterion[1] == '=' &&
          criterion[2] == 1) {
        // Handled below
      } else {
        throw FilterParseException(
          'Criterion must be a 3-element list [field, operator, value], found length ${criterion.length}',
          index: index,
          element: criterion,
        );
      }
    }

    final rawField = criterion[0];
    final rawOp = criterion[1];
    final value = criterion[2];

    // Boolean tautology shortcuts: (1, '=', 1) or (0, '=', 1)
    if (rawField == 1 && rawOp == '=' && value == 1) {
      return const FilterCriterion(
        field: '1',
        operator: FilterOperator.equals,
        value: 1,
      );
    }
    if (rawField == 0 && rawOp == '=' && value == 1) {
      return const FilterCriterion(
        field: '0',
        operator: FilterOperator.equals,
        value: 1,
      );
    }

    if (rawField is! String) {
      throw FilterParseException(
        'Criterion field must be a String, found ${rawField.runtimeType}',
        index: index,
        element: criterion,
      );
    }

    final field = rawField.trim();
    if (field.isEmpty) {
      throw FilterParseException(
        'Criterion field cannot be empty',
        index: index,
        element: criterion,
      );
    }

    if (!_validFieldPattern.hasMatch(field)) {
      throw FilterParseException(
        'Invalid field identifier "$field". Field names must consist of alphanumeric characters/underscores and dot notation.',
        index: index,
        element: criterion,
      );
    }

    if (rawOp is! String) {
      throw FilterParseException(
        'Criterion operator must be a String, found ${rawOp.runtimeType}',
        index: index,
        element: criterion,
      );
    }

    final FilterOperator op;
    try {
      op = FilterOperator.fromString(rawOp);
    } catch (_) {
      throw FilterParseException(
        'Unsupported or unknown operator "$rawOp"',
        index: index,
        element: criterion,
      );
    }

    // Validate operator-value semantics
    if (op.isCollection && value is! Iterable && value != null) {
      throw FilterParseException(
        'Operator "${op.symbol}" expects an Iterable or Collection value, found ${value.runtimeType}',
        index: index,
        element: criterion,
      );
    }

    return FilterCriterion(
      field: field,
      operator: op,
      value: value,
    );
  }
}

class _Cursor {
  _Cursor(this._tokens);

  final List<dynamic> _tokens;
  int _index = 0;

  bool get hasNext => _index < _tokens.length;
  int get index => _index;

  dynamic next() {
    if (!hasNext) {
      throw StateError('No more tokens available');
    }
    return _tokens[_index++];
  }
}
