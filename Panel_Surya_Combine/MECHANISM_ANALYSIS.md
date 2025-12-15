# Analisis Mekanisme Project ESP32 & Mobile App

## 📊 Struktur Sistem

```
┌─────────────────┐         ┌──────────────────┐         ┌─────────────────┐
│   ESP32         │         │  Firebase RTDB    │         │  Flutter App    │
│  (Hardware)     │◀───────▶│  (Cloud Bridge)  │◀───────▶│  (Mobile/Web)   │
└─────────────────┘         └──────────────────┘         └─────────────────┘
     │                              │                              │
     │                              │                              │
     ▼                              ▼                              ▼
┌──────────┐                ┌──────────────┐              ┌──────────────┐
│ Sensors  │                │ /status      │              │ UI Display   │
│ Motors   │                │ /control     │              │ Commands     │
│ State    │                │              │              │ Logs         │
└──────────┘                └──────────────┘              └──────────────┘
```

## 🔄 Alur Komunikasi

### 1. ESP32 → Firebase (Data Upload)
**Interval:** Setiap 1 detik (1000ms)

**Path:** `/panel_surya_01/status`

**Data yang dikirim:**
```json
{
  "debu": 0.045,      // Float (dari sensor debu)
  "hujan": false,     // Boolean (dari sensor hujan)
  "state": "IDLE"     // String (state machine saat ini)
}
```

**Kode ESP32:**
```cpp
// Setiap 1 detik
Firebase.RTDB.setFloat(&fbdo, pathStatus + "/debu", dustValue);
Firebase.RTDB.setBool(&fbdo, pathStatus + "/hujan", isRaining);
Firebase.RTDB.setString(&fbdo, pathStatus + "/state", currentStateStr);
```

### 2. Flutter App → Firebase (Data Read)
**Interval:** 
- UI Refresh: Setiap 2 detik
- Background Monitoring: Setiap 5 detik

**Path:** `/panel_surya_01.json?auth=KEY`

**Method:** GET

**Response:**
```json
{
  "status": {
    "debu": 0.045,
    "hujan": false,
    "state": "IDLE"
  },
  "control": {
    "command": "NONE"
  }
}
```

### 3. Flutter App → Firebase (Command Send)
**Path:** `/panel_surya_01/control.json?auth=KEY`

**Method:** PATCH

**Body:**
```json
{
  "command": "START" | "STOP" | "AUTO_ON" | "AUTO_OFF"
}
```

### 4. ESP32 → Firebase (Command Read)
**Interval:** Setiap 1 detik (hanya saat STATE_IDLE)

**Path:** `/panel_surya_01/control/command`

**Kode ESP32:**
```cpp
// Hanya baca command saat IDLE
if (currentState == STATE_IDLE) {
  if (Firebase.RTDB.getString(&fbdo, pathControl + "/command")) {
    String cmd = fbdo.stringData();
    
    if (cmd == "START") {
      // Start cleaning
      currentState = STATE_PRE_WASH;
      Firebase.RTDB.setString(&fbdo, pathControl + "/command", "RUNNING");
    }
    else if (cmd == "STOP") {
      stopAllHardware();
      Firebase.RTDB.setString(&fbdo, pathControl + "/command", "NONE");
    }
  }
}
```

## 🎯 State Machine ESP32

### State Flow:
```
IDLE → PRE_WASH → MOVING_DOWN → RINSING → MOVING_UP → IDLE
  ↑                                                          ↓
  └────────────────── RAIN_STOP ───────────────────────────┘
```

### Detail State:

| State | String | Durasi | Deskripsi |
|-------|--------|--------|-----------|
| STATE_IDLE | "IDLE" | - | Mesin diam, siap menerima perintah |
| STATE_PRE_WASH | "PRE_WASH" | 2 detik | Pompa & sikat menyala |
| STATE_MOVING_DOWN | "MOVING_DOWN" | 5 detik | Mesin turun |
| STATE_PAUSE_BOTTOM | "RINSING" | 2 detik | Bilas di posisi bawah |
| STATE_MOVING_UP | "MOVING_UP" | 6 detik | Mesin naik kembali |
| STATE_RAIN_ABORT | "RAIN_STOP" | 5 detik | Stop darurat karena hujan |

### Auto Start Logic:
```cpp
// Di STATE_IDLE
if (dustValue > BATAS_DEBU_AUTO && !isRaining) {
  // Auto start cleaning
  currentState = STATE_PRE_WASH;
}
```

**Catatan:** Auto start **SELALU AKTIF** di code.ino saat ini, tidak bisa dimatikan.

## ⚠️ Masalah yang Ditemukan

### 1. AUTO_ON/AUTO_OFF Tidak Didukung
**Masalah:** 
- Flutter app mengirim command `AUTO_ON` dan `AUTO_OFF`
- ESP32 tidak membaca command ini
- Auto start selalu aktif, tidak bisa dimatikan dari app

**Solusi yang Diperlukan:**
- Tambahkan support AUTO_ON/AUTO_OFF di ESP32
- Tambahkan variabel `autoModeEnabled` di ESP32
- Modifikasi auto start logic untuk check `autoModeEnabled`

### 2. Command Hanya Dibaca Saat IDLE
**Masalah:**
- ESP32 hanya membaca command saat `STATE_IDLE`
- Jika user kirim START saat mesin sedang jalan, command diabaikan

**Solusi:**
- Command STOP bisa dibaca kapan saja (sudah ada)
- Command START hanya valid saat IDLE (sudah benar)

### 3. Command Reset Mechanism
**Status:** ✅ Sudah Benar
- ESP32 mengubah command menjadi "RUNNING" saat proses berjalan
- ESP32 reset command menjadi "NONE" setelah selesai
- Mencegah command diproses berulang kali

## 🔧 Rekomendasi Perbaikan ESP32

### 1. Tambahkan Support AUTO_ON/AUTO_OFF

**Tambahkan variabel global:**
```cpp
bool autoModeEnabled = true; // Default true
```

**Tambahkan di loop(), bagian baca command:**
```cpp
if (currentState == STATE_IDLE) {
  if (Firebase.RTDB.getString(&fbdo, pathControl + "/command")) {
    String cmd = fbdo.stringData();
    
    if (cmd == "START") {
      Serial.println("🔥 Perintah START dari Firebase!");
      currentState = STATE_PRE_WASH;
      stateStartTime = millis();
      Firebase.RTDB.setString(&fbdo, pathControl + "/command", "RUNNING");
    }
    else if (cmd == "STOP") {
      stopAllHardware();
      Firebase.RTDB.setString(&fbdo, pathControl + "/command", "NONE");
    }
    // TAMBAHKAN INI:
    else if (cmd == "AUTO_ON") {
      Serial.println("✅ Mode Otomatis AKTIF");
      autoModeEnabled = true;
      Firebase.RTDB.setBool(&fbdo, pathStatus + "/autoMode", true);
      Firebase.RTDB.setString(&fbdo, pathControl + "/command", "NONE");
    }
    else if (cmd == "AUTO_OFF") {
      Serial.println("❌ Mode Otomatis NONAKTIF");
      autoModeEnabled = false;
      Firebase.RTDB.setBool(&fbdo, pathStatus + "/autoMode", false);
      Firebase.RTDB.setString(&fbdo, pathControl + "/command", "NONE");
    }
  }
}
```

### 2. Modifikasi Auto Start Logic

**Ubah di STATE_IDLE:**
```cpp
case STATE_IDLE:
  currentStateStr = "IDLE";
  // Auto Start hanya jika autoModeEnabled = true
  if (autoModeEnabled && dustValue > BATAS_DEBU_AUTO && !isRaining) {
    Serial.println("🤖 Auto Start: Debu Tinggi");
    currentState = STATE_PRE_WASH;
    stateStartTime = millis();
  }
  break;
```

### 3. Inisialisasi autoMode di Setup

**Tambahkan di setup():**
```cpp
// Set default autoMode ke true
Firebase.RTDB.setBool(&fbdo, pathStatus + "/autoMode", true);
```

### 4. Baca autoMode dari Firebase (Optional)

**Tambahkan di loop(), bagian komunikasi Firebase:**
```cpp
// Baca autoMode dari Firebase (jika diubah manual di Firebase Console)
if (Firebase.RTDB.getBool(&fbdo, pathStatus + "/autoMode")) {
  autoModeEnabled = fbdo.boolData();
}
```

## 📱 Penyesuaian Flutter App

### Status Saat Ini: ✅ Sudah Sesuai

1. **Membaca State:** ✅ Sudah benar
   - Membaca dari `/panel_surya_01/status/state`
   - Menampilkan semua state dengan warna dan icon yang sesuai

2. **Mengirim Command:** ✅ Sudah benar
   - Mengirim ke `/panel_surya_01/control/command`
   - Command: START, STOP, AUTO_ON, AUTO_OFF

3. **Sinkronisasi autoMode:** ✅ Sudah benar
   - Membaca dari `/panel_surya_01/status/autoMode`
   - Mengupdate saat toggle diubah

4. **Kontrol Manual:** ✅ Sudah benar
   - START hanya aktif saat state = "IDLE"
   - STOP aktif saat mesin berjalan

### Yang Perlu Disesuaikan (Setelah ESP32 Diupdate):

**Tidak ada** - Flutter app sudah siap, hanya perlu ESP32 ditambahkan support AUTO_ON/AUTO_OFF.

## 🔍 Checklist Integrasi

### ESP32 (code.ino):
- [ ] Tambahkan variabel `autoModeEnabled`
- [ ] Tambahkan support command AUTO_ON
- [ ] Tambahkan support command AUTO_OFF
- [ ] Modifikasi auto start logic untuk check `autoModeEnabled`
- [ ] Set default autoMode di setup()
- [ ] (Optional) Baca autoMode dari Firebase

### Flutter App:
- [x] Membaca state dari Firebase
- [x] Mengirim command ke Firebase
- [x] Sinkronisasi autoMode dengan Firebase
- [x] Menampilkan state dengan benar
- [x] Kontrol manual berdasarkan state

## 📝 Catatan Penting

1. **Command Priority:**
   - STOP memiliki priority tertinggi (bisa dipanggil kapan saja)
   - START hanya valid saat IDLE
   - AUTO_ON/AUTO_OFF hanya valid saat IDLE

2. **State Priority:**
   - RAIN_STOP memiliki priority tertinggi
   - Jika hujan terdeteksi, semua state langsung berubah ke RAIN_STOP

3. **Timing:**
   - ESP32 update data setiap 1 detik
   - Flutter app refresh UI setiap 2 detik
   - Background monitoring setiap 5 detik

4. **Command Reset:**
   - ESP32 mengubah command menjadi "RUNNING" saat proses berjalan
   - ESP32 reset command menjadi "NONE" setelah selesai
   - Mencegah command diproses berulang kali

## 🚀 Testing

### Test State Machine:
1. Pastikan ESP32 mengirim state dengan benar
2. Test setiap state dengan manual start
3. Test auto start dengan debu tinggi
4. Test rain stop dengan simulasi hujan

### Test Command:
1. Test START saat IDLE → harus jalan
2. Test START saat berjalan → harus diabaikan
3. Test STOP kapan saja → harus stop
4. Test AUTO_ON → harus aktifkan auto mode
5. Test AUTO_OFF → harus nonaktifkan auto mode

### Test Auto Mode:
1. Toggle AUTO_ON di Flutter app
2. Pastikan ESP32 membaca autoMode = true
3. Test auto start masih bekerja
4. Toggle AUTO_OFF
5. Pastikan auto start tidak bekerja lagi

