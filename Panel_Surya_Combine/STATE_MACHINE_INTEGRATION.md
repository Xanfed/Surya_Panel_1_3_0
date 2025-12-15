# Integrasi State Machine ESP32 dengan Flutter App

## 📊 State Machine di ESP32 (code.ino)

### State yang Digunakan:
1. **STATE_IDLE** → `"IDLE"`
   - Mesin dalam keadaan diam/siap
   - Menunggu perintah atau auto-start jika debu tinggi

2. **STATE_PRE_WASH** → `"PRE_WASH"`
   - Persiapan cuci (pompa dan sikat menyala)
   - Durasi: 2 detik

3. **STATE_MOVING_DOWN** → `"MOVING_DOWN"`
   - Mesin turun ke bawah
   - Durasi: 5 detik (WAKTU_TURUN)

4. **STATE_PAUSE_BOTTOM** → `"RINSING"`
   - Bilas di posisi bawah
   - Durasi: 2 detik (WAKTU_BILAS)

5. **STATE_MOVING_UP** → `"MOVING_UP"`
   - Mesin naik kembali
   - Durasi: 6 detik (WAKTU_NAIK)

6. **STATE_RAIN_ABORT** → `"RAIN_STOP"`
   - Stop darurat karena hujan
   - Diam 5 detik sebelum bisa jalan lagi

## 🔄 Alur State Machine

```
IDLE → PRE_WASH → MOVING_DOWN → RINSING → MOVING_UP → IDLE
  ↑                                                          ↓
  └────────────────── RAIN_STOP ───────────────────────────┘
```

## 📱 Penyesuaian di Flutter App

### 1. ✅ Kartu Status Mesin
- Menampilkan state saat ini dengan warna dan icon yang sesuai
- Warna:
  - IDLE: Biru
  - PRE_WASH: Orange
  - MOVING_DOWN: Hijau
  - RINSING: Cyan
  - MOVING_UP: Hijau
  - RAIN_STOP: Merah

### 2. ✅ Kontrol Manual
- Tombol START: Hanya aktif saat state = "IDLE"
- Tombol STOP: Aktif saat state berjalan atau IDLE
- Menampilkan status state saat ini

### 3. ✅ Display State
- Nama state ditampilkan dalam bahasa Indonesia:
  - "IDLE" → "Siap"
  - "PRE_WASH" → "Persiapan Cuci"
  - "MOVING_DOWN" → "Turun"
  - "RINSING" → "Bilas"
  - "MOVING_UP" → "Naik"
  - "RAIN_STOP" → "Stop Hujan"

## ⚠️ Yang Perlu Ditambahkan di ESP32 (code.ino)

### 1. Support AUTO_ON/AUTO_OFF Command

**Tambahkan di bagian loop(), setelah membaca command START/STOP:**

```cpp
// Di bagian loop(), setelah membaca command START/STOP
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
      // Set flag auto mode (jika diperlukan)
      Firebase.RTDB.setBool(&fbdo, pathStatus + "/autoMode", true);
      Firebase.RTDB.setString(&fbdo, pathControl + "/command", "NONE");
    }
    else if (cmd == "AUTO_OFF") {
      Serial.println("❌ Mode Otomatis NONAKTIF");
      Firebase.RTDB.setBool(&fbdo, pathStatus + "/autoMode", false);
      Firebase.RTDB.setString(&fbdo, pathControl + "/command", "NONE");
    }
  }
}
```

### 2. Baca Status autoMode dari Firebase

**Tambahkan variabel global:**
```cpp
bool autoModeEnabled = true; // Default true (sesuai behavior saat ini)
```

**Baca autoMode di loop():**
```cpp
// Di bagian komunikasi Firebase, tambahkan:
if (Firebase.RTDB.getBool(&fbdo, pathStatus + "/autoMode")) {
  autoModeEnabled = fbdo.boolData();
}
```

### 3. Modifikasi Auto Start Logic

**Ubah bagian STATE_IDLE:**
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

### 4. Inisialisasi autoMode di Setup

**Tambahkan di setup():**
```cpp
// Set default autoMode ke true
Firebase.RTDB.setBool(&fbdo, pathStatus + "/autoMode", true);
```

## 📋 Checklist Integrasi

### ESP32 (code.ino):
- [ ] Tambahkan support command AUTO_ON
- [ ] Tambahkan support command AUTO_OFF
- [ ] Baca status autoMode dari Firebase
- [ ] Modifikasi auto start logic untuk check autoMode
- [ ] Set default autoMode di setup()

### Flutter App:
- [x] Menampilkan semua state dengan benar
- [x] Kartu status mesin dengan warna dan icon
- [x] Kontrol manual berdasarkan state
- [x] Display state dalam bahasa Indonesia
- [x] Toggle mode otomatis/manual
- [x] Sinkronisasi autoMode dengan Firebase

## 🔍 Catatan Penting

1. **Command Reset:**
   - ESP32 mengubah command menjadi "RUNNING" saat proses berjalan
   - Setelah selesai, reset menjadi "NONE"
   - Flutter app tidak perlu membaca "RUNNING", hanya state yang penting

2. **Auto Mode:**
   - Saat ini ESP32 selalu auto-start jika debu tinggi
   - Setelah ditambahkan autoMode, ESP32 hanya auto-start jika autoMode = true

3. **State Priority:**
   - RAIN_STOP memiliki priority tertinggi
   - Jika hujan terdeteksi, semua state langsung berubah ke RAIN_STOP

4. **Command Handling:**
   - Command hanya dibaca saat STATE_IDLE
   - Command STOP bisa dipanggil kapan saja untuk force stop

## 🚀 Testing

### Test State Machine:
1. Pastikan ESP32 mengirim state dengan benar
2. Test setiap state dengan manual start
3. Test auto start dengan debu tinggi
4. Test rain stop dengan simulasi hujan

### Test Auto Mode:
1. Toggle AUTO_ON di Flutter app
2. Pastikan ESP32 membaca autoMode = true
3. Test auto start masih bekerja
4. Toggle AUTO_OFF
5. Pastikan auto start tidak bekerja lagi

