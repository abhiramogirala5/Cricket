/// Base type for every error the UI is expected to handle.
sealed class AppException implements Exception {
  const AppException(this.message);

  /// Technical message (safe to log; contains no secrets).
  final String message;

  /// Short, friendly text that can be shown to the user.
  String get userMessage => message;

  @override
  String toString() => '$runtimeType: $message';
}

/// An error response from the backend (see docs/API_CONTRACT.md §1.1).
final class ApiException extends AppException {
  const ApiException({
    required this.code,
    required String message,
    this.statusCode,
    this.details,
    this.requestId,
    this.retryAfter,
  }) : super(message);

  final String code;
  final int? statusCode;
  final List<Object?>? details;
  final String? requestId;

  /// From the `Retry-After` header of a `429` response.
  final Duration? retryAfter;

  bool get isTokenExpired => code == 'TOKEN_EXPIRED';
  bool get isUnauthorized => statusCode == 401;
  bool get isServerError => (statusCode ?? 0) >= 500;
  bool get isRateLimited => code == 'RATE_LIMITED';

  @override
  String get userMessage {
    switch (code) {
      case 'INVALID_CREDENTIALS':
        return 'Incorrect email or password.';
      case 'EMAIL_ALREADY_REGISTERED':
        return 'An account with this email already exists. Try signing in instead.';
      case 'RATE_LIMITED':
        return 'Too many attempts. Please wait a minute and try again.';
      case 'VALIDATION_ERROR':
        return 'Please check the details you entered.';
      case 'ACCOUNT_DISABLED':
        return 'This account has been disabled.';
      case 'PASSWORD_INCORRECT':
        return 'That password is not correct.';
      case 'INVALID_REFRESH_TOKEN':
      case 'NOT_AUTHENTICATED':
      case 'INVALID_TOKEN':
        return 'Your session has expired. Please sign in again.';
      default:
        if (isServerError) {
          return 'The server had a problem. Please try again in a moment.';
        }
        return message.isNotEmpty ? message : 'Something went wrong. Please try again.';
    }
  }
}

/// The device is offline, timed out, or the server could not be reached.
final class NetworkException extends AppException {
  const NetworkException([super.message = 'The server could not be reached.']);

  @override
  String get userMessage =>
      'No connection to the server. Your matches are safe on this device and will sync later.';
}

/// The refresh token was rejected; the user has to sign in again.
final class SessionExpiredException extends AppException {
  const SessionExpiredException() : super('The session has expired.');

  @override
  String get userMessage => 'Your session has expired. Please sign in again.';
}

/// Local database or secure-storage failure.
final class LocalDataException extends AppException {
  const LocalDataException(super.message);

  @override
  String get userMessage => 'Could not read or save data on this device.';
}
