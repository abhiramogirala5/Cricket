import 'dart:async';

import 'package:gully_umpire/data/local/local_reader.dart';
import 'package:gully_umpire/data/local/local_writer.dart';
import 'package:sqflite/sqflite.dart';

/// The on-device database of one account.
///
/// Reads can be done directly on the store. Every write goes through [transaction], which
/// makes a group of writes atomic (an entity and its outbox event are saved together) and
/// announces the change on [changes] once it is committed.
final class LocalStore extends LocalReader {
  // ignore: use_super_parameters
  LocalStore(Database database)
      : _database = database,
        super(database);

  final Database _database;
  final StreamController<void> _changes = StreamController<void>.broadcast();
  bool _closed = false;

  /// Emits after every committed transaction. Screens use it to refresh.
  Stream<void> get changes => _changes.stream;

  bool get isClosed => _closed;

  /// Runs [action] in one SQLite transaction. Only use the given [LocalWriter] inside it:
  /// using the store itself would wait for the transaction and never finish.
  ///
  /// Pass `notify: false` for bookkeeping that the rest of the app does not need to react to
  /// (the sync engine uses it, otherwise its own writes would trigger itself again).
  Future<T> transaction<T>(
    Future<T> Function(LocalWriter writer) action, {
    bool notify = true,
  }) async {
    final T result = await _database.transaction<T>(
      (Transaction txn) => action(LocalWriter(txn)),
    );
    if (notify && !_closed && !_changes.isClosed) {
      _changes.add(null);
    }
    return result;
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _changes.close();
    await _database.close();
  }
}
