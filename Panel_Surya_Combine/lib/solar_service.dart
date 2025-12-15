import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// Conditional imports untuk database
import 'database_stub.dart'
    if (dart.library.io) 'database_mobile.dart'
    if (dart.library.html) 'database_web.dart';

class SolarService {
  // --- KONFIGURASI FIREBASE ---
  // Kita gunakan REST API agar tidak perlu setup google-services.json yang ribet
  final String _baseUrl = "https://surya-panel-default-rtdb.asia-southeast1.firebasedatabase.app/panel_surya_01.json";
  final String _authKey = "O7dnWOEJbhOxCgaecBgsTeF05iAXU13HeNaDFNIC"; // Database Secret Anda
  
  DatabaseInterface _database = DatabaseInterface();
  final FlutterLocalNotificationsPlugin _notifPlugin = FlutterLocalNotificationsPlugin();
  Timer? _monitoringTimer;
  int _notificationIdCounter = 0;
  
  // Variabel untuk mencegah Spam Notifikasi
  DateTime? _lastDustNotifTime;
  DateTime? _lastRainNotifTime;

  // Singleton pattern (agar service hanya dibuat sekali)
  static final SolarService _instance = SolarService._internal();
  factory SolarService() => _instance;
  SolarService._internal();

  // 1. INITIALIZE (DB & Notifikasi)
  Future<void> init() async {
    // A. Setup Database (SQLite untuk mobile, SharedPreferences untuk web)
    await _database.init();

    // B. Setup Local Notification (hanya untuk mobile, skip untuk web)
    if (!kIsWeb) {
      const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const InitializationSettings initSettings = InitializationSettings(android: androidSettings);
      await _notifPlugin.initialize(initSettings);
    }
  }

  // 2. AMBIL DATA DARI FIREBASE (Monitoring)
  Future<Map<String, dynamic>?> fetchData() async {
    try {
      // Tambahkan ?auth=KEY untuk keamanan
      final response = await http.get(
        Uri.parse("$_baseUrl?auth=$_authKey")
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('Request timeout - tidak dapat terhubung ke server');
        },
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map<String, dynamic>) {
          return data;
        }
      } else {
        print("Error Fetching Data: Status ${response.statusCode}");
      }
    } on TimeoutException catch (e) {
      print("Timeout Error: $e");
    } on http.ClientException catch (e) {
      print("Network Error: $e");
    } catch (e) {
      print("Error Fetching Data: $e");
    }
    return null;
  }

  // 3. KIRIM PERINTAH (Controlling)
  Future<bool> sendCommand(String command) async {
    try {
      // Kita update path /control/command
      final url = "https://surya-panel-default-rtdb.asia-southeast1.firebasedatabase.app/panel_surya_01/control.json?auth=$_authKey";
      
      final response = await http.patch(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({"command": command}),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('Request timeout - tidak dapat terhubung ke server');
        },
      );

      // Jika command adalah AUTO_ON atau AUTO_OFF, sinkronkan status ke Firebase
      if (command == "AUTO_ON" || command == "AUTO_OFF") {
        await _syncAutoModeStatus(command == "AUTO_ON");
      }

      return response.statusCode == 200;
    } on TimeoutException catch (e) {
      print("Timeout Error Sending Command: $e");
      return false;
    } on http.ClientException catch (e) {
      print("Network Error Sending Command: $e");
      return false;
    } catch (e) {
      print("Error Sending Command: $e");
      return false;
    }
  }

  // Sinkronisasi status autoMode ke Firebase
  Future<void> _syncAutoModeStatus(bool isAutoMode) async {
    try {
      final url = "https://surya-panel-default-rtdb.asia-southeast1.firebasedatabase.app/panel_surya_01/status/autoMode.json?auth=$_authKey";
      await http.patch(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(isAutoMode),
      ).timeout(const Duration(seconds: 5));
    } catch (e) {
      print("Error syncing autoMode status: $e");
    }
  }

  // Ambil status autoMode dari Firebase
  Future<bool?> getAutoModeStatus() async {
    try {
      final url = "https://surya-panel-default-rtdb.asia-southeast1.firebasedatabase.app/panel_surya_01/status/autoMode.json?auth=$_authKey";
      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 5),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is bool) {
          return data;
        } else if (data is String) {
          return data.toLowerCase() == 'true';
        }
      }
    } catch (e) {
      print("Error getting autoMode status: $e");
    }
    return null;
  }

  // 4. LOGIKA MONITORING OTOMATIS (Polling)
  void startBackgroundMonitoring() {
    // Cancel timer yang sudah ada jika ada
    _monitoringTimer?.cancel();
    
    _monitoringTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      final data = await fetchData();
      if (data != null && data['status'] != null) {
        final status = data['status'];
        
        // Parsing Data dengan aman (default value jika null)
        double debu = 0.0;
        if (status['debu'] != null) {
          debu = double.tryParse(status['debu'].toString()) ?? 0.0;
        }
        
        bool hujan = status['hujan'] is bool 
            ? status['hujan'] as bool 
            : (status['hujan']?.toString().toLowerCase() == 'true');
        
        String state = status['state']?.toString() ?? "IDLE";

        _checkForAlerts(debu, hujan, state);
      }
    });
  }
  
  // Method untuk stop monitoring (optional, untuk cleanup)
  void stopBackgroundMonitoring() {
    _monitoringTimer?.cancel();
    _monitoringTimer = null;
  }

  // 5. CEK APAKAH PERLU NOTIFIKASI
  void _checkForAlerts(double debu, bool hujan, String state) {
    DateTime now = DateTime.now();

    // A. Alert Debu Tinggi (Jika > 0.20 dan belum ada notif 1 jam terakhir)
    if (debu > 0.20) {
      if (_lastDustNotifTime == null || now.difference(_lastDustNotifTime!).inMinutes > 60) {
        _showNotification("⚠️ Debu Terdeteksi!", "Kadar debu: $debu. Pembersihan Otomatis mungkin dimulai.");
        _lastDustNotifTime = now;
      }
    }

    // B. Alert Hujan (Jika hujan dan mesin sedang/baru saja Stop Darurat)
    if (hujan && state == "RAIN_STOP") {
      if (_lastRainNotifTime == null || now.difference(_lastRainNotifTime!).inMinutes > 30) {
        _showNotification("⛔ Hujan Turun!", "Sistem dimatikan demi keamanan.");
        _lastRainNotifTime = now;
      }
    }
  }

  // 6. TAMPILKAN & SIMPAN NOTIFIKASI
  Future<void> _showNotification(String title, String body) async {
    try {
      // Simpan ke database (SQLite untuk mobile, SharedPreferences untuk web)
      await _database.insertLog(title, body, DateTime.now().toIso8601String());

      // Generate unique notification ID
      final notificationId = _notificationIdCounter++;
      if (_notificationIdCounter > 1000000) {
        _notificationIdCounter = 0; // Reset untuk menghindari overflow
      }

      // Munculkan notifikasi hanya untuk mobile (web tidak support local notifications)
      if (!kIsWeb) {
        const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
          'solar_channel', 'Solar Alerts',
          importance: Importance.max, 
          priority: Priority.high,
          channelShowBadge: true,
        );
        const NotificationDetails details = NotificationDetails(android: androidDetails);
        await _notifPlugin.show(notificationId, title, body, details);
      } else {
        // Untuk web, kita bisa menggunakan browser notification API di masa depan
        print("Notification: $title - $body");
      }
    } catch (e) {
      print("Error showing notification: $e");
    }
  }

  // 7. AMBIL HISTORY LOG
  Future<List<Map<String, dynamic>>> getLogs() async {
    try {
      return await _database.getLogs();
    } catch (e) {
      print("Error getting logs: $e");
      return [];
    }
  }

  // 8. MANAJEMEN JADWAL PEMBERSIHAN
  Future<void> addSchedule(String time, int duration, bool isActive) async {
    await _database.insertSchedule(time, duration, isActive);
  }

  Future<List<Map<String, dynamic>>> getSchedules() async {
    try {
      return await _database.getSchedules();
    } catch (e) {
      print("Error getting schedules: $e");
      return [];
    }
  }

  Future<void> updateSchedule(int id, String time, int duration, bool isActive) async {
    await _database.updateSchedule(id, time, duration, isActive);
  }

  Future<void> deleteSchedule(int id) async {
    await _database.deleteSchedule(id);
  }

  // 9. MANAJEMEN TIMER MODE
  Future<bool> setTimerMode(bool enabled) async {
    try {
      final url = "https://surya-panel-default-rtdb.asia-southeast1.firebasedatabase.app/panel_surya_01/status/timerMode.json?auth=$_authKey";
      final response = await http.patch(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(enabled),
      ).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (e) {
      print("Error setting timer mode: $e");
      return false;
    }
  }

  Future<bool> setTimerInterval(int intervalMinutes) async {
    try {
      // Validasi range
      if (intervalMinutes < 5 || intervalMinutes > 180) {
        print("Error: Timer interval out of range (5-180): $intervalMinutes");
        return false;
      }

      // Firebase REST API: Untuk update single value
      // Gunakan PATCH dengan path parent dan kirim JSON object dengan key
      // Sama seperti cara update command di sendCommand
      final url = "https://surya-panel-default-rtdb.asia-southeast1.firebasedatabase.app/panel_surya_01/status.json?auth=$_authKey";
      
      // PATCH dengan path parent, kirim JSON object dengan key timerInterval
      final response = await http.patch(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        // Kirim sebagai JSON object dengan key timerInterval
        body: json.encode({"timerInterval": intervalMinutes}),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('Request timeout - tidak dapat terhubung ke server');
        },
      );

      print("Set timer interval: status=${response.statusCode}, body=${response.body}");
      
      // Firebase REST API mengembalikan data yang di-set jika berhasil
      // Response body akan berupa number (sebagai string) jika berhasil
      if (response.statusCode == 200 || response.statusCode == 204) {
        // Parse response untuk verifikasi
        final responseBody = response.body.trim();
        try {
          // Firebase mengembalikan number sebagai string, parse untuk verifikasi
          final returnedValue = int.tryParse(responseBody);
          if (returnedValue == intervalMinutes || responseBody == intervalMinutes.toString()) {
            print("✅ Timer interval berhasil diubah menjadi $intervalMinutes menit");
            return true;
          } else {
            print("⚠️ Timer interval response mismatch: expected $intervalMinutes, got $responseBody");
            // Tetap return true karena status code 200 (Firebase mungkin mengembalikan format berbeda)
            return true;
          }
        } catch (e) {
          // Jika parsing gagal, tetap anggap sukses jika status code 200
          print("⚠️ Could not parse response, but status is 200: $responseBody");
          return true;
        }
      } else {
        print("❌ Failed to set timer interval: ${response.statusCode} - ${response.body}");
        return false;
      }
    } on TimeoutException catch (e) {
      print("Timeout Error Setting Timer Interval: $e");
      return false;
    } on http.ClientException catch (e) {
      print("Network Error Setting Timer Interval: $e");
      return false;
    } catch (e) {
      print("Error setting timer interval: $e");
      return false;
    }
  }

  // Ambil status timerMode dari Firebase
  Future<bool?> getTimerModeStatus() async {
    try {
      final url = "https://surya-panel-default-rtdb.asia-southeast1.firebasedatabase.app/panel_surya_01/status/timerMode.json?auth=$_authKey";
      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 5),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is bool) {
          return data;
        } else if (data is String) {
          return data.toLowerCase() == 'true';
        }
      }
    } catch (e) {
      print("Error getting timerMode status: $e");
    }
    return null;
  }
}