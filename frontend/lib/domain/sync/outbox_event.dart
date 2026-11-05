import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:gully_umpire/domain/models/json_helpers.dart';
import 'package:gully_umpire/domain/sync/sync_entity_type.dart';

/// Where an outbox event stands.
enum OutboxStatus {
  /// Waiting to be sent (or to be sent again).
  pending('PENDING'),

  /// The server refused it (or it could not be applied yet); it needs a decision from the user.
  failed('FAILED');

  const OutboxStatus(this.wire);

  final String wire;

  static OutboxStatus fromWire(Object? raw) => raw == 'FAILED' ? failed : pending;
}

/// One change waiting to be sent to the server.
///
/// Events are created in the same database transaction as the change they describe, so a change
/// can never be saved without its event (or the other way round).
final class OutboxEvent extends Equatable {
  const OutboxEvent({
    required this.eventId,
    required this.entityType,
    required this.action,
    required this.payload,
    required this.clientCreatedAt,
    this.matchId,
    this.seq,
    this.status = OutboxStatus.pending,
    this.attempts = 0,
    this.errorCode,
    this.errorMessage,
  });

  /// Builds an event from a database row.
  factory OutboxEvent.fromRow(Map<String, Object?> row) {
    final Map<String, Object?>? payload = asJsonMapOrNull(row['payload']);
    return OutboxEvent(
      seq: asIntOrNull(row['seq']),
      eventId: asString(row['event_id']),
      entityType: SyncEntityType.fromWire(row['entity_type']),
      action: SyncAction.fromWire(row['action']),
      payload: payload ?? const <String, Object?>{},
      clientCreatedAt: parseDateTime(row['client_created_at']),
      matchId: asStringOrNull(row['match_id']),
      status: OutboxStatus.fromWire(row['status']),
      attempts: asInt(row['attempts'] ?? 0),
      errorCode: asStringOrNull(row['error_code']),
      errorMessage: asStringOrNull(row['error_message']),
    );
  }

  /// Client-generated UUID; the server's idempotency key.
  final String eventId;
  final SyncEntityType entityType;
  final SyncAction action;
  final Map<String, Object?> payload;
  final DateTime clientCreatedAt;

  /// The match this change belongs to (`null` for players and teams). Used to keep the events of
  /// one match in order and to drop them when the match is deleted.
  final String? matchId;

  /// Local ordering number (assigned by the database); `null` before the event is stored.
  final int? seq;
  final OutboxStatus status;
  final int attempts;
  final String? errorCode;
  final String? errorMessage;

  bool get isFailed => status == OutboxStatus.failed;

  /// The JSON sent to the server (docs/API_CONTRACT.md §5.1).
  Map<String, Object?> toRequestJson() => <String, Object?>{
        'event_id': eventId,
        'entity_type': entityType.wire,
        'action': action.wire,
        'payload': payload,
        'client_created_at': toIsoUtc(clientCreatedAt),
      };

  /// The values stored in the `outbox` table (without `seq`, which the database assigns).
  Map<String, Object?> toRow() => <String, Object?>{
        'event_id': eventId,
        'entity_type': entityType.wire,
        'action': action.wire,
        'payload': jsonEncode(payload),
        'client_created_at': toIsoUtc(clientCreatedAt),
        'status': status.wire,
        'attempts': attempts,
        'error_code': errorCode,
        'error_message': errorMessage,
        'match_id': matchId,
      };

  @override
  List<Object?> get props => <Object?>[
        eventId,
        entityType,
        action,
        payload,
        clientCreatedAt,
        matchId,
        seq,
        status,
        attempts,
        errorCode,
        errorMessage,
      ];
}
