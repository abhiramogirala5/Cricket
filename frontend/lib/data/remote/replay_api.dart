import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';
import 'package:gully_umpire/core/errors/app_exception.dart';
import 'package:gully_umpire/data/remote/api_client.dart';
import 'package:gully_umpire/domain/models/json_helpers.dart';

/// Where and how the phone must send one replay file (docs/API_CONTRACT.md §8).
final class ReplayUploadTarget extends Equatable {
  const ReplayUploadTarget({required this.url, required this.headers});

  factory ReplayUploadTarget.fromJson(Map<String, Object?> json) {
    final Object? url = json['url'];
    if (url is! String || url.isEmpty) {
      throw const ApiException(
        code: 'INVALID_RESPONSE',
        message: 'The server sent an unusable upload link.',
      );
    }
    final Object? raw = json['headers'];
    final Map<String, String> headers = <String, String>{};
    if (raw is Map) {
      raw.forEach((Object? key, Object? value) {
        if (key is String && value is String) {
          headers[key] = value;
        }
      });
    }
    return ReplayUploadTarget(url: url, headers: headers);
  }

  /// A short-lived address of the private bucket. It carries its own permission, so it is called
  /// without the account's token.
  final String url;

  /// Headers to send with the file, exactly as given.
  final Map<String, String> headers;

  @override
  List<Object?> get props => <Object?>[url, headers];
}

/// The server's answer to "I am about to upload this replay".
final class ReplayAnnouncement extends Equatable {
  const ReplayAnnouncement({required this.alreadyStored, this.upload});

  /// The server already holds this replay: nothing has to be sent.
  final bool alreadyStored;

  /// Where to send the file (`null` when [alreadyStored]).
  final ReplayUploadTarget? upload;

  @override
  List<Object?> get props => <Object?>[alreadyStored, upload];
}

/// A replay the server holds.
final class RemoteReplay extends Equatable {
  const RemoteReplay({required this.id, required this.sizeBytes, this.deliveryId});

  final String id;
  final int sizeBytes;
  final String? deliveryId;

  @override
  List<Object?> get props => <Object?>[id, sizeBytes, deliveryId];
}

/// The replay endpoints. An interface so the uploader can be tested without a network.
abstract interface class ReplayApi {
  /// Tells the server about a replay file that is about to be uploaded. Announcing the same [id]
  /// again is harmless.
  Future<ReplayAnnouncement> announce({
    required String id,
    required String matchId,
    required int sizeBytes,
    String? deliveryId,
    int? width,
    int? height,
    int? frameCount,
    int? durationMs,
  });

  /// Sends the file to the address the server gave.
  Future<void> upload(ReplayUploadTarget target, Uint8List bytes);

  /// Says that the file has been sent; the server checks that it arrived whole.
  Future<void> complete(String id);

  /// The stored replays of one delivery (newest first).
  Future<List<RemoteReplay>> forDelivery(String deliveryId);

  /// The bytes of a stored replay.
  Future<Uint8List> download(String id);
}

final class HttpReplayApi implements ReplayApi {
  HttpReplayApi(this._client, {Dio? fileDio}) : _files = fileDio ?? Dio();

  final ApiClient _client;

  /// Talks to the storage service directly: no base address and no account token.
  final Dio _files;

  @override
  Future<ReplayAnnouncement> announce({
    required String id,
    required String matchId,
    required int sizeBytes,
    String? deliveryId,
    int? width,
    int? height,
    int? frameCount,
    int? durationMs,
  }) async {
    final Map<String, Object?> json = await _client.sendForMap(
      'POST',
      '/replays',
      body: <String, Object?>{
        'id': id,
        'match_id': matchId,
        if (deliveryId != null) 'delivery_id': deliveryId,
        'size_bytes': sizeBytes,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
        if (frameCount != null) 'frame_count': frameCount,
        if (durationMs != null) 'duration_ms': durationMs,
      },
    );
    final Object? upload = json['upload'];
    if (upload == null) {
      return const ReplayAnnouncement(alreadyStored: true);
    }
    final Map<String, Object?>? target = upload is Map ? asJsonMapOrNull(upload) : null;
    if (target == null) {
      throw const ApiException(
        code: 'INVALID_RESPONSE',
        message: 'The server sent an unexpected response.',
      );
    }
    return ReplayAnnouncement(alreadyStored: false, upload: ReplayUploadTarget.fromJson(target));
  }

  @override
  Future<void> upload(ReplayUploadTarget target, Uint8List bytes) async {
    final Response<String> response;
    try {
      // The file goes out as a stream with its length set: that is how dio sends raw bytes. (A
      // plain byte list is meant for text and form data and could be sent as text.)
      response = await _files.put<String>(
        target.url,
        data: Stream<List<int>>.value(bytes),
        options: Options(
          headers: <String, Object?>{
            ...target.headers,
            Headers.contentLengthHeader: bytes.length,
          },
          responseType: ResponseType.plain,
          validateStatus: (int? status) => true,
          sendTimeout: const Duration(minutes: 2),
          receiveTimeout: const Duration(minutes: 2),
        ),
      );
    } on DioException {
      throw const NetworkException('The replay could not be sent. Check the connection.');
    }
    final int status = response.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      throw ApiException(
        code: 'UPLOAD_FAILED',
        message: 'The storage service refused the replay (status $status).',
        statusCode: status,
      );
    }
  }

  @override
  Future<void> complete(String id) async {
    await _client.send('POST', '/replays/$id/complete');
  }

  @override
  Future<List<RemoteReplay>> forDelivery(String deliveryId) async {
    final Map<String, Object?> json = await _client.sendForMap(
      'GET',
      '/replays',
      query: <String, Object?>{'delivery_id': deliveryId, 'limit': 5},
    );
    final Object? items = json['items'];
    final List<RemoteReplay> replays = <RemoteReplay>[];
    if (items is List) {
      for (final Object? item in items) {
        final Map<String, Object?>? map = item is Map ? asJsonMapOrNull(item) : null;
        final Object? id = map?['id'];
        final Object? size = map?['size_bytes'];
        if (map != null && id is String && size is num) {
          replays.add(
            RemoteReplay(
              id: id,
              sizeBytes: size.toInt(),
              deliveryId: asStringOrNull(map['delivery_id']),
            ),
          );
        }
      }
    }
    return replays;
  }

  @override
  Future<Uint8List> download(String id) async {
    final Map<String, Object?> json = await _client.sendForMap('GET', '/replays/$id/download');
    final Object? url = json['url'];
    if (url is! String || url.isEmpty) {
      throw const ApiException(
        code: 'INVALID_RESPONSE',
        message: 'The server sent an unusable download link.',
      );
    }
    final Response<List<int>> response;
    try {
      response = await _files.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          validateStatus: (int? status) => true,
          receiveTimeout: const Duration(minutes: 2),
        ),
      );
    } on DioException {
      throw const NetworkException('The replay could not be downloaded. Check the connection.');
    }
    final int status = response.statusCode ?? 0;
    final List<int>? data = response.data;
    if (status < 200 || status >= 300 || data == null) {
      throw ApiException(
        code: 'DOWNLOAD_FAILED',
        message: 'The replay could not be downloaded (status $status).',
        statusCode: status,
      );
    }
    return data is Uint8List ? data : Uint8List.fromList(data);
  }
}
