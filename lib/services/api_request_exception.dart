/// A failed HTTP response, without retaining credentials or response content.
class ApiRequestException implements Exception {
  final int statusCode;

  const ApiRequestException(this.statusCode);

  @override
  String toString() => 'ApiRequestException(status=$statusCode)';
}
