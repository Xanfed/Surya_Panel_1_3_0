import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseInterface {
  Database? _database;

  Future<void> init() async {
    _database = await openDatabase(
      join(await getDatabasesPath(), 'solar_logs.db'),
      onCreate: (db, version) {
        db.execute(
          "CREATE TABLE logs(id INTEGER PRIMARY KEY, title TEXT, body TEXT, time TEXT)",
        );
        db.execute(
          "CREATE TABLE schedules(id INTEGER PRIMARY KEY, time TEXT, duration INTEGER, isActive INTEGER)",
        );
      },
      version: 2,
      onUpgrade: (db, oldVersion, newVersion) {
        if (oldVersion < 2) {
          db.execute(
            "CREATE TABLE IF NOT EXISTS schedules(id INTEGER PRIMARY KEY, time TEXT, duration INTEGER, isActive INTEGER)",
          );
        }
      },
    );
  }

  Future<void> insertLog(String title, String body, String time) async {
    if (_database != null) {
      await _database!.insert('logs', {
        'title': title,
        'body': body,
        'time': time,
      });
    }
  }

  Future<List<Map<String, dynamic>>> getLogs() async {
    try {
      if (_database == null) return [];
      return await _database!.query('logs', orderBy: "time DESC", limit: 20);
    } catch (e) {
      print("Error getting logs: $e");
      return [];
    }
  }

  Future<void> insertSchedule(String time, int duration, bool isActive) async {
    if (_database != null) {
      await _database!.insert('schedules', {
        'time': time,
        'duration': duration,
        'isActive': isActive ? 1 : 0,
      });
    }
  }

  Future<List<Map<String, dynamic>>> getSchedules() async {
    try {
      if (_database == null) return [];
      return await _database!.query('schedules', orderBy: "time ASC");
    } catch (e) {
      print("Error getting schedules: $e");
      return [];
    }
  }

  Future<void> updateSchedule(int id, String time, int duration, bool isActive) async {
    if (_database != null) {
      await _database!.update(
        'schedules',
        {
          'time': time,
          'duration': duration,
          'isActive': isActive ? 1 : 0,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  Future<void> deleteSchedule(int id) async {
    if (_database != null) {
      await _database!.delete('schedules', where: 'id = ?', whereArgs: [id]);
    }
  }
}

