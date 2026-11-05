import 'package:gully_umpire/core/utils/clock.dart';
import 'package:gully_umpire/core/utils/id_generator.dart';
import 'package:gully_umpire/data/local/local_database.dart';
import 'package:gully_umpire/data/local/local_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Ids `id-0001`, `id-0002` ... so that tests can predict them.
final class SequenceIds implements IdGenerator {
  int _next = 1;

  @override
  String newId() => 'id-${(_next++).toString().padLeft(4, '0')}';
}

/// A clock that only moves when the test says so.
final class FakeClock implements AppClock {
  FakeClock([DateTime? start]) : _now = start ?? DateTime.utc(2026, 10, 8, 7, 33);

  DateTime _now;

  @override
  DateTime now() => _now;

  void advance(Duration by) {
    _now = _now.add(by);
  }
}

/// A fresh, empty in-memory database wrapped in a [LocalStore].
Future<LocalStore> openMemoryStore() async {
  sqfliteFfiInit();
  final database = await LocalDatabase.open(
    factory: databaseFactoryFfi,
    path: inMemoryDatabasePath,
  );
  return LocalStore(database);
}
