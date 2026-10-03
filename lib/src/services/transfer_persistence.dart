import 'dart:async';
import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/transfer.dart';

class TransferPersistence {
  TransferPersistence._();

  static final TransferPersistence instance = TransferPersistence._();

  static const String _dbName = 'transfers.db';
  static const int _dbVersion = 2;
  static const String _tableName = 'transfers';

  /// Test override so parallel test files never share one sqlite file.
  static String debugDatabaseName = _dbName;

  Database? _db;
  Completer<Database>? _initCompleter;

  /// Test-only: drop the cached handle so the next access reopens the file.
  Future<void> debugReset() async {
    _initCompleter = null;
    final db = _db;
    _db = null;
    try {
      await db?.close();
    } catch (_) {}
  }

  Future<Database> get database async {
    if (_db != null) return _db!;
    if (_initCompleter != null) return _initCompleter!.future;
    _initCompleter = Completer<Database>();
    _db = await _initDatabase();
    _initCompleter!.complete(_db);
    return _db!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, debugDatabaseName);

    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $_tableName (
        id TEXT PRIMARY KEY,
        file_id TEXT NOT NULL,
        name TEXT NOT NULL,
        size INTEGER NOT NULL,
        bytes_transferred INTEGER NOT NULL DEFAULT 0,
        direction TEXT NOT NULL,
        status TEXT NOT NULL,
        remote_peer_id TEXT,
        remote_peer_name TEXT,
        local_path TEXT NOT NULL,
        destination_path TEXT,
        sha256_hash TEXT,
        partial_hash TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        completed_at TEXT,
        error_message TEXT,
        retry_count INTEGER NOT NULL DEFAULT 0,
        resume_metadata TEXT NOT NULL DEFAULT '{}',
        transport TEXT NOT NULL,
        priority INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_transfers_status ON $_tableName(status)
    ''');
    await db.execute('''
      CREATE INDEX idx_transfers_updated_at ON $_tableName(updated_at)
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Migration from v1 to v2: check if file_id column exists, add if not
      final columns = await db.rawQuery("PRAGMA table_info($_tableName)");
      final hasFileId = columns.any((col) => col['name'] == 'file_id');
      if (!hasFileId) {
        await db.execute('ALTER TABLE $_tableName ADD COLUMN file_id TEXT NOT NULL DEFAULT \'\'');
      }
    }
  }

  Future<void> insert(Transfer transfer) async {
    final db = await database;
    await db.insert(
      _tableName,
      transfer.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> insertAll(List<Transfer> transfers) async {
    final db = await database;
    final batch = db.batch();
    for (final transfer in transfers) {
      batch.insert(
        _tableName,
        transfer.toJson(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<Transfer?> get(String id) async {
    final db = await database;
    final results = await db.query(
      _tableName,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (results.isEmpty) return null;
    return Transfer.fromJson(results.first);
  }

  Future<List<Transfer>> getAll({TransferStatus? status}) async {
    final db = await database;
    final where = status != null ? 'status = ?' : null;
    final whereArgs = status != null ? [status.name] : null;
    final results = await db.query(
      _tableName,
      where: where,
      whereArgs: whereArgs,
      orderBy: 'updated_at DESC',
    );
    return results.map(Transfer.fromJson).toList();
  }

  Future<List<Transfer>> getActive() async {
    final db = await database;
    final statuses = [
      TransferStatus.queued.name,
      TransferStatus.preparing.name,
      TransferStatus.connecting.name,
      TransferStatus.transferring.name,
      TransferStatus.paused.name,
      TransferStatus.resuming.name,
      TransferStatus.verifying.name,
      TransferStatus.retrying.name,
    ];
    final placeholders = List.filled(statuses.length, '?').join(',');
    final results = await db.query(
      _tableName,
      where: 'status IN ($placeholders)',
      whereArgs: statuses,
      orderBy: 'updated_at DESC',
    );
    return results.map(Transfer.fromJson).toList();
  }

  Future<void> update(Transfer transfer) async {
    final db = await database;
    await db.update(
      _tableName,
      transfer.toJson(),
      where: 'id = ?',
      whereArgs: [transfer.id],
    );
  }

  Future<void> updateBytesTransferred(String id, int bytes) async {
    final db = await database;
    await db.update(
      _tableName,
      {
        'bytes_transferred': bytes,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateStatus(String id, TransferStatus status, {String? errorMessage}) async {
    final db = await database;
    final data = <String, dynamic>{
      'status': status.name,
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (status == TransferStatus.completed) {
      data['completed_at'] = DateTime.now().toIso8601String();
    }
    if (errorMessage != null) {
      data['error_message'] = errorMessage;
    }
    await db.update(
      _tableName,
      data,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateResumeMetadata(String id, Map<String, dynamic> metadata) async {
    final db = await database;
    await db.update(
      _tableName,
      {
        'resume_metadata': jsonEncode(metadata),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateLocalPath(String id, String localPath) async {
    final db = await database;
    await db.update(
      _tableName,
      {
        'local_path': localPath,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> delete(String id) async {
    final db = await database;
    await db.delete(
      _tableName,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteAll() async {
    final db = await database;
    await db.delete(_tableName);
  }

  Future<void> deleteCompleted() async {
    final db = await database;
    await db.delete(
      _tableName,
      where: 'status = ?',
      whereArgs: [TransferStatus.completed.name],
    );
  }

  Future<void> deleteTerminal() async {
    final db = await database;
    await db.delete(
      _tableName,
      where: 'status IN (?, ?, ?)',
      whereArgs: [
        TransferStatus.completed.name,
        TransferStatus.cancelled.name,
        TransferStatus.failed.name,
      ],
    );
  }

  Future<int> count({TransferStatus? status}) async {
    final db = await database;
    final where = status != null ? 'status = ?' : null;
    final whereArgs = status != null ? [status.name] : null;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM $_tableName${where != null ? ' WHERE $where' : ''}',
      whereArgs,
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> close() async {
    final db = _db;
    if (db != null) {
      await db.close();
      _db = null;
      _initCompleter = null;
    }
  }
}