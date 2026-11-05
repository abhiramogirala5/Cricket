import 'package:equatable/equatable.dart';
import 'package:gully_umpire/domain/models/json_helpers.dart';

/// Per-event outcome of `POST /sync/push` (docs/API_CONTRACT.md §5.1).
enum SyncResultStatus {
  applied('APPLIED'),
  duplicate('DUPLICATE'),
  rejected('REJECTED');

  const SyncResultStatus(this.wire);

  final String wire;

  /// The server has this change now (either just applied or applied earlier).
  bool get isAccepted => this != SyncResultStatus.rejected;

  static SyncResultStatus fromWire(Object? raw) {
    for (final SyncResultStatus value in values) {
      if (value.wire == raw) {
        return value;
      }
    }
    throw FormatException('Unknown sync result status: $raw');
  }
}

/// Per-event error codes (docs/API_CONTRACT.md §5.4).
abstract final class SyncErrorCodes {
  static const String invalidPayload = 'INVALID_PAYLOAD';
  static const String unsupportedEvent = 'UNSUPPORTED_EVENT';
  static const String forbidden = 'FORBIDDEN';
  static const String parentNotFound = 'PARENT_NOT_FOUND';
  static const String invalidReference = 'INVALID_REFERENCE';
  static const String invalidState = 'INVALID_STATE';
  static const String invalidDelivery = 'INVALID_DELIVERY';
  static const String inningsClosed = 'INNINGS_CLOSED';
  static const String overLimitExceeded = 'OVER_LIMIT_EXCEEDED';
  static const String notLastDelivery = 'NOT_LAST_DELIVERY';
  static const String entityNotFound = 'ENTITY_NOT_FOUND';
  static const String internalError = 'INTERNAL_ERROR';

  /// Codes that can resolve themselves later (the contract's "retryable later").
  static bool isRetryableLater(String? code) =>
      code == parentNotFound || code == internalError;

  /// A short explanation for the "Sync issues" screen.
  static String describe(String? code) {
    switch (code) {
      case invalidPayload:
        return 'The server could not read this change.';
      case unsupportedEvent:
        return 'This kind of change is not supported by the server.';
      case forbidden:
        return 'This belongs to a different account.';
      case parentNotFound:
        return 'It depends on something that has not reached the server yet.';
      case invalidReference:
        return 'It refers to a player or team that is not part of this match.';
      case invalidState:
        return 'The server already has a conflicting version.';
      case invalidDelivery:
        return 'The server did not accept this ball as scored.';
      case inningsClosed:
        return 'The server has already closed this innings.';
      case overLimitExceeded:
        return 'The server already has all the overs for this innings.';
      case notLastDelivery:
        return 'Only the most recent ball can be undone on the server.';
      case entityNotFound:
        return 'The server does not have the ball that should be changed.';
      case internalError:
        return 'The server had a problem. It is safe to try again.';
      default:
        return 'The server did not accept this change.';
    }
  }
}

final class SyncEventResult extends Equatable {
  const SyncEventResult({
    required this.eventId,
    required this.status,
    this.errorCode,
    this.errorMessage,
  });

  factory SyncEventResult.fromJson(Map<String, Object?> json) {
    final Map<String, Object?>? error = asJsonMapOrNull(json['error']);
    return SyncEventResult(
      eventId: asString(json['event_id']),
      status: SyncResultStatus.fromWire(json['status']),
      errorCode: error == null ? null : asStringOrNull(error['code']),
      errorMessage: error == null ? null : asStringOrNull(error['message']),
    );
  }

  final String eventId;
  final SyncResultStatus status;
  final String? errorCode;
  final String? errorMessage;

  @override
  List<Object?> get props => <Object?>[eventId, status, errorCode, errorMessage];
}

/// The `200` body of `POST /sync/push`.
final class SyncPushResponse extends Equatable {
  const SyncPushResponse({required this.results, this.serverTime});

  factory SyncPushResponse.fromJson(Map<String, Object?> json) {
    final List<Object?> rawResults = asJsonListOrNull(json['results']) ?? const <Object?>[];
    return SyncPushResponse(
      results: rawResults
          .map<SyncEventResult>(
            (Object? item) => SyncEventResult.fromJson(asJsonMapOrNull(item) ?? <String, Object?>{}),
          )
          .toList(growable: false),
      serverTime: parseDateTimeOrNull(json['server_time']),
    );
  }

  final List<SyncEventResult> results;
  final DateTime? serverTime;

  @override
  List<Object?> get props => <Object?>[results, serverTime];
}
