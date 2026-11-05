// Tiny strict JSON readers for the CV layer (which must not depend on
// `lib/domain/models`). All throw [FormatException] on a bad value.

/// Reads a required number as a double.
double readDouble(Map<String, Object?> json, String key) {
  final Object? raw = json[key];
  if (raw is num) {
    return raw.toDouble();
  }
  throw FormatException('Expected a number for "$key" but got: $raw');
}

/// Reads a required number as an int (doubles are truncated).
int readInt(Map<String, Object?> json, String key) {
  final Object? raw = json[key];
  if (raw is num) {
    return raw.toInt();
  }
  throw FormatException('Expected an integer for "$key" but got: $raw');
}

/// Converts any JSON number to a double.
double numToDouble(Object? raw) {
  if (raw is num) {
    return raw.toDouble();
  }
  throw FormatException('Expected a number but got: $raw');
}

/// Converts any JSON number to an int.
int numToInt(Object? raw) {
  if (raw is num) {
    return raw.toInt();
  }
  throw FormatException('Expected an integer but got: $raw');
}

/// Converts a decoded JSON object into `Map<String, Object?>`.
Map<String, Object?> asStringMap(Object? raw) {
  if (raw is Map) {
    return raw.map((Object? key, Object? value) => MapEntry<String, Object?>(key.toString(), value));
  }
  throw FormatException('Expected a JSON object but got: $raw');
}

/// Converts a decoded JSON array into `List<Object?>`.
List<Object?> asObjectList(Object? raw) {
  if (raw is List) {
    return List<Object?>.of(raw);
  }
  throw FormatException('Expected a JSON array but got: $raw');
}
