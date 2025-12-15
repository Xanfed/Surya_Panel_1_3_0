# Arsitektur Sistem Panel Surya Cleaning IoT

## 📊 Diagram Arsitektur

```
┌─────────────┐         ┌──────────────────┐         ┌──────────────┐
│   ESP32     │────────▶│  Firebase RTDB   │◀────────│ Flutter App  │
│  (Hardware) │  POST   │  (Cloud Storage) │  GET    │  (Mobile/Web)│
└─────────────┘         └──────────────────┘         └──────────────┘
     │                                                       │
     │                                                       │
     │                                                       ▼
     │                                              ┌──────────────────┐
     │                                              │  Local Database   │
     │                                              │  (SQLite/Shared)  │
     │                                              │  - Logs           │
     │                                              │  - Schedules      │
     │                                              └──────────────────┘
     │
     └──────────────────────────────────────────────────────┘
                    PATCH (Commands)
```

## 🔄 Alur Data

### 1. ESP32 → Firebase (Data Sensor)
ESP32 mengirim data sensor ke Firebase dengan struktur:

```json
{
  "panel_surya_01": {
    "status": {
      "debu": 0.045,        // Float (0.0 - 1.0 atau nilai aktual)
      "hujan": false,       // Boolean
      "state": "IDLE"      // String: "IDLE", "MOVING", "PRE_WASH", "RAIN_STOP", dll
    }
  }
}
```

**Path Firebase:** `/panel_surya_01/status.json`

### 2. Flutter App → Firebase (Membaca Data)
- **Method:** `GET`
- **URL:** `https://surya-panel-default-rtdb.asia-southeast1.firebasedatabase.app/panel_surya_01.json?auth=KEY`
- **Interval:** Setiap 2 detik (UI refresh) dan 5 detik (background monitoring)

### 3. Flutter App → Firebase (Mengirim Perintah)
- **Method:** `PATCH`
- **URL:** `https://surya-panel-default-rtdb.asia-southeast1.firebasedatabase.app/panel_surya_01/control.json?auth=KEY`
- **Body:**
```json
{
  "command": "START" | "STOP" | "AUTO_ON" | "AUTO_OFF"
}
```

**Path Firebase:** `/panel_surya_01/control/command`

### 4. ESP32 → Firebase (Membaca Perintah)
ESP32 harus membaca dari path `/panel_surya_01/control/command` dan merespons perintah.

## 💾 Struktur Database Lokal

### Mobile (SQLite)
**File:** `solar_logs.db`

**Table: `logs`**
```sql
CREATE TABLE logs(
  id INTEGER PRIMARY KEY,
  title TEXT,      -- Contoh: "⚠️ Debu Terdeteksi!"
  body TEXT,        -- Contoh: "Kadar debu: 0.25..."
  time TEXT         -- ISO8601 format
);
```

**Table: `schedules`**
```sql
CREATE TABLE schedules(
  id INTEGER PRIMARY KEY,
  time TEXT,        -- Format: "HH:mm" (contoh: "12:00")
  duration INTEGER, -- Durasi dalam menit
  isActive INTEGER  -- 0 = false, 1 = true
);
```

### Web (SharedPreferences)
- **Key:** `solar_logs` (List<String> JSON)
- **Key:** `solar_schedules` (List<String> JSON)

## 🔧 Integrasi yang Perlu Disesuaikan di ESP32

### 1. Struktur Data Firebase
ESP32 harus mengirim data dengan struktur yang sesuai:

```cpp
// Contoh struktur JSON yang dikirim ESP32
{
  "status": {
    "debu": 0.045,      // Float
    "hujan": false,      // Boolean
    "state": "IDLE"     // String
  }
}
```

### 2. Path Firebase yang Harus Dibaca ESP32
ESP32 harus memantau path berikut untuk menerima perintah:

**Path:** `/panel_surya_01/control/command`

**Nilai yang mungkin:**
- `"START"` - Mulai pembersihan manual
- `"STOP"` - Stop pembersihan
- `"AUTO_ON"` - Aktifkan mode otomatis
- `"AUTO_OFF"` - Nonaktifkan mode otomatis

**Contoh implementasi ESP32:**
```cpp
// ESP32 harus melakukan Firebase.get() atau stream listener
Firebase.get(firebaseData, "/panel_surya_01/control/command");
String command = firebaseData.stringData();

if (command == "START") {
  // Logika start cleaning
} else if (command == "STOP") {
  // Logika stop cleaning
} else if (command == "AUTO_ON") {
  autoMode = true;
} else if (command == "AUTO_OFF") {
  autoMode = false;
}

// Setelah membaca, reset command ke "" atau null
Firebase.setString(firebaseData, "/panel_surya_01/control/command", "");
```

### 3. State Machine yang Didukung
Aplikasi Flutter mengharapkan state berikut:
- `"IDLE"` - Mesin dalam keadaan idle
- `"MOVING"` - Mesin sedang bergerak
- `"PRE_WASH"` - Persiapan cuci
- `"RAIN_STOP"` - Stop karena hujan
- `"CLEANING"` - Sedang membersihkan
- `"CONNECTING..."` - Status default saat belum terhubung

### 4. Format Data Debu
- Aplikasi mengkonversi nilai debu ke µg/m³ dengan formula: `debu * 1000`
- Jika ESP32 mengirim dalam µg/m³ langsung, sesuaikan di aplikasi
- Threshold warning: `debu > 0.20` (atau 200 µg/m³)

## 📱 Fitur Aplikasi Flutter

### 1. Monitoring Real-time
- Refresh UI setiap 2 detik
- Background monitoring setiap 5 detik
- Auto-notifikasi untuk alert

### 2. Kontrol Manual
- Toggle pembersihan otomatis (AUTO_ON/AUTO_OFF)
- Perintah START/STOP (jika diperlukan)

### 3. Jadwal Pembersihan
- **Lokal:** Disimpan di database lokal (tidak tersinkron dengan Firebase)
- **Catatan:** Untuk sinkronisasi dengan ESP32, perlu implementasi tambahan

### 4. Logging & History
- Warning otomatis tersimpan di database lokal
- Maksimal 20 log terbaru
- Format waktu: "HH.mm"

## ⚠️ Hal yang Perlu Disesuaikan

### 1. Sinkronisasi Status Pembersihan Otomatis
**Masalah:** Status toggle `pembersihanOtomatis` hanya tersimpan di state aplikasi, tidak tersinkron dengan Firebase.

**Solusi yang Disarankan:**
- Tambahkan field di Firebase: `/panel_surya_01/status/autoMode` (boolean)
- ESP32 membaca field ini untuk mengetahui status mode otomatis
- Aplikasi membaca field ini saat startup untuk sinkronisasi

### 2. Integrasi Jadwal dengan ESP32
**Masalah:** Jadwal pembersihan hanya tersimpan lokal, ESP32 tidak tahu jadwalnya.

**Solusi yang Disarankan:**
- Tambahkan path di Firebase: `/panel_surya_01/schedules/`
- Aplikasi mengirim jadwal ke Firebase saat dibuat/diubah
- ESP32 membaca jadwal dari Firebase dan mengeksekusi sesuai waktu

**Struktur Firebase untuk Schedules:**
```json
{
  "panel_surya_01": {
    "schedules": {
      "schedule_1": {
        "time": "12:00",
        "duration": 10,
        "isActive": true
      },
      "schedule_2": {
        "time": "18:00",
        "duration": 15,
        "isActive": false
      }
    }
  }
}
```

### 3. Reset Command setelah Dibaca
**Masalah:** Command di Firebase tidak di-reset setelah dibaca ESP32.

**Solusi:** ESP32 harus mengosongkan command setelah membaca:
```cpp
Firebase.setString(firebaseData, "/panel_surya_01/control/command", "");
```

### 4. Format Waktu Jadwal
**Format yang digunakan:** "HH:mm" (contoh: "12:00")
**ESP32 harus:** Parse format ini dan bandingkan dengan waktu real-time

## 🔐 Konfigurasi Firebase

**Database URL:** `https://surya-panel-default-rtdb.asia-southeast1.firebasedatabase.app`

**Auth Key:** `O7dnWOEJbhOxCgaecBgsTeF05iAXU13HeNaDFNIC`

**Rules Firebase (Disarankan):**
```json
{
  "rules": {
    "panel_surya_01": {
      ".read": "auth != null || query.orderByKey().limitToFirst(1).exists()",
      ".write": "auth != null",
      "status": {
        ".read": true,
        ".write": "auth != null"
      },
      "control": {
        ".read": true,
        ".write": true
      }
    }
  }
}
```

## 📝 Checklist Integrasi

### ESP32 Side:
- [ ] Mengirim data ke `/panel_surya_01/status` dengan struktur yang benar
- [ ] Membaca perintah dari `/panel_surya_01/control/command`
- [ ] Reset command setelah dibaca
- [ ] Mengirim state yang valid ("IDLE", "MOVING", dll)
- [ ] Format debu sesuai (float 0.0-1.0 atau µg/m³)
- [ ] Format hujan sebagai boolean

### Flutter App Side:
- [x] Membaca data dari Firebase
- [x] Mengirim perintah ke Firebase
- [x] Menyimpan logs lokal
- [x] Menyimpan schedules lokal
- [ ] Sinkronisasi status autoMode dengan Firebase (OPTIONAL)
- [ ] Sinkronisasi schedules dengan Firebase (OPTIONAL)

## 🚀 Rekomendasi Peningkatan

1. **Real-time Sync:** Gunakan Firebase Stream untuk update real-time tanpa polling
2. **Cloud Schedules:** Simpan jadwal di Firebase untuk akses multi-device
3. **Status Sync:** Sinkronkan status pembersihan otomatis dengan Firebase
4. **Error Handling:** Tambahkan retry mechanism untuk koneksi yang gagal
5. **Offline Mode:** Cache data terakhir untuk mode offline

