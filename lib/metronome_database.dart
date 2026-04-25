import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

const String kDefaultWebPageUrl = 'https://www.jitashe.org/';

class PersistedSettings {
  const PersistedSettings({
    required this.lastBpm,
    required this.timeSignature,
    required this.accentSoundId,
    required this.normalSoundId,
    required this.vocalMode,
    required this.subdivisionType,
    required this.beatRhythmTypes,
    required this.webPageUrl,
  });

  final int lastBpm;
  final String timeSignature;
  final String accentSoundId;
  final String normalSoundId;
  final String vocalMode;
  final int subdivisionType;
  final List<String> beatRhythmTypes;
  final String webPageUrl;

  bool get vocalModeEnabled => vocalMode != 'off';

  Map<String, Object?> toMap() {
    return {
      'id': 1,
      'last_bpm': lastBpm,
      'time_signature': timeSignature,
      'accent_sound_id': accentSoundId,
      'normal_sound_id': normalSoundId,
      'vocal_mode_enabled': vocalModeEnabled ? 1 : 0,
      'voice_mode': vocalMode,
      'subdivision_type': subdivisionType,
      'beat_rhythm_types': beatRhythmTypes.join(','),
      'web_page_url': webPageUrl,
    };
  }

  factory PersistedSettings.fromMap(Map<String, Object?> map) {
    final voiceMode = map['voice_mode'] as String?;
    final vocalEnabled = ((map['vocal_mode_enabled'] as int?) ?? 0) == 1;

    return PersistedSettings(
      lastBpm: (map['last_bpm'] as int?) ?? 120,
      timeSignature: (map['time_signature'] as String?) ?? '4/4',
      accentSoundId: (map['accent_sound_id'] as String?) ?? 'accent',
      normalSoundId: (map['normal_sound_id'] as String?) ?? 'wood',
      vocalMode: voiceMode ?? (vocalEnabled ? 'english' : 'off'),
      subdivisionType: (map['subdivision_type'] as int?) ?? 0,
      beatRhythmTypes: _splitTokens(map['beat_rhythm_types'] as String?),
      webPageUrl: (map['web_page_url'] as String?) ?? kDefaultWebPageUrl,
    );
  }
}

class PracticeLog {
  const PracticeLog({
    required this.id,
    required this.date,
    required this.durationSeconds,
    required this.averageBpm,
  });

  final int id;
  final DateTime date;
  final int durationSeconds;
  final int averageBpm;

  factory PracticeLog.fromMap(Map<String, Object?> map) {
    return PracticeLog(
      id: (map['id'] as int?) ?? 0,
      date: DateTime.parse(
        (map['date'] as String?) ?? DateTime.now().toIso8601String(),
      ),
      durationSeconds: (map['duration_seconds'] as int?) ?? 0,
      averageBpm: (map['average_bpm'] as int?) ?? 0,
    );
  }
}

class PracticeDaySummary {
  const PracticeDaySummary({
    required this.date,
    required this.totalSeconds,
    required this.sessionCount,
  });

  final DateTime date;
  final int totalSeconds;
  final int sessionCount;

  factory PracticeDaySummary.fromMap(Map<String, Object?> map) {
    final rawDate = (map['day'] as String?) ?? DateTime.now().toIso8601String();
    final parts = rawDate.split('-');
    final year = parts.isNotEmpty ? int.tryParse(parts[0]) : null;
    final month = parts.length > 1 ? int.tryParse(parts[1]) : null;
    final day = parts.length > 2 ? int.tryParse(parts[2]) : null;

    return PracticeDaySummary(
      date: DateTime(
        year ?? DateTime.now().year,
        month ?? DateTime.now().month,
        day ?? DateTime.now().day,
      ),
      totalSeconds: (map['total_seconds'] as int?) ?? 0,
      sessionCount: (map['session_count'] as int?) ?? 0,
    );
  }
}

class SavedMetronomePreset {
  const SavedMetronomePreset({
    required this.id,
    required this.name,
    required this.bpm,
    required this.timeSignature,
    required this.beatsPerBar,
    required this.noteValue,
    required this.beatPattern,
    required this.beatRhythmTypes,
    required this.subdivisionType,
    required this.timerEnabled,
    required this.timerSeconds,
    required this.accentSoundId,
    required this.normalSoundId,
    required this.vocalMode,
  });

  final int? id;
  final String name;
  final int bpm;
  final String timeSignature;
  final int beatsPerBar;
  final int noteValue;
  final List<String> beatPattern;
  final List<String> beatRhythmTypes;
  final int subdivisionType;
  final bool timerEnabled;
  final int timerSeconds;
  final String accentSoundId;
  final String normalSoundId;
  final String vocalMode;

  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'bpm': bpm,
      'time_signature': timeSignature,
      'beats_per_bar': beatsPerBar,
      'note_value': noteValue,
      'beat_pattern': beatPattern.join(','),
      'beat_rhythm_types': beatRhythmTypes.join(','),
      'subdivision_type': subdivisionType,
      'timer_enabled': timerEnabled ? 1 : 0,
      'timer_seconds': timerSeconds,
      'accent_sound_id': accentSoundId,
      'normal_sound_id': normalSoundId,
      'voice_mode': vocalMode,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }

  factory SavedMetronomePreset.fromMap(Map<String, Object?> map) {
    return SavedMetronomePreset(
      id: map['id'] as int?,
      name: (map['name'] as String?) ?? 'Untitled',
      bpm: (map['bpm'] as int?) ?? 120,
      timeSignature: (map['time_signature'] as String?) ?? '4/4',
      beatsPerBar: (map['beats_per_bar'] as int?) ?? 4,
      noteValue: (map['note_value'] as int?) ?? 4,
      beatPattern: _splitTokens(map['beat_pattern'] as String?),
      beatRhythmTypes: _splitTokens(map['beat_rhythm_types'] as String?),
      subdivisionType: (map['subdivision_type'] as int?) ?? 0,
      timerEnabled: ((map['timer_enabled'] as int?) ?? 0) == 1,
      timerSeconds: (map['timer_seconds'] as int?) ?? 0,
      accentSoundId: (map['accent_sound_id'] as String?) ?? 'accent',
      normalSoundId: (map['normal_sound_id'] as String?) ?? 'wood',
      vocalMode: (map['voice_mode'] as String?) ?? 'off',
    );
  }
}

class MetronomeDatabase {
  MetronomeDatabase._();

  static final MetronomeDatabase instance = MetronomeDatabase._();

  Database? _database;

  Future<Database> get database async {
    final existing = _database;
    if (existing != null) {
      return existing;
    }

    final dbPath = await getDatabasesPath();
    final database = await openDatabase(
      p.join(dbPath, 'pulse_grid.db'),
      version: 4,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE Settings (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            last_bpm INTEGER NOT NULL,
            time_signature TEXT NOT NULL,
            accent_sound_id TEXT NOT NULL,
            normal_sound_id TEXT NOT NULL,
            vocal_mode_enabled INTEGER NOT NULL DEFAULT 0,
            voice_mode TEXT NOT NULL DEFAULT 'off',
            subdivision_type INTEGER NOT NULL DEFAULT 0,
            beat_rhythm_types TEXT NOT NULL DEFAULT '',
            web_page_url TEXT NOT NULL DEFAULT '$kDefaultWebPageUrl'
          )
        ''');
        await db.execute('''
          CREATE TABLE PracticeLogs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date TEXT NOT NULL,
            duration_seconds INTEGER NOT NULL,
            average_bpm INTEGER NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_practice_logs_date ON PracticeLogs(date)',
        );
        await _createSavedConfigsTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createSavedConfigsTable(db);
        }
        if (oldVersion < 3) {
          await _addColumnIfMissing(
            db,
            tableName: 'Settings',
            columnName: 'web_page_url',
            definition: "TEXT NOT NULL DEFAULT '$kDefaultWebPageUrl'",
          );
        }
        if (oldVersion < 4) {
          await _addColumnIfMissing(
            db,
            tableName: 'Settings',
            columnName: 'beat_rhythm_types',
            definition: "TEXT NOT NULL DEFAULT ''",
          );
          await _addColumnIfMissing(
            db,
            tableName: 'SavedConfigs',
            columnName: 'beat_rhythm_types',
            definition: "TEXT NOT NULL DEFAULT ''",
          );
        }
      },
    );

    _database = database;
    return database;
  }

  Future<Database?> _tryDatabase() async {
    try {
      return await database;
    } on StateError catch (error) {
      if (error.message.contains('databaseFactory not initialized')) {
        return null;
      }
      rethrow;
    }
  }

  Future<PersistedSettings?> loadSettings() async {
    final db = await _tryDatabase();
    if (db == null) {
      return null;
    }

    final rows = await db.query('Settings', limit: 1);
    if (rows.isEmpty) {
      return null;
    }
    return PersistedSettings.fromMap(rows.first);
  }

  Future<void> saveSettings(PersistedSettings settings) async {
    final db = await _tryDatabase();
    if (db == null) {
      return;
    }

    await db.insert(
      'Settings',
      settings.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> addPracticeLog({
    required DateTime date,
    required int durationSeconds,
    required int averageBpm,
  }) async {
    if (durationSeconds <= 0) {
      return;
    }

    final db = await _tryDatabase();
    if (db == null) {
      return;
    }

    await db.insert('PracticeLogs', {
      'date': date.toIso8601String(),
      'duration_seconds': durationSeconds,
      'average_bpm': averageBpm,
    });
  }

  Future<Duration> todayTotal(DateTime now) async {
    final db = await _tryDatabase();
    if (db == null) {
      return Duration.zero;
    }

    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));
    final rows = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(duration_seconds), 0) AS total
      FROM PracticeLogs
      WHERE date >= ? AND date < ?
      ''',
      [start.toIso8601String(), end.toIso8601String()],
    );
    final totalSeconds = (rows.first['total'] as int?) ?? 0;
    return Duration(seconds: totalSeconds);
  }

  Future<List<PracticeLog>> recentPracticeLogs({int limit = 6}) async {
    final db = await _tryDatabase();
    if (db == null) {
      return const [];
    }

    final rows = await db.query(
      'PracticeLogs',
      orderBy: 'date DESC',
      limit: limit,
    );
    return rows.map(PracticeLog.fromMap).toList();
  }

  Future<List<PracticeDaySummary>> dailyPracticeSummaries({
    required DateTime start,
    required DateTime end,
  }) async {
    final db = await _tryDatabase();
    if (db == null) {
      return const [];
    }

    final startOfDay = DateTime(start.year, start.month, start.day);
    final endExclusive = DateTime(
      end.year,
      end.month,
      end.day,
    ).add(const Duration(days: 1));
    final rows = await db.rawQuery(
      '''
      SELECT
        substr(date, 1, 10) AS day,
        COALESCE(SUM(duration_seconds), 0) AS total_seconds,
        COUNT(*) AS session_count
      FROM PracticeLogs
      WHERE date >= ? AND date < ?
      GROUP BY day
      ORDER BY day ASC
      ''',
      [startOfDay.toIso8601String(), endExclusive.toIso8601String()],
    );
    return rows.map(PracticeDaySummary.fromMap).toList();
  }

  Future<List<PracticeLog>> practiceLogsForDay(DateTime day) async {
    final db = await _tryDatabase();
    if (db == null) {
      return const [];
    }

    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    final rows = await db.query(
      'PracticeLogs',
      where: 'date >= ? AND date < ?',
      whereArgs: [start.toIso8601String(), end.toIso8601String()],
      orderBy: 'date DESC',
    );
    return rows.map(PracticeLog.fromMap).toList();
  }

  Future<List<SavedMetronomePreset>> loadSavedPresets() async {
    final db = await _tryDatabase();
    if (db == null) {
      return const [];
    }

    final rows = await db.query('SavedConfigs', orderBy: 'updated_at DESC');
    return rows.map(SavedMetronomePreset.fromMap).toList();
  }

  Future<void> savePreset(SavedMetronomePreset preset) async {
    final db = await _tryDatabase();
    if (db == null) {
      return;
    }

    await db.insert(
      'SavedConfigs',
      preset.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deletePreset(int id) async {
    final db = await _tryDatabase();
    if (db == null) {
      return;
    }

    await db.delete('SavedConfigs', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> _createSavedConfigsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS SavedConfigs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        bpm INTEGER NOT NULL,
        time_signature TEXT NOT NULL,
        beats_per_bar INTEGER NOT NULL,
        note_value INTEGER NOT NULL,
        beat_pattern TEXT NOT NULL,
        beat_rhythm_types TEXT NOT NULL DEFAULT '',
        subdivision_type INTEGER NOT NULL DEFAULT 0,
        timer_enabled INTEGER NOT NULL DEFAULT 0,
        timer_seconds INTEGER NOT NULL DEFAULT 0,
        accent_sound_id TEXT NOT NULL,
        normal_sound_id TEXT NOT NULL,
        voice_mode TEXT NOT NULL DEFAULT 'off',
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_saved_configs_updated_at ON SavedConfigs(updated_at)',
    );
  }

  static Future<void> _addColumnIfMissing(
    Database db, {
    required String tableName,
    required String columnName,
    required String definition,
  }) async {
    final columns = await db.rawQuery('PRAGMA table_info($tableName)');
    final exists = columns.any((column) => column['name'] == columnName);
    if (!exists) {
      await db.execute(
        'ALTER TABLE $tableName ADD COLUMN $columnName $definition',
      );
    }
  }
}

List<String> _splitTokens(String? raw) {
  return (raw ?? '')
      .split(',')
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList();
}
