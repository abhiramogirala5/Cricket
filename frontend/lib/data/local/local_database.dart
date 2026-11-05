import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Opens the on-device SQLite database and owns its schema.
///
/// Entities are stored as JSON documents (`doc`) next to the few columns that are queried or
/// sorted on. The documents use exactly the shapes of `lib/domain/models` (`toJson`/`fromJson`),
/// so adding an optional field to a model never needs a migration.
abstract final class LocalDatabase {
  /// Bump together with a migration step in [_onUpgrade].
  static const int schemaVersion = 2;

  /// Name of the database file for [userId] (one file per account on a shared phone).
  static String fileNameFor(String userId) {
    final String safe = userId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return 'gully_umpire_${safe.isEmpty ? 'local' : safe}.db';
  }

  /// Full path of the database file for [userId].
  static Future<String> pathFor(DatabaseFactory factory, String userId) async {
    final String directory = await factory.getDatabasesPath();
    return p.join(directory, fileNameFor(userId));
  }

  /// Folder in which the replay files of [userId] are kept (next to the database file).
  static Future<String> replayDirectoryPathFor(DatabaseFactory factory, String userId) async {
    final String directory = await factory.getDatabasesPath();
    final String name = fileNameFor(userId).replaceAll(RegExp(r'\.db$'), '_replays');
    return p.join(directory, name);
  }

  /// Opens (and creates if needed) the database at [path].
  ///
  /// Pass `inMemoryDatabasePath` as [path] in tests.
  static Future<Database> open({
    required DatabaseFactory factory,
    required String path,
  }) {
    return factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        singleInstance: false,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );
  }

  /// Deletes the database file of [userId] (account deletion).
  static Future<void> deleteFor(DatabaseFactory factory, String userId) async {
    await factory.deleteDatabase(await pathFor(factory, userId));
    final Directory replays = Directory(await replayDirectoryPathFor(factory, userId));
    if (replays.existsSync()) {
      await replays.delete(recursive: true);
    }
  }

  static Future<void> _onCreate(Database db, int version) async {
    final Batch batch = db.batch();
    for (final String statement in <String>[..._createStatements, ..._replayStatements]) {
      batch.execute(statement);
    }
    await batch.commit(noResult: true);
  }

  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Each step is idempotent, so a half-finished upgrade can simply run again.
    if (oldVersion < 2) {
      for (final String statement in _replayStatements) {
        await db.execute(statement);
      }
    }
  }

  /// Version 2: the replay packs of deliveries (the files themselves live next to the database).
  static const List<String> _replayStatements = <String>[
    '''
CREATE TABLE IF NOT EXISTS replay_packs (
  id TEXT PRIMARY KEY NOT NULL,
  match_id TEXT NOT NULL,
  delivery_id TEXT,
  file_name TEXT NOT NULL,
  size_bytes INTEGER NOT NULL,
  created_at_ms INTEGER NOT NULL,
  upload_state TEXT NOT NULL DEFAULT 'LOCAL',
  remote_id TEXT,
  attempts INTEGER NOT NULL DEFAULT 0,
  last_error TEXT
)''',
    'CREATE INDEX IF NOT EXISTS ix_replay_delivery ON replay_packs (delivery_id)',
    'CREATE INDEX IF NOT EXISTS ix_replay_state ON replay_packs (upload_state, created_at_ms)',
  ];

  static const List<String> _createStatements = <String>[
    '''
CREATE TABLE teams (
  id TEXT PRIMARY KEY NOT NULL,
  name TEXT NOT NULL,
  doc TEXT NOT NULL
)''',
    '''
CREATE TABLE players (
  id TEXT PRIMARY KEY NOT NULL,
  name TEXT NOT NULL,
  doc TEXT NOT NULL
)''',
    '''
CREATE TABLE matches (
  id TEXT PRIMARY KEY NOT NULL,
  status TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  doc TEXT NOT NULL
)''',
    'CREATE INDEX ix_matches_created ON matches (created_at_ms DESC)',
    '''
CREATE TABLE match_players (
  match_id TEXT NOT NULL,
  player_id TEXT NOT NULL,
  doc TEXT NOT NULL,
  PRIMARY KEY (match_id, player_id)
)''',
    '''
CREATE TABLE match_rules (
  match_id TEXT PRIMARY KEY NOT NULL,
  doc TEXT NOT NULL
)''',
    '''
CREATE TABLE tosses (
  id TEXT PRIMARY KEY NOT NULL,
  match_id TEXT NOT NULL UNIQUE,
  doc TEXT NOT NULL
)''',
    '''
CREATE TABLE innings (
  id TEXT PRIMARY KEY NOT NULL,
  match_id TEXT NOT NULL,
  innings_number INTEGER NOT NULL,
  doc TEXT NOT NULL,
  UNIQUE (match_id, innings_number)
)''',
    '''
CREATE TABLE deliveries (
  id TEXT PRIMARY KEY NOT NULL,
  innings_id TEXT NOT NULL,
  delivery_sequence INTEGER NOT NULL,
  is_voided INTEGER NOT NULL DEFAULT 0,
  doc TEXT NOT NULL,
  UNIQUE (innings_id, delivery_sequence)
)''',
    '''
CREATE TABLE delivery_decisions (
  id TEXT PRIMARY KEY NOT NULL,
  delivery_id TEXT NOT NULL,
  doc TEXT NOT NULL
)''',
    'CREATE INDEX ix_decisions_delivery ON delivery_decisions (delivery_id)',
    '''
CREATE TABLE scene_scans (
  id TEXT PRIMARY KEY NOT NULL,
  match_id TEXT NOT NULL,
  doc TEXT NOT NULL
)''',
    'CREATE INDEX ix_scans_match ON scene_scans (match_id)',
    '''
CREATE TABLE wicket_detections (
  id TEXT PRIMARY KEY NOT NULL,
  match_id TEXT NOT NULL,
  is_active INTEGER NOT NULL DEFAULT 1,
  doc TEXT NOT NULL
)''',
    'CREATE INDEX ix_wickets_match ON wicket_detections (match_id)',
    '''
CREATE TABLE trajectory_snapshots (
  id TEXT PRIMARY KEY NOT NULL,
  delivery_id TEXT NOT NULL,
  doc TEXT NOT NULL
)''',
    'CREATE INDEX ix_trajectories_delivery ON trajectory_snapshots (delivery_id)',
    '''
CREATE TABLE outbox (
  seq INTEGER PRIMARY KEY AUTOINCREMENT,
  event_id TEXT NOT NULL UNIQUE,
  entity_type TEXT NOT NULL,
  action TEXT NOT NULL,
  payload TEXT NOT NULL,
  client_created_at TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'PENDING',
  attempts INTEGER NOT NULL DEFAULT 0,
  error_code TEXT,
  error_message TEXT,
  match_id TEXT
)''',
    'CREATE INDEX ix_outbox_status ON outbox (status, seq)',
    'CREATE INDEX ix_outbox_match ON outbox (match_id, seq)',
    '''
CREATE TABLE meta (
  key TEXT PRIMARY KEY NOT NULL,
  value TEXT NOT NULL
)''',
  ];
}
