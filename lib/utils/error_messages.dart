import 'package:supabase_flutter/supabase_flutter.dart';

/// Typed failures surfaced to the UI.
class AppFailure implements Exception {
  final String message;
  const AppFailure(this.message);
  @override
  String toString() => message;
}

class InvalidCredentials extends AppFailure {
  const InvalidCredentials()
      : super('Authentication failed. Please check your credentials.');
}

class RateLimited extends AppFailure {
  const RateLimited()
      : super('Too many login attempts. Please try again in 15 minutes.');
}

/// Converts any error into a message that is safe and useful to show users.
/// Database trigger messages are written for end users, so they are passed
/// through; anything unexpected becomes a generic message (no internals leak).
String friendlyError(Object error) {
  if (error is AppFailure) return error.message;
  if (error is PostgrestException) {
    switch (error.code) {
      case '42501':
        return 'You do not have permission to perform this action.';
      case '23505':
        return 'This record already exists.';
      case '22023':
      case '23514':
      case 'P0002':
        return error.message;
      case 'PGRST116':
        return 'The requested item was not found or you do not have access to it.';
    }
    return 'The server rejected the request. Please try again.';
  }
  if (error is FunctionException) {
    final details = error.details;
    if (details is Map && details['error'] is String) {
      return details['error'] as String;
    }
    return 'The server could not complete the request (${error.status}).';
  }
  if (error is AuthException) {
    return 'Your session has expired. Please sign in again.';
  }
  final text = error.toString();
  if (text.contains('SocketException') ||
      text.contains('ClientException') ||
      text.contains('Failed to fetch')) {
    return 'Cannot reach the server. Check your connection and try again.';
  }
  return 'Something went wrong. Please try again.';
}
