import 'dart:convert';

/// Parses an ISO-8601 timestamp (always UTC on the wire) or returns null.
DateTime? parseDateTimeOrNull(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is DateTime) {
    return value.toUtc();
  }
  if (value is String) {
    if (value.isEmpty) {
      return null;
    }
    return DateTime.parse(value).toUtc();
  }
  throw FormatException('Invalid timestamp: $value');
}

DateTime parseDateTime(Object? value) {
  final DateTime? parsed = parseDateTimeOrNull(value);
  if (parsed == null) {
    throw const FormatException('Missing required timestamp');
  }
  return parsed;
}

/// Serialises a timestamp as RFC 3339 UTC with a `Z` suffix.
String? toIsoUtc(DateTime? value) => value?.toUtc().toIso8601String();

String asString(Object? value) {
  if (value is String) {
    return value;
  }
  throw FormatException('Expected a string but got: $value');
}

String? asStringOrNull(Object? value) => value == null ? null : asString(value);

int asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.parse(value);
  }
  throw FormatException('Expected an integer but got: $value');
}

int? asIntOrNull(Object? value) => value == null ? null : asInt(value);

double asDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.parse(value);
  }
  throw FormatException('Expected a number but got: $value');
}

double? asDoubleOrNull(Object? value) => value == null ? null : asDouble(value);

/// Accepts real booleans (JSON) and 0/1 integers (SQLite).
bool asBool(Object? value, {bool fallback = false}) {
  if (value == null) {
    return fallback;
  }
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  throw FormatException('Expected a boolean but got: $value');
}

/// Accepts a decoded map (JSON) or a JSON string (SQLite text column).
Map<String, Object?>? asJsonMapOrNull(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is String) {
    if (value.isEmpty) {
      return null;
    }
    return asJsonMapOrNull(jsonDecode(value));
  }
  if (value is Map) {
    return value.map((Object? key, Object? entry) => MapEntry<String, Object?>(key.toString(), entry));
  }
  throw FormatException('Expected a JSON object but got: $value');
}

/// Accepts a decoded list (JSON) or a JSON string (SQLite text column).
List<Object?>? asJsonListOrNull(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is String) {
    if (value.isEmpty) {
      return null;
    }
    return asJsonListOrNull(jsonDecode(value));
  }
  if (value is List) {
    return List<Object?>.from(value);
  }
  throw FormatException('Expected a JSON array but got: $value');
}

/// Returns a copy of [json] without the listed keys (used to build sync payloads).
Map<String, Object?> withoutKeys(Map<String, Object?> json, Set<String> keys) {
  final Map<String, Object?> copy = Map<String, Object?>.of(json);
  for (final String key in keys) {
    copy.remove(key);
  }
  return copy;
}
