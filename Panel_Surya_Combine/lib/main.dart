import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'solar_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final service = SolarService();
  await service.init();
  service.startBackgroundMonitoring();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: const SolarDashboard(),
    );
  }
}

class SolarDashboard extends StatefulWidget {
  const SolarDashboard({super.key});

  @override
  State<SolarDashboard> createState() => _SolarDashboardState();
}

class _SolarDashboardState extends State<SolarDashboard> {
  final SolarService _service = SolarService();
  Timer? _uiTimer;
  
  // Data State
  double debu = 0.0;
  bool hujan = false;
  String stateMesin = "CONNECTING...";
  bool isAutoMode = true; // true = Otomatis, false = Timer
  int timerInterval = 15; // menit (hanya untuk Timer mode)
  List<Map<String, dynamic>> logs = [];
  bool isLoading = false;
  String? errorMessage;
  bool _isUpdatingMode = false; // Flag untuk mencegah refresh overwrite saat update mode

  @override
  void initState() {
    super.initState();
    // Refresh lebih cepat untuk notifikasi real-time (1 detik)
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _refreshData();
    });
    _refreshData();
    _loadModeStatus();
  }

  Future<void> _loadModeStatus() async {
    // Load mode dari Firebase (autoMode = true berarti Otomatis, timerMode = true berarti Timer)
    final autoStatus = await _service.getAutoModeStatus();
    final timerStatus = await _service.getTimerModeStatus();
    if (mounted) {
      setState(() {
        // Jika timerMode aktif, maka isAutoMode = false, sebaliknya
        if (timerStatus == true) {
          isAutoMode = false;
        } else if (autoStatus == true) {
          isAutoMode = true;
        }
      });
    }
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    _timerIntervalDebounce?.cancel();
    super.dispose();
  }

  Future<void> _refreshData() async {
    if (!mounted) return;
    
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
    final data = await _service.fetchData();
    final history = await _service.getLogs();

      if (mounted) {
        if (data != null && data['status'] != null) {
          // Update mode dari Firebase (Otomatis atau Timer)
          bool firebaseTimerMode = false;
          
          if (data['status']['timerMode'] != null) {
            firebaseTimerMode = data['status']['timerMode'] is bool
                ? data['status']['timerMode'] as bool
                : data['status']['timerMode'].toString().toLowerCase() == 'true';
          }
          
          // Tentukan mode: Jika timerMode aktif, maka mode Timer, sebaliknya mode Otomatis
          // Jangan update mode jika sedang dalam proses update (untuk mencegah toggle kembali)
          if (!_isUpdatingMode) {
            setState(() {
              isAutoMode = !firebaseTimerMode; // Jika timerMode aktif, maka bukan auto mode
            });
          }

          // Update timerInterval dari Firebase jika ada
          if (data['status']['timerInterval'] != null) {
            final ti = int.tryParse(data['status']['timerInterval'].toString());
            if (ti != null && ti > 0) {
              setState(() {
                timerInterval = ti;
              });
            }
          }

      setState(() {
        debu = double.tryParse(data['status']['debu'].toString()) ?? 0.0;
        hujan = data['status']['hujan'] ?? false;
        stateMesin = data['status']['state'] ?? "UNKNOWN";
        logs = history;
            isLoading = false;
            errorMessage = null;
          });
        } else {
          setState(() {
            isLoading = false;
            errorMessage = "Tidak dapat mengambil data dari ESP32";
            stateMesin = "DISCONNECTED";
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoading = false;
          errorMessage = "Error: ${e.toString()}";
          stateMesin = "ERROR";
        });
      }
    }
  }

  Future<void> _toggleMode(bool isAuto) async {
    // Set flag untuk mencegah refresh overwrite
    _isUpdatingMode = true;
    
    // Update UI immediately (optimistic update) untuk responsivitas
    setState(() {
      isAutoMode = isAuto;
    });
    
    try {
      // Set mode di Firebase: jika Otomatis, aktifkan autoMode dan nonaktifkan timerMode
      // Jika Timer, aktifkan timerMode dan nonaktifkan autoMode
      if (isAuto) {
        // Mode Otomatis: aktifkan autoMode, nonaktifkan timerMode
        await _service.sendCommand("AUTO_ON");
        await _service.setTimerMode(false);
      } else {
        // Mode Timer: nonaktifkan autoMode, aktifkan timerMode
        await _service.sendCommand("AUTO_OFF");
        await _service.setTimerMode(true);
      }
      
      // Tunggu sebentar untuk memastikan Firebase sudah update
      await Future.delayed(const Duration(milliseconds: 800));
      
      // Refresh data untuk sinkronisasi (tanpa overwrite mode karena flag masih true)
      await _refreshData();
      
      // Setelah refresh selesai, reset flag dan pastikan mode sesuai dengan Firebase
      _isUpdatingMode = false;
      
      // Verifikasi mode dari Firebase untuk memastikan sinkronisasi
      final data = await _service.fetchData();
      if (data != null && data['status'] != null && mounted) {
        bool firebaseTimerMode = false;
        if (data['status']['timerMode'] != null) {
          firebaseTimerMode = data['status']['timerMode'] is bool
              ? data['status']['timerMode'] as bool
              : data['status']['timerMode'].toString().toLowerCase() == 'true';
        }
        
        // Update mode dari Firebase (sekarang sudah aman karena flag sudah false)
        setState(() {
          isAutoMode = !firebaseTimerMode;
        });
      }
    } catch (e) {
      // Jika error, rollback ke mode sebelumnya
      if (mounted) {
        setState(() {
          isAutoMode = !isAuto; // Kembalikan ke mode sebelumnya
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Gagal mengubah mode: ${e.toString()}"),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.red,
          ),
        );
      }
      _isUpdatingMode = false;
    }
  }

  Timer? _timerIntervalDebounce;
  
  Future<void> _changeTimerInterval(int value) async {
    // Validasi range
    if (value < 5) value = 5;
    if (value > 180) value = 180;
    
    // Update UI immediately untuk responsivitas
    setState(() {
      timerInterval = value;
    });
    
    // Cancel debounce timer sebelumnya jika ada
    _timerIntervalDebounce?.cancel();
    
    // Debounce: tunggu 500ms sebelum mengirim ke Firebase
    // Ini mencegah spam API saat user drag slider
    _timerIntervalDebounce = Timer(const Duration(milliseconds: 500), () async {
      if (!mounted) return;
      
      try {
        final success = await _service.setTimerInterval(value);
        if (mounted) {
          if (success) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("Interval diubah menjadi $value menit"),
                duration: const Duration(seconds: 1),
                backgroundColor: Colors.green,
              ),
            );
            // Refresh data untuk sinkronisasi
            Future.delayed(const Duration(milliseconds: 500), _refreshData);
          } else {
            // Rollback ke nilai sebelumnya jika gagal
            final currentData = await _service.fetchData();
            if (currentData != null && currentData['status'] != null && currentData['status']['timerInterval'] != null) {
              final ti = int.tryParse(currentData['status']['timerInterval'].toString());
              if (ti != null && ti >= 5 && ti <= 180) {
                setState(() {
                  timerInterval = ti;
                });
              }
            }
            
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Gagal mengubah interval. Periksa koneksi internet."),
                duration: Duration(seconds: 2),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } catch (e) {
        print("Error in _changeTimerInterval: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Error: ${e.toString()}"),
              duration: const Duration(seconds: 2),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    });
  }


  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 600;
    final isVerySmallScreen = screenWidth < 400;
    
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: SafeArea(
        child: Column(
          children: [
            // HEADER BIRU
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(
                horizontal: isSmallScreen ? 16 : 20,
                vertical: isSmallScreen ? 16 : 20,
              ),
              decoration: const BoxDecoration(
                color: Color(0xFF2196F3), // Biru
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: const Text(
                  "PANEL SURYA CLEANING",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),

            // CONTENT - Full screen layout tanpa scroll
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: kIsWeb ? 800 : double.infinity,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ROW 1: Tiga kartu horizontal (atau vertical di layar kecil)
                      isSmallScreen
                          ? Column(
                              children: [
                                _buildDustCard(isSmallScreen, isVerySmallScreen),
                                const SizedBox(height: 12),
                                _buildStateCard(isSmallScreen, isVerySmallScreen),
                              ],
                            )
                          : Row(
                              children: [
                                Expanded(child: _buildDustCard(isSmallScreen, isVerySmallScreen)),
                                const SizedBox(width: 12),
                                Expanded(child: _buildStateCard(isSmallScreen, isVerySmallScreen)),
                              ],
                            ),

                      SizedBox(height: isSmallScreen ? 12 : 16),

                      // ROW 2: Card Mode & Kontrol (gabungan untuk efisiensi)
                      _buildModeAndControlCard(isSmallScreen, isVerySmallScreen),

                      SizedBox(height: isSmallScreen ? 12 : 16),

                      // ROW 3: Card Riwayat - Expanded untuk menyesuaikan tinggi
                      Expanded(
                        child: _buildWarningCard(isSmallScreen, isVerySmallScreen),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDustCard(bool isSmallScreen, bool isVerySmallScreen) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFF9800), // Orange
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              "Tingkat Kebersihan",
              style: TextStyle(
                color: Colors.white,
                fontSize: isVerySmallScreen ? 12 : (isSmallScreen ? 13 : 14),
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      "${(debu * 1000).toStringAsFixed(0)} µg/m³",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isVerySmallScreen ? 14 : (isSmallScreen ? 16 : 18),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  debu > 0.20 ? Icons.warning : Icons.check_circle,
                  color: Colors.white,
                  size: isSmallScreen ? 20 : 24,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeAndControlCard(bool isSmallScreen, bool isVerySmallScreen) {
    // State yang bisa start: hanya IDLE
    final canStart = stateMesin == "IDLE";
    // State yang sedang berjalan: semua state selain IDLE dan RAIN_STOP
    final isRunning = stateMesin != "IDLE" && 
                     stateMesin != "RAIN_STOP" && 
                     stateMesin != "DISCONNECTED" &&
                     stateMesin != "CONNECTING...";
    
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
      decoration: BoxDecoration(
        color: const Color(0xFF2196F3), // Biru
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Mode Pembersihan dengan Toggle
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  "Mode Pembersihan",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: isVerySmallScreen ? 12 : (isSmallScreen ? 13 : 14),
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return ScaleTransition(scale: animation, child: child);
                },
                child: Switch(
                  key: ValueKey(isAutoMode),
                  value: isAutoMode,
                  onChanged: _isUpdatingMode ? null : _toggleMode,
                  activeColor: Colors.white,
                  activeTrackColor: Colors.white70,
                  inactiveThumbColor: Colors.white,
                  inactiveTrackColor: Colors.white38,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (Widget child, Animation<double> animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.1, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: Row(
              key: ValueKey(isAutoMode),
              children: [
                Icon(
                  isAutoMode ? Icons.auto_mode : Icons.timer,
                  color: Colors.white70,
                  size: isSmallScreen ? 16 : 18,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    isAutoMode ? "Mode Otomatis (Berdasarkan Debu)" : "Mode Timer (Bersih Berkala)",
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: isVerySmallScreen ? 10 : (isSmallScreen ? 11 : 12),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          
          // Konten untuk Mode Timer
          if (!isAutoMode) ...[
            const SizedBox(height: 16),
            // Divider
            Container(
              height: 1,
              color: Colors.white.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            
            // Interval Slider (Compact)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Interval",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: isSmallScreen ? 12 : 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isSmallScreen ? 8 : 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    "$timerInterval mnt",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: isSmallScreen ? 12 : 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Slider(
              value: timerInterval.toDouble(),
              min: 5,
              max: 180,
              divisions: 35,
              label: "$timerInterval menit",
              onChangeStart: (val) {},
              onChanged: (val) {
                final newValue = val.round();
                if (newValue >= 5 && newValue <= 180) {
                  setState(() {
                    timerInterval = newValue;
                  });
                }
              },
              onChangeEnd: (val) {
                final newValue = val.round();
                if (newValue >= 5 && newValue <= 180) {
                  _changeTimerInterval(newValue);
                }
              },
              activeColor: Colors.white,
              inactiveColor: Colors.white54,
            ),
            
            const SizedBox(height: 12),
            
            // Kontrol Start/Stop (Compact)
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: canStart ? () => _kirimPerintah("START") : null,
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: Text(
                      "START",
                      style: TextStyle(fontSize: isSmallScreen ? 12 : 13),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(
                        vertical: isSmallScreen ? 8 : 10,
                      ),
                      disabledBackgroundColor: Colors.grey[600],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: isRunning || canStart ? () => _kirimPerintah("STOP") : null,
                    icon: const Icon(Icons.stop, size: 18),
                    label: Text(
                      "STOP",
                      style: TextStyle(fontSize: isSmallScreen ? 12 : 13),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(
                        vertical: isSmallScreen ? 8 : 10,
                      ),
                      disabledBackgroundColor: Colors.grey[600],
                    ),
                  ),
                ),
              ],
            ),
            
            // Status State (Compact)
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: _getStateColor(stateMesin).withOpacity(0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _getStateIcon(stateMesin),
                    color: _getStateColor(stateMesin),
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      _getStateDisplayName(stateMesin),
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: isSmallScreen ? 10 : 11,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStateCard(bool isSmallScreen, bool isVerySmallScreen) {
    final stateColor = _getStateColor(stateMesin);
    final stateIcon = _getStateIcon(stateMesin);
    final stateName = _getStateDisplayName(stateMesin);
    
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
      decoration: BoxDecoration(
        color: stateColor.withOpacity(0.9),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Status Mesin",
            style: TextStyle(
              color: Colors.white,
              fontSize: isVerySmallScreen ? 12 : (isSmallScreen ? 13 : 14),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                stateIcon,
                color: Colors.white,
                size: isSmallScreen ? 24 : 28,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    stateName,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: isVerySmallScreen ? 14 : (isSmallScreen ? 16 : 18),
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }


  // Helper untuk mendapatkan warna state
  Color _getStateColor(String state) {
    switch (state.toUpperCase()) {
      case "IDLE":
        return Colors.blue;
      case "PRE_WASH":
        return Colors.orange;
      case "MOVING_DOWN":
        return Colors.green;
      case "RINSING":
        return Colors.cyan;
      case "MOVING_UP":
        return Colors.green;
      case "RAIN_STOP":
        return Colors.red;
      case "DISCONNECTED":
      case "CONNECTING...":
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  // Helper untuk mendapatkan icon state
  IconData _getStateIcon(String state) {
    switch (state.toUpperCase()) {
      case "IDLE":
        return Icons.pause_circle;
      case "PRE_WASH":
        return Icons.water_drop;
      case "MOVING_DOWN":
        return Icons.arrow_downward;
      case "RINSING":
        return Icons.cleaning_services;
      case "MOVING_UP":
        return Icons.arrow_upward;
      case "RAIN_STOP":
        return Icons.warning;
      case "DISCONNECTED":
        return Icons.cloud_off;
      case "CONNECTING...":
        return Icons.sync;
      default:
        return Icons.help_outline;
    }
  }

  // Helper untuk mendapatkan nama display state
  String _getStateDisplayName(String state) {
    switch (state.toUpperCase()) {
      case "IDLE":
        return "Siap";
      case "PRE_WASH":
        return "Persiapan Cuci";
      case "MOVING_DOWN":
        return "Turun";
      case "RINSING":
        return "Bilas";
      case "MOVING_UP":
        return "Naik";
      case "RAIN_STOP":
        return "Stop Hujan";
      case "DISCONNECTED":
        return "Terputus";
      case "CONNECTING...":
        return "Menghubungkan...";
      default:
        return state;
    }
  }

  void _kirimPerintah(String cmd) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Mengirim $cmd..."))
    );
    
    try {
      bool success = await _service.sendCommand(cmd);
      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Perintah berhasil dikirim!"),
              backgroundColor: Colors.green,
            )
          );
          Future.delayed(const Duration(milliseconds: 500), _refreshData);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Gagal mengirim perintah. Periksa koneksi internet."),
              backgroundColor: Colors.red,
            )
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error: ${e.toString()}"),
            backgroundColor: Colors.red,
          )
        );
      }
    }
  }

  Widget _buildWarningCard(bool isSmallScreen, bool isVerySmallScreen) {
    // Sort logs terbaru di atas
    final sortedLogs = List<Map<String, dynamic>>.from(logs);
    sortedLogs.sort((a, b) {
      try {
        final timeA = DateTime.tryParse(a['time']?.toString() ?? '');
        final timeB = DateTime.tryParse(b['time']?.toString() ?? '');
        if (timeA != null && timeB != null) {
          return timeB.compareTo(timeA); // Terbaru di atas
        }
        return 0;
      } catch (e) {
        return 0;
      }
    });

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFF9800), // Orange
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.max, // Ubah ke max agar mengisi ruang yang tersedia
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Riwayat Notifikasi",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isSmallScreen ? 16 : 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (sortedLogs.isNotEmpty)
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isSmallScreen ? 6 : 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    "${sortedLogs.length}",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: isSmallScreen ? 11 : 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // Scrollable list untuk riwayat
          Expanded(
            child: sortedLogs.isEmpty
                ? Center(
                    child: Text(
                      "Belum ada notifikasi",
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: isSmallScreen ? 12 : 14,
                      ),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: sortedLogs.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final log = sortedLogs[index];
                      String displayTime = "10.21"; // Default
                      try {
                        final timeStr = log['time']?.toString() ?? '';
                        if (timeStr.isNotEmpty) {
                          final dateTime = DateTime.tryParse(timeStr);
                          if (dateTime != null) {
                            displayTime = "${dateTime.hour.toString().padLeft(2, '0')}.${dateTime.minute.toString().padLeft(2, '0')}";
                          } else if (timeStr.length >= 5) {
                            displayTime = timeStr.substring(0, 5).replaceAll(':', '.');
                          }
                        }
                      } catch (e) {
                        // Keep default
                      }
                      
                      String title = log['title']?.toString() ?? 'Unknown';
                      if (title.contains("Debu") || title.contains("debu")) {
                        title = "Debu Melebihi Batas";
                      } else if (title.contains("Hujan") || title.contains("hujan")) {
                        title = "Hujan Terdeteksi";
                      }

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.warning,
                            color: Colors.white,
                            size: isSmallScreen ? 18 : 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              title,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: isSmallScreen ? 12 : 14,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            displayTime,
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: isSmallScreen ? 10 : 12,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

}
