import 'package:uuid/uuid.dart';

/// Source of client-generated identifiers. Entities are created offline, so every
/// primary key is a UUID v4 produced on the device (see docs/API_CONTRACT.md §1).
abstract interface class IdGenerator {
  String newId();
}

/// Production [IdGenerator] producing random UUID v4 strings.
class UuidGenerator implements IdGenerator {
  UuidGenerator() : _uuid = const Uuid();

  final Uuid _uuid;

  @override
  String newId() => _uuid.v4();
}
