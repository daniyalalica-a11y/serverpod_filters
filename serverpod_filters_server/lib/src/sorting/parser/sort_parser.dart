import 'dart:convert';

import '../ast/sort_criterion.dart';
import '../ast/sort_direction.dart';
import '../ast/sort_specification.dart';
import 'sort_parse_exception.dart';

/// High-performance parser that transforms diverse client sorting formats
/// into a validated [SortSpecification].
///
/// Supported input formats:
/// - **Strings:**
///   - Simple: `'name'`
///   - Prefixed: `'-createdAt'` (desc), `'+createdAt'` (asc)
///   - Suffix: `'name desc'`, `'name asc'`, `'name ASC'`, `'name DESC'`
///   - Delimited: `'name:desc'`, `'name:asc'`, `'name/desc'`
///   - Multi-column comma-separated: `'-createdAt, name:asc, customer.country.name:desc'`
/// - **Lists:**
///   - List of strings: `['name', '-amount', 'customer.country.name']`
///   - 2-element tuples: `['name', 'desc']`, `['amount', -1]`, `['state', false]`
///   - Nested lists of tuples: `[['name', 'asc'], ['amount', 'desc']]`
/// - **Maps / JSON Objects:**
///   - Criterion maps: `{'field': 'name', 'direction': 'desc'}`
///   - DevExtreme format: `{'selector': 'name', 'desc': true}`
///   - AG Grid format: `{'colId': 'name', 'sort': 'asc'}`
///   - TanStack Table / React Table format: `{'id': 'name', 'desc': true}`
///   - Column descriptor: `{'column': 'name', 'descending': true}`
///   - Key-value dictionary: `{'name': 'asc', 'amount': 'desc'}`
///   - List of maps: `[{'field': 'name', 'order': 'asc'}, {'field': 'amount', 'order': 'desc'}]`
/// - **JSON Strings:**
///   - Serialized JSON of any of the above formats.
class SortParser {
  const SortParser();

  static final RegExp _validFieldPattern = RegExp(
    r'^[a-zA-Z_][a-zA-Z0-9_]*(\.[a-zA-Z_][a-zA-Z0-9_]*)*$',
  );

  /// Parses a raw sort input into a validated [SortSpecification].
  SortSpecification parse(dynamic rawSort) {
    if (rawSort == null) return const SortSpecification.empty();
    if (rawSort is SortSpecification) return rawSort;
    if (rawSort is SortCriterion) return SortSpecification([rawSort]);

    if (rawSort is String) {
      final trimmed = rawSort.trim();
      if (trimmed.isEmpty || trimmed == '[]' || trimmed == '{}') {
        return const SortSpecification.empty();
      }

      // Check if it's a JSON string
      if (trimmed.startsWith('[') ||
          trimmed.startsWith('{') ||
          trimmed.startsWith('"')) {
        try {
          final decoded = jsonDecode(trimmed);
          return parse(decoded);
        } catch (_) {
          // If not valid JSON, fall back to string parsing
        }
      }

      return _parseString(trimmed);
    }

    if (rawSort is List) {
      return _parseList(rawSort);
    }

    if (rawSort is Iterable) {
      return _parseList(rawSort.toList(growable: false));
    }

    if (rawSort is Map) {
      return _parseMap(rawSort);
    }

    throw SortParseException(
      'Unsupported sort format of type ${rawSort.runtimeType}',
      input: rawSort,
    );
  }

  SortSpecification _parseString(String input) {
    // Check for comma-separated compound sort: "name asc, -amount, customer.country.code:desc"
    if (input.contains(',')) {
      final segments = input.split(',');
      final criteria = <SortCriterion>[];
      for (var i = 0; i < segments.length; i++) {
        final seg = segments[i].trim();
        if (seg.isEmpty) continue;
        criteria.add(_parseSingleStringSegment(seg, index: i));
      }
      return SortSpecification(criteria);
    }

    return SortSpecification([_parseSingleStringSegment(input)]);
  }

  SortCriterion _parseSingleStringSegment(String segment, {int? index}) {
    var str = segment.trim();
    if (str.isEmpty) {
      throw SortParseException(
        'Empty sort field segment',
        input: segment,
        index: index,
      );
    }

    // Check prefix notation: -field (desc) or +field (asc)
    if (str.startsWith('-')) {
      final field = str.substring(1).trim();
      _validateField(field, input: segment, index: index);
      return SortCriterion(field, SortDirection.descending);
    }
    if (str.startsWith('+')) {
      final field = str.substring(1).trim();
      _validateField(field, input: segment, index: index);
      return SortCriterion(field, SortDirection.ascending);
    }

    // Check colon or slash delimiter: field:desc or field/asc
    final colonIdx = str.indexOf(':');
    final slashIdx = str.indexOf('/');
    final delimIdx = colonIdx != -1 ? colonIdx : slashIdx;
    if (delimIdx != -1) {
      final field = str.substring(0, delimIdx).trim();
      final dirStr = str.substring(delimIdx + 1).trim();
      _validateField(field, input: segment, index: index);
      final direction = _parseDirection(dirStr, input: segment, index: index);
      return SortCriterion(field, direction);
    }

    // Check whitespace separation: "name desc" or "name ASC"
    final parts = str.split(RegExp(r'\s+'));
    if (parts.length == 2) {
      final field = parts[0].trim();
      final dirStr = parts[1].trim();
      _validateField(field, input: segment, index: index);
      final direction = _parseDirection(dirStr, input: segment, index: index);
      return SortCriterion(field, direction);
    } else if (parts.length > 2) {
      throw SortParseException(
        'Invalid sort segment syntax: "$segment"',
        input: segment,
        index: index,
      );
    }

    // Default simple field: ascending
    _validateField(str, input: segment, index: index);
    return SortCriterion(str, SortDirection.ascending);
  }

  SortSpecification _parseList(List<dynamic> list) {
    if (list.isEmpty) return const SortSpecification.empty();

    // Check if this list itself represents a single 2-element tuple: [field, direction]
    // e.g. ['name', 'desc'] or ['amount', -1] or ['state', true]
    if (list.length == 2 && list[0] is String) {
      final first = (list[0] as String).trim();
      final second = list[1];
      if (_isDirectionValue(second)) {
        _validateField(first, input: list);
        final dir = _parseDirection(second, input: list);
        return SortSpecification([SortCriterion(first, dir)]);
      }
    }

    // Otherwise, treat as a list of sort criteria
    final criteria = <SortCriterion>[];
    for (var i = 0; i < list.length; i++) {
      final item = list[i];
      if (item == null) continue;

      if (item is SortCriterion) {
        criteria.add(item);
      } else if (item is String) {
        criteria.add(_parseSingleStringSegment(item, index: i));
      } else if (item is List) {
        if (item.isEmpty) continue;
        if (item.length >= 2 && item[0] is String) {
          final field = (item[0] as String).trim();
          _validateField(field, input: item, index: i);
          final dir = _parseDirection(item[1], input: item, index: i);
          criteria.add(SortCriterion(field, dir));
        } else if (item.length == 1 && item[0] is String) {
          criteria.add(_parseSingleStringSegment(item[0] as String, index: i));
        } else {
          throw SortParseException(
            'Invalid sort item list: $item',
            input: item,
            index: i,
          );
        }
      } else if (item is Map) {
        criteria.addAll(_parseMap(item).criteria);
      } else {
        throw SortParseException(
          'Unsupported sort element type: ${item.runtimeType}',
          input: item,
          index: i,
        );
      }
    }

    return SortSpecification(criteria);
  }

  SortSpecification _parseMap(Map<dynamic, dynamic> map) {
    if (map.isEmpty) return const SortSpecification.empty();

    // Check for standard single criterion map keys:
    // field / selector / column / colId / id / name / key
    final fieldVal =
        map['field'] ??
        map['selector'] ??
        map['column'] ??
        map['colId'] ??
        map['id'] ??
        map['name'] ??
        map['key'];

    if (fieldVal != null && fieldVal is String) {
      final field = fieldVal.trim();
      _validateField(field, input: map);

      SortDirection direction = SortDirection.ascending;

      if (map.containsKey('desc')) {
        direction = map['desc'] == true
            ? SortDirection.descending
            : SortDirection.ascending;
      } else if (map.containsKey('descending')) {
        direction = map['descending'] == true
            ? SortDirection.descending
            : SortDirection.ascending;
      } else if (map.containsKey('isDescending')) {
        direction = map['isDescending'] == true
            ? SortDirection.descending
            : SortDirection.ascending;
      } else if (map.containsKey('asc')) {
        direction = map['asc'] == true
            ? SortDirection.ascending
            : SortDirection.descending;
      } else if (map.containsKey('ascending')) {
        direction = map['ascending'] == true
            ? SortDirection.ascending
            : SortDirection.descending;
      } else if (map.containsKey('direction')) {
        direction = _parseDirection(map['direction'], input: map);
      } else if (map.containsKey('order')) {
        direction = _parseDirection(map['order'], input: map);
      } else if (map.containsKey('sort')) {
        direction = _parseDirection(map['sort'], input: map);
      }

      return SortSpecification([SortCriterion(field, direction)]);
    }

    // Otherwise, treat as key-value map: {'name': 'asc', 'amount': 'desc'}
    final criteria = <SortCriterion>[];
    for (final entry in map.entries) {
      final key = entry.key?.toString().trim();
      if (key == null || key.isEmpty) continue;
      _validateField(key, input: map);
      final dir = _parseDirection(entry.value, input: map);
      criteria.add(SortCriterion(key, dir));
    }

    return SortSpecification(criteria);
  }

  bool _isDirectionValue(dynamic val) {
    if (val is SortDirection || val is bool) return true;
    if (val is num && (val == 1 || val == -1)) return true;
    if (val is String) {
      final s = val.trim().toLowerCase();
      return s == 'asc' ||
          s == 'desc' ||
          s == 'ascending' ||
          s == 'descending' ||
          s == '+' ||
          s == '-';
    }
    return false;
  }

  SortDirection _parseDirection(dynamic val, {dynamic input, int? index}) {
    try {
      return SortDirection.parse(val);
    } catch (_) {
      throw SortParseException(
        'Invalid sort direction: "$val"',
        input: input,
        index: index,
      );
    }
  }

  void _validateField(String field, {dynamic input, int? index}) {
    if (!_validFieldPattern.hasMatch(field)) {
      throw SortParseException(
        'Invalid sort field format: "$field". '
        'Field names must be valid identifiers or dot-separated paths (e.g. "name", "customer.country.code")',
        input: input,
        index: index,
      );
    }
  }
}
