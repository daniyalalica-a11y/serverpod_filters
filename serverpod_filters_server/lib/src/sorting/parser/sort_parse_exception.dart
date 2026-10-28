/// Exception thrown when sort syntax or format is malformed.
class SortParseException implements Exception {
  SortParseException(this.message, {this.input, this.index});

  final String message;
  final dynamic input;
  final int? index;

  @override
  String toString() {
    final buffer = StringBuffer('SortParseException: $message');
    if (index != null) buffer.write(' at index $index');
    if (input != null) buffer.write(' (input: $input)');
    return buffer.toString();
  }
}

/// Exception thrown when a sort field violates whitelist security rules.
class SortValidationException implements Exception {
  SortValidationException(this.message, {this.field});

  final String message;
  final String? field;

  @override
  String toString() => 'SortValidationException: $message';
}
