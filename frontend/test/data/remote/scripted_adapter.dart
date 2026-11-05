import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// A dio adapter that answers from a function instead of using the network.
final class ScriptedAdapter implements HttpClientAdapter {
  ScriptedAdapter(this.onRequest);

  Future<ResponseBody> Function(RequestOptions options) onRequest;

  /// Every request that reached the "network", in order.
  final List<RequestOptions> requests = <RequestOptions>[];

  /// The bytes that were sent with each request in [requests] (empty when there was no body).
  final List<Uint8List> bodies = <Uint8List>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final BytesBuilder body = BytesBuilder(copy: false);
    if (requestStream != null) {
      await for (final Uint8List chunk in requestStream) {
        body.add(chunk);
      }
    }
    requests.add(options);
    bodies.add(body.takeBytes());
    return onRequest(options);
  }

  @override
  void close({bool force = false}) {}

  /// The JSON body that was sent with request number [index].
  Map<String, Object?> sentJson(int index) {
    final Object? data = requests[index].data;
    if (data is! String) {
      throw StateError('Request $index has no JSON body');
    }
    final Object? decoded = jsonDecode(data);
    return (decoded as Map<Object?, Object?>).map(
      (Object? key, Object? value) => MapEntry<String, Object?>(key.toString(), value),
    );
  }

  List<String> get paths => requests.map<String>((RequestOptions r) => r.uri.path).toList();
}

ResponseBody jsonReply(int status, Object? body, {Map<String, List<String>>? headers}) =>
    ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
        ...?headers,
      },
    );

ResponseBody textReply(int status, String body) => ResponseBody.fromString(body, status);

ResponseBody emptyReply(int status) => ResponseBody.fromString('', status);

Map<String, Object?> errorEnvelope(String code, String message, {Object? details}) =>
    <String, Object?>{
      'error': <String, Object?>{
        'code': code,
        'message': message,
        if (details != null) 'details': details,
        'request_id': 'req-123',
      },
    };

Map<String, Object?> tokenPair(String access, String refresh) => <String, Object?>{
      'access_token': access,
      'refresh_token': refresh,
      'token_type': 'bearer',
      'expires_in': 900,
    };

Map<String, Object?> userJson({String id = 'user-1'}) => <String, Object?>{
      'id': id,
      'email': 'asha@example.com',
      'display_name': 'Asha Rao',
      'phone': null,
      'avatar_url': null,
      'created_at': '2026-10-08T07:33:00Z',
    };
