# Ringkasan Integrasi ESP32 & Mobile App

## 📋 Struktur Mekanisme yang Dipahami

### 1. **ESP32 (Hardware Controller)**
- **Fungsi:** Mengontrol hardware (motor, pompa, sensor)
- **State Machine:** 6 state (IDLE, PRE_WASH, MOVING_DOWN, RINSING, MOVING_UP, RAIN_STOP)
- **Auto Start:** Otomatis start jika debu > 0.20 dan tidak hujan
- **Safety:** Priority tertinggi untuk rain stop

### 2. **Firebase RTDB (Cloud Bridge)**
- **Path Status:** `/panel_surya_01/status` (data dari ESP32)
- **Path Control:** `/panel_surya_01/control/command` (perintah dari mobile)
- **Update Interval:** ESP32 update setiap 1 detik

### 3. **Flutter App (Mobile/Web)**
- **Monitoring:** Baca data setiap 2 detik (UI) dan 5 detik (background)
- **Control:** Kirim command ke Firebase
- **Storage:** Simpan logs dan schedules lokal

## 🔄 Alur Komunikasi Lengkap

### ESP32 → Firebase → Mobile App
```
ESP32 (Sensor) 
  → Baca debu & hujan
  → Update state machine
  → Upload ke Firebase (/status)
    → Mobile app baca setiap 2 detik
    → Update UI dengan data terbaru
```

### Mobile App → Firebase → ESP32
```
Mobile App (User Action)
  → User tekan START/STOP/toggle
  → Kirim command ke Firebase (/control/command)
    → ESP32 baca setiap 1 detik (saat IDLE)
    → ESP32 proses command
    → ESP32 reset command ke "NONE" atau "RUNNING"
```

## ✅ Status Integrasi Saat Ini

### ESP32 (code.ino):
- ✅ State machine lengkap (6 state)
- ✅ Upload data ke Firebase setiap 1 detik
- ✅ Baca command START/STOP
- ✅ Auto start berdasarkan debu
- ✅ Safety rain stop
- ❌ **BELUM:** Support AUTO_ON/AUTO_OFF

### Flutter App:
- ✅ Baca data dari Firebase
- ✅ Kirim command START/STOP
- ✅ Kirim command AUTO_ON/AUTO_OFF
- ✅ Sinkronisasi autoMode dengan Firebase
- ✅ Menampilkan semua state dengan benar
- ✅ Kontrol manual berdasarkan state
- ✅ Responsive design

## 🔧 File yang Perlu Diupdate

### 1. **code.ino** (ESP32)
**File:** `code_improved.ino` (sudah dibuat)

**Perubahan:**
- ✅ Tambah variabel `autoModeEnabled`
- ✅ Tambah support command AUTO_ON
- ✅ Tambah support command AUTO_OFF
- ✅ Modifikasi auto start logic
- ✅ Set default autoMode di setup()
- ✅ Baca autoMode dari Firebase (optional sync)

**Cara Pakai:**
1. Copy isi `code_improved.ino` ke `code.ino`
2. Upload ke ESP32
3. Test dengan mobile app

### 2. **Flutter App**
**Status:** ✅ Sudah siap, tidak perlu perubahan

## 📊 Mapping State & Command

### State yang Dikirim ESP32:
| State Enum | String | Display Name | Warna |
|------------|--------|--------------|-------|
| STATE_IDLE | "IDLE" | "Siap" | Biru |
| STATE_PRE_WASH | "PRE_WASH" | "Persiapan Cuci" | Orange |
| STATE_MOVING_DOWN | "MOVING_DOWN" | "Turun" | Hijau |
| STATE_PAUSE_BOTTOM | "RINSING" | "Bilas" | Cyan |
| STATE_MOVING_UP | "MOVING_UP" | "Naik" | Hijau |
| STATE_RAIN_ABORT | "RAIN_STOP" | "Stop Hujan" | Merah |

### Command yang Diterima ESP32:
| Command | Kapan Valid | Aksi |
|---------|-------------|------|
| START | Saat IDLE | Mulai cleaning |
| STOP | Kapan saja | Force stop |
| AUTO_ON | Saat IDLE | Aktifkan auto mode |
| AUTO_OFF | Saat IDLE | Nonaktifkan auto mode |

## 🎯 Testing Checklist

### Test 1: State Machine
- [ ] ESP32 mengirim state dengan benar
- [ ] Mobile app menampilkan state dengan warna/icon yang sesuai
- [ ] State berubah sesuai alur: IDLE → PRE_WASH → MOVING_DOWN → RINSING → MOVING_UP → IDLE

### Test 2: Manual Control
- [ ] START hanya aktif saat IDLE
- [ ] START memulai cleaning process
- [ ] STOP bisa dipanggil kapan saja
- [ ] STOP menghentikan semua hardware

### Test 3: Auto Mode
- [ ] Toggle AUTO_ON → auto start aktif
- [ ] Toggle AUTO_OFF → auto start nonaktif
- [ ] Auto start bekerja saat AUTO_ON dan debu tinggi
- [ ] Auto start tidak bekerja saat AUTO_OFF

### Test 4: Safety
- [ ] Rain stop bekerja saat hujan terdeteksi
- [ ] Semua hardware mati saat rain stop
- [ ] State kembali ke IDLE setelah 5 detik

### Test 5: Sinkronisasi
- [ ] autoMode tersinkron antara mobile app dan ESP32
- [ ] State tersinkron real-time
- [ ] Command terkirim dan diproses dengan benar

## 📝 Catatan Penting

1. **Command Reset:**
   - ESP32 mengubah command menjadi "RUNNING" saat proses berjalan
   - ESP32 reset command menjadi "NONE" setelah selesai
   - Mencegah command diproses berulang kali

2. **Auto Mode:**
   - Default: true (sesuai behavior lama)
   - Bisa diubah dari mobile app atau Firebase Console
   - Auto start hanya bekerja jika autoModeEnabled = true

3. **State Priority:**
   - RAIN_STOP memiliki priority tertinggi
   - Jika hujan terdeteksi, semua state langsung berubah ke RAIN_STOP

4. **Timing:**
   - ESP32 update data: setiap 1 detik
   - Mobile app refresh UI: setiap 2 detik
   - Background monitoring: setiap 5 detik

## 🚀 Langkah Selanjutnya

1. **Update ESP32:**
   - Copy `code_improved.ino` ke `code.ino`
   - Upload ke ESP32
   - Test dengan mobile app

2. **Test Integrasi:**
   - Test semua command
   - Test auto mode toggle
   - Test state machine
   - Test safety features

3. **Optimasi (Optional):**
   - Tambah jadwal pembersihan di ESP32
   - Tambah timer mode di ESP32
   - Tambah fitur lainnya sesuai kebutuhan

