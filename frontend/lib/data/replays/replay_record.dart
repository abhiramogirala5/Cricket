import 'package:equatable/equatable.dart';

/// Where a replay file is on its way to the server.
enum ReplayUploadState {
  /// Only on this phone so far.
  local('LOCAL'),

  /// An upload is running.
  uploading('UPLOADING'),

  /// A copy is on the server.
  uploaded('UPLOADED'),

  /// The last attempts failed; the upload is tried again later.
  failed('FAILED');

  const ReplayUploadState(this.wire);

  final String wire;

  static ReplayUploadState fromWire(Object? raw) {
    for (final ReplayUploadState state in ReplayUploadState.values) {
      if (state.wire == raw) {
        return state;
      }
    }
    return ReplayUploadState.local;
  }
}

/// The bookkeeping row of one replay file.
final class ReplayRecord extends Equatable {
  const ReplayRecord({
    required this.id,
    required this.matchId,
    required this.fileName,
    required this.sizeBytes,
    required this.createdAtMs,
    this.deliveryId,
    this.uploadState = ReplayUploadState.local,
    this.remoteId,
    this.attempts = 0,
    this.lastError,
  });

  factory ReplayRecord.fromRow(Map<String, Object?> row) {
    return ReplayRecord(
      id: row['id']! as String,
      matchId: row['match_id']! as String,
      deliveryId: row['delivery_id'] as String?,
      fileName: row['file_name']! as String,
      sizeBytes: (row['size_bytes']! as num).toInt(),
      createdAtMs: (row['created_at_ms']! as num).toInt(),
      uploadState: ReplayUploadState.fromWire(row['upload_state']),
      remoteId: row['remote_id'] as String?,
      attempts: ((row['attempts'] ?? 0) as num).toInt(),
      lastError: row['last_error'] as String?,
    );
  }

  final String id;
  final String matchId;

  /// The scored ball this replay belongs to (set once the ball is saved), or null.
  final String? deliveryId;

  /// Name of the file inside the replay folder.
  final String fileName;
  final int sizeBytes;
  final int createdAtMs;
  final ReplayUploadState uploadState;

  /// Id of the copy on the server.
  final String? remoteId;
  final int attempts;
  final String? lastError;

  bool get isUploaded => uploadState == ReplayUploadState.uploaded;

  Map<String, Object?> toRow() => <String, Object?>{
        'id': id,
        'match_id': matchId,
        'delivery_id': deliveryId,
        'file_name': fileName,
        'size_bytes': sizeBytes,
        'created_at_ms': createdAtMs,
        'upload_state': uploadState.wire,
        'remote_id': remoteId,
        'attempts': attempts,
        'last_error': lastError,
      };

  ReplayRecord copyWith({
    String? deliveryId,
    ReplayUploadState? uploadState,
    String? remoteId,
    int? attempts,
    String? lastError,
    bool clearError = false,
  }) {
    return ReplayRecord(
      id: id,
      matchId: matchId,
      deliveryId: deliveryId ?? this.deliveryId,
      fileName: fileName,
      sizeBytes: sizeBytes,
      createdAtMs: createdAtMs,
      uploadState: uploadState ?? this.uploadState,
      remoteId: remoteId ?? this.remoteId,
      attempts: attempts ?? this.attempts,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }

  @override
  List<Object?> get props => <Object?>[
        id,
        matchId,
        deliveryId,
        fileName,
        sizeBytes,
        createdAtMs,
        uploadState,
        remoteId,
        attempts,
        lastError,
      ];
}
