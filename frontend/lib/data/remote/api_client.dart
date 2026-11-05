import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:gully_umpire/core/errors/app_exception.dart';
import 'package:gully_umpire/core/utils/app_log.dart';
import 'package:gully_umpire/core/utils/id_generator.dart';
import 'package:gully_umpire/data/session/session_keeper.dart';
import 'package:gully_umpire/data/session/session_models.dart';
import 'package:gully_umpire/domain/models/json_helpers.dart';

/// A decoded HTTP answer.
final class _Reply {
  const _Reply(this.statusCode, this.body, this.headers);

  final int statusCode;
  final Object? body;
  final Headers headers;

  bool get isSuccess => statusCode >= 200 && statusCode < 300;

  /// The error `code` of the backend's error envelope, if the body is one.
  String? get errorCode {
    final Map<String, Object?>? envelope = _envelope;
    return envelope == null ? null : asStringOrNull(envelope['code']);
  }

  Map<String, Object?>? get _envelope {
    final Object? current = body;
    if (current is Map) {
      final Object? error = current['error'];
      if (error is Map) {
        return error.map((Object? k, Object? v) => MapEntry<String, Object?>(k.toString(), v));
      }
    }
    return null;
  }
}

/// JSON-over-HTTP client for the Gully Umpire API (docs/API_CONTRACT.md).
///
/// * Adds the bearer token and a request id to every call.
/// * Turns error responses into [ApiException] and connection problems into [NetworkException].
/// * On `401 TOKEN_EXPIRED` refreshes the tokens ONCE (all callers that need it at the same
///   moment share one refresh, because refresh tokens rotate) and repeats the request.
/// * When the server no longer accepts the session it forgets it ([SessionKeeper.expire]) and
///   throws [SessionExpiredException].
final class ApiClient {
  ApiClient({
    required String baseUrl,
    required SessionKeeper session,
    required IdGenerator ids,
    Duration timeout = const Duration(seconds: 20),
    Dio? dio,
  })  : _session = session,
        _ids = ids,
        _dio = dio ?? Dio() {
    _dio.options
      ..baseUrl = baseUrl
      ..connectTimeout = timeout
      ..sendTimeout = timeout
      ..receiveTimeout = timeout;
  }

  final SessionKeeper _session;
  final IdGenerator _ids;
  final Dio _dio;
  Future<void>? _refreshInFlight;

  /// Sends a request and returns the decoded JSON body (`null` for an empty body).
  ///
  /// Set [auth] to `false` for the endpoints that need no token (login, register, refresh).
  Future<Object?> send(
    String method,
    String path, {
    Object? body,
    Map<String, Object?>? query,
    bool auth = true,
  }) async {
    _Reply reply = await _sendOnce(method, path, body: body, query: query, auth: auth);
    if (auth && reply.statusCode == 401 && reply.errorCode == 'TOKEN_EXPIRED') {
      await _refreshTokens();
      reply = await _sendOnce(method, path, body: body, query: query, auth: auth);
    }
    if (reply.isSuccess) {
      return reply.body;
    }
    if (auth && reply.statusCode == 401) {
      // Whatever the code, a second 401 means this session cannot be used any more.
      await _session.expire();
      throw const SessionExpiredException();
    }
    throw _toApiException(reply);
  }

  /// [send] for endpoints that return a JSON object.
  Future<Map<String, Object?>> sendForMap(
    String method,
    String path, {
    Object? body,
    Map<String, Object?>? query,
    bool auth = true,
  }) async {
    final Object? decoded = await send(method, path, body: body, query: query, auth: auth);
    final Map<String, Object?>? map = decoded is Map ? asJsonMapOrNull(decoded) : null;
    if (map == null) {
      throw const ApiException(
        code: 'INVALID_RESPONSE',
        message: 'The server sent an unexpected response.',
      );
    }
    return map;
  }

  Future<_Reply> _sendOnce(
    String method,
    String path, {
    Object? body,
    Map<String, Object?>? query,
    required bool auth,
  }) async {
    final Map<String, Object?> headers = <String, Object?>{
      'Accept': 'application/json',
      'X-Request-ID': _ids.newId(),
    };
    if (auth) {
      final AuthTokens? tokens = _session.current?.tokens;
      if (tokens == null) {
        throw const SessionExpiredException();
      }
      headers['Authorization'] = 'Bearer ${tokens.accessToken}';
    }

    final Response<String> response;
    try {
      response = await _dio.request<String>(
        path,
        data: body == null ? null : jsonEncode(body),
        queryParameters: query,
        options: Options(
          method: method,
          headers: headers,
          contentType: body == null ? null : Headers.jsonContentType,
          responseType: ResponseType.plain,
          validateStatus: (int? status) => true,
        ),
      );
    } on DioException catch (error) {
      throw _toNetworkException(error);
    }

    final int status = response.statusCode ?? 0;
    final String text = response.data ?? '';
    Object? decoded;
    if (text.trim().isNotEmpty) {
      try {
        decoded = jsonDecode(text);
      } on FormatException {
        decoded = null;
        if (status >= 200 && status < 300) {
          throw ApiException(
            code: 'INVALID_RESPONSE',
            message: 'The server sent an unreadable response.',
            statusCode: status,
          );
        }
      }
    }
    return _Reply(status, decoded, response.headers);
  }

  Future<void> _refreshTokens() {
    final Future<void>? running = _refreshInFlight;
    if (running != null) {
      return running;
    }
    final Future<void> started = _doRefresh().whenComplete(() {
      _refreshInFlight = null;
    });
    _refreshInFlight = started;
    return started;
  }

  Future<void> _doRefresh() async {
    final AuthTokens? tokens = _session.current?.tokens;
    if (tokens == null) {
      throw const SessionExpiredException();
    }
    final _Reply reply = await _sendOnce(
      'POST',
      '/auth/refresh',
      body: <String, Object?>{'refresh_token': tokens.refreshToken},
      auth: false,
    );
    if (reply.isSuccess) {
      final Object? body = reply.body;
      if (body is! Map) {
        throw const ApiException(
          code: 'INVALID_RESPONSE',
          message: 'The server sent an unexpected response.',
        );
      }
      await _session.updateTokens(AuthTokens.fromJson(asJsonMapOrNull(body)!));
      return;
    }
    if (reply.statusCode == 401 || reply.statusCode == 403) {
      AppLog.info('Refresh token refused (${reply.errorCode}); the session has ended.');
      await _session.expire();
      throw const SessionExpiredException();
    }
    throw _toApiException(reply);
  }

  ApiException _toApiException(_Reply reply) {
    final Map<String, Object?>? envelope = reply._envelope;
    final Object? rawDetails = envelope?['details'];
    final String? retryAfterHeader = reply.headers.value('retry-after');
    final int? retrySeconds = retryAfterHeader == null ? null : int.tryParse(retryAfterHeader.trim());
    return ApiException(
      code: reply.errorCode ?? 'HTTP_${reply.statusCode}',
      message: (envelope == null ? null : asStringOrNull(envelope['message'])) ??
          'The server answered with status ${reply.statusCode}.',
      statusCode: reply.statusCode,
      details: rawDetails is List ? List<Object?>.from(rawDetails) : null,
      requestId: (envelope == null ? null : asStringOrNull(envelope['request_id'])) ??
          reply.headers.value('x-request-id'),
      retryAfter: retrySeconds == null || retrySeconds < 0 ? null : Duration(seconds: retrySeconds),
    );
  }

  NetworkException _toNetworkException(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const NetworkException('The server took too long to answer.');
      case DioExceptionType.badCertificate:
        return const NetworkException('A secure connection to the server could not be made.');
      case DioExceptionType.cancel:
        return const NetworkException('The request was cancelled.');
      // connectionError, badResponse, unknown and any type a newer dio adds.
      default:
        return const NetworkException();
    }
  }

  void close() => _dio.close();
}
