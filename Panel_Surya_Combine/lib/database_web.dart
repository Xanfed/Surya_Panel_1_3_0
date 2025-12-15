import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class DatabaseInterface {
  static const String _logsKey = 'solar_logs';
  static const String _schedulesKey = 'solar_schedules';

  Future<void> init() async {
    // Tidak perlu setup khusus untuk web, shared_preferences sudah siap
  }

  Future<void> insertLog(String title, String body, String time) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final logsJson = prefs.getStringList(_logsKey) ?? [];
      
      final newLog = {
        'id': DateTime.now().millisecondsSinceEpoch,
        'title': title,
        'body': body,
        'time': time,
      };
      
      logsJson.insert(0, json.encode(newLog));
      
      // Simpan maksimal 20 log terbaru
      if (logsJson.length > 20) {
        logsJson.removeRange(20, logsJson.length);
      }
      
      await prefs.setStringList(_logsKey, logsJson);
    } catch (e) {
      print("Error inserting log: $e");
    }
  }

  Future<List<Map<String, dynamic>>> getLogs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final logsJson = prefs.getStringList(_logsKey) ?? [];
      
      return logsJson.map((jsonStr) {
        try {
          final decoded = json.decode(jsonStr) as Map<String, dynamic>;
          return decoded;
        } catch (e) {
          return <String, dynamic>{};
        }
      }).toList();
    } catch (e) {
      print("Error getting logs: $e");
      return [];
    }
  }

  Future<void> insertSchedule(String time, int duration, bool isActive) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final schedulesJson = prefs.getStringList(_schedulesKey) ?? [];
      
      final newSchedule = {
        'id': DateTime.now().millisecondsSinceEpoch,
        'time': time,
        'duration': duration,
        'isActive': isActive,
      };
      
      schedulesJson.add(json.encode(newSchedule));
      await prefs.setStringList(_schedulesKey, schedulesJson);
    } catch (e) {
      print("Error inserting schedule: $e");
    }
  }

  Future<List<Map<String, dynamic>>> getSchedules() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final schedulesJson = prefs.getStringList(_schedulesKey) ?? [];
      
      return schedulesJson.map((jsonStr) {
        try {
          final decoded = json.decode(jsonStr) as Map<String, dynamic>;
          return decoded;
        } catch (e) {
          return <String, dynamic>{};
        }
      }).toList();
    } catch (e) {
      print("Error getting schedules: $e");
      return [];
    }
  }

  Future<void> updateSchedule(int id, String time, int duration, bool isActive) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final schedulesJson = prefs.getStringList(_schedulesKey) ?? [];
      
      final updated = schedulesJson.map((jsonStr) {
        try {
          final decoded = json.decode(jsonStr) as Map<String, dynamic>;
          if (decoded['id'] == id) {
            return json.encode({
              'id': id,
              'time': time,
              'duration': duration,
              'isActive': isActive,
            });
          }
          return jsonStr;
        } catch (e) {
          return jsonStr;
        }
      }).toList();
      
      await prefs.setStringList(_schedulesKey, updated);
    } catch (e) {
      print("Error updating schedule: $e");
    }
  }

  Future<void> deleteSchedule(int id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final schedulesJson = prefs.getStringList(_schedulesKey) ?? [];
      
      final filtered = schedulesJson.where((jsonStr) {
        try {
          final decoded = json.decode(jsonStr) as Map<String, dynamic>;
          return decoded['id'] != id;
        } catch (e) {
          return true;
        }
      }).toList();
      
      await prefs.setStringList(_schedulesKey, filtered);
    } catch (e) {
      print("Error deleting schedule: $e");
    }
  }
}

