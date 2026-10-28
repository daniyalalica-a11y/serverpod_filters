/// Exception thrown when a filter field violates security whitelist rules.
class FilterValidationException implements Exception {
  FilterValidationException(this.message, {this.field});

  final String message;
  final String? field;

  @override
  String toString() => 'FilterValidationException: $message';
}
