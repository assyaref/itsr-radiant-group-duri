import 'dart:async';

import 'package:http/http.dart' as http;

/// HTTP client used by the Supabase SDK (PostgREST, Auth, Edge Functions).
///
/// * Every request gets a hard [timeout], so a stalled connection (office
///   Wi-Fi drop, captive portal, overloaded gateway) surfaces as an error the
///   UI can show instead of a spinner that never ends.
/// * Idempotent reads (GET/HEAD) are retried a few times with backoff on
///   network errors, timeouts and transient gateway replies (502/503/504).
///   Writes (POST/PATCH/DELETE) are NEVER retried automatically: a request that
///   timed out may still have been applied on the server, and repeating it
///   could create a duplicate ticket or comment.
class ResilientHttpClient extends http.BaseClient {
  ResilientHttpClient({
    http.Client? inner,
    this.timeout = const Duration(seconds: 30),
    this.maxRetries = 2,
    this.baseDelay = const Duration(milliseconds: 400),
  }) : _inner = inner ?? http.Client();

  final http.Client _inner;
  final Duration timeout;
  final int maxRetries;
  final Duration baseDelay;

  static const _retryStatus = {502, 503, 504};

  static bool isIdempotent(String method) {
    final m = method.toUpperCase();
    return m == 'GET' || m == 'HEAD';
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!isIdempotent(request.method) || maxRetries <= 0) {
      return _sendOnce(request);
    }
    var attempt = 0;
    var current = request;
    while (true) {
      try {
        final response = await _sendOnce(current);
        if (!_retryStatus.contains(response.statusCode) || attempt >= maxRetries) {
          return response;
        }
        // Drain the body so the connection can be reused, then retry.
        await response.stream.drain<void>().catchError((_) {});
      } on TimeoutException {
        if (attempt >= maxRetries) rethrow;
      } on http.ClientException {
        if (attempt >= maxRetries) rethrow;
      }
      attempt++;
      await Future<void>.delayed(baseDelay * attempt);
      current = _copy(request);
    }
  }

  Future<http.StreamedResponse> _sendOnce(http.BaseRequest request) =>
      _inner.send(request).timeout(
            timeout,
            onTimeout: () => throw TimeoutException(
              'Request to ${request.url.path} timed out',
              timeout,
            ),
          );

  /// A BaseRequest can only be sent once; GET/HEAD carry no body, so a copy
  /// with the same method, URL and headers is equivalent.
  static http.Request _copy(http.BaseRequest original) {
    final copy = http.Request(original.method, original.url)
      ..followRedirects = original.followRedirects
      ..maxRedirects = original.maxRedirects
      ..persistentConnection = original.persistentConnection;
    copy.headers.addAll(original.headers);
    return copy;
  }

  @override
  void close() => _inner.close();
}
