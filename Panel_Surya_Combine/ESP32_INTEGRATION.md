# Panduan Integrasi ESP32 dengan Flutter App

## 📋 Checklist yang Perlu Disesuaikan di ESP32

### 1. ✅ Struktur Data yang Dikirim ke Firebase

ESP32 harus mengirim data dengan struktur berikut:

**Path:** `/panel_surya_01/status.json`

**Format JSON:**
```json
{
  "debu": 0.045,        // Float (0.0 - 1.0) atau nilai aktual dalam mg/m³
  "hujan": false,       // Boolean (true/false)
  "state": "IDLE",      // String
  "autoMode": false     // Boolean (opsional, untuk sinkronisasi)
}
```

**Contoh Kode ESP32 (Firebase ESP32 Client):**
```cpp
FirebaseJson json;
json.set("debu", 0.045);
json.set("hujan", false);
json.set("state", "IDLE");
json.set("autoMode", false);

Firebase.setJSON(firebaseData, "/panel_surya_01/status", json);
```

### 2. ✅ Membaca Perintah dari Firebase

ESP32 harus membaca perintah dari path berikut:

**Path:** `/panel_surya_01/control/command`

**Nilai yang mungkin:**
- `"START"` - Mulai pembersihan manual
- `"STOP"` - Stop pembersihan
- `"AUTO_ON"` - Aktifkan mode otomatis
- `"AUTO_OFF"` - Nonaktifkan mode otomatis

**Contoh Kode ESP32:**
```cpp
void checkFirebaseCommand() {
  if (Firebase.getString(firebaseData, "/panel_surya_01/control/command")) {
    String command = firebaseData.stringData();
    
    if (command == "START") {
      // Logika start cleaning
      startCleaning();
      // Reset command setelah diproses
      Firebase.setString(firebaseData, "/panel_surya_01/control/command", "");
      
    } else if (command == "STOP") {
      // Logika stop cleaning
      stopCleaning();
      Firebase.setString(firebaseData, "/panel_surya_01/control/command", "");
      
    } else if (command == "AUTO_ON") {
      // Aktifkan mode otomatis
      autoMode = true;
      updateAutoModeStatus(true);
      Firebase.setString(firebaseData, "/panel_surya_01/control/command", "");
      
    } else if (command == "AUTO_OFF") {
      // Nonaktifkan mode otomatis
      autoMode = false;
      updateAutoModeStatus(false);
      Firebase.setString(firebaseData, "/panel_surya_01/control/command", "");
    }
  }
}

void updateAutoModeStatus(bool status) {
  Firebase.setBool(firebaseData, "/panel_surya_01/status/autoMode", status);
}
```

**PENTING:** Setelah membaca command, **WAJIB** reset command ke string kosong `""` agar tidak diproses berulang kali.

### 3. ✅ State Machine yang Didukung

Aplikasi Flutter mengharapkan state berikut:

| State | Deskripsi |
|-------|-----------|
| `"IDLE"` | Mesin dalam keadaan idle/siap |
| `"MOVING"` | Mesin sedang bergerak |
| `"PRE_WASH"` | Persiapan cuci |
| `"CLEANING"` | Sedang membersihkan |
| `"RAIN_STOP"` | Stop karena hujan terdeteksi |
| `"ERROR"` | Terjadi error |

**Contoh Update State:**
```cpp
void updateState(String newState) {
  Firebase.setString(firebaseData, "/panel_surya_01/status/state", newState);
}
```

### 4. ✅ Format Data Sensor

#### Debu (Dust Sensor)
- **Format:** Float (0.0 - 1.0) atau nilai aktual
- **Aplikasi mengkonversi:** `debu * 1000` untuk menampilkan dalam µg/m³
- **Threshold Warning:** `debu > 0.20` (atau 200 µg/m³)

**Contoh:**
```cpp
float dustValue = readDustSensor(); // Baca dari sensor
// Jika sensor mengembalikan nilai dalam mg/m³, kirim langsung
// Jika dalam format lain, konversi terlebih dahulu
Firebase.setFloat(firebaseData, "/panel_surya_01/status/debu", dustValue);
```

#### Hujan (Rain Sensor)
- **Format:** Boolean (`true` atau `false`)
- **true** = Hujan terdeteksi
- **false** = Tidak ada hujan

**Contoh:**
```cpp
bool rainDetected = digitalRead(RAIN_SENSOR_PIN) == LOW; // Sesuaikan dengan sensor Anda
Firebase.setBool(firebaseData, "/panel_surya_01/status/hujan", rainDetected);
```

### 5. ✅ Sinkronisasi Status AutoMode

ESP32 harus membaca dan mengupdate status `autoMode` di Firebase:

**Path:** `/panel_surya_01/status/autoMode`

**Contoh:**
```cpp
void syncAutoMode() {
  if (Firebase.getBool(firebaseData, "/panel_surya_01/status/autoMode")) {
    autoMode = firebaseData.boolData();
  }
}

void updateAutoModeStatus(bool status) {
  Firebase.setBool(firebaseData, "/panel_surya_01/status/autoMode", status);
  autoMode = status;
}
```

### 6. ✅ Interval Update Data

**Rekomendasi:**
- Update data sensor ke Firebase: **Setiap 2-5 detik**
- Check command dari Firebase: **Setiap 1-2 detik**

**Contoh:**
```cpp
unsigned long lastSensorUpdate = 0;
unsigned long lastCommandCheck = 0;

void loop() {
  unsigned long currentMillis = millis();
  
  // Update sensor setiap 3 detik
  if (currentMillis - lastSensorUpdate >= 3000) {
    updateSensorData();
    lastSensorUpdate = currentMillis;
  }
  
  // Check command setiap 1 detik
  if (currentMillis - lastCommandCheck >= 1000) {
    checkFirebaseCommand();
    lastCommandCheck = currentMillis;
  }
}
```

## 🔧 Konfigurasi Firebase di ESP32

### Firebase Database URL
```
https://surya-panel-default-rtdb.asia-southeast1.firebasedatabase.app
```

### Database Secret (Auth Key)
```
O7dnWOEJbhOxCgaecBgsTeF05iAXU13HeNaDFNIC
```

**Contoh Setup:**
```cpp
#define FIREBASE_HOST "surya-panel-default-rtdb.asia-southeast1.firebasedatabase.app"
#define FIREBASE_AUTH "O7dnWOEJbhOxCgaecBgsTeF05iAXU13HeNaDFNIC"

Firebase.begin(FIREBASE_HOST, FIREBASE_AUTH);
```

## 📝 Template Kode ESP32 Lengkap

```cpp
#include <FirebaseESP32.h>

#define FIREBASE_HOST "surya-panel-default-rtdb.asia-southeast1.firebasedatabase.app"
#define FIREBASE_AUTH "O7dnWOEJbhOxCgaecBgsTeF05iAXU13HeNaDFNIC"

FirebaseData firebaseData;
bool autoMode = false;

void setup() {
  Serial.begin(115200);
  
  // Setup WiFi
  WiFi.begin("SSID", "PASSWORD");
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  
  // Setup Firebase
  Firebase.begin(FIREBASE_HOST, FIREBASE_AUTH);
  Firebase.reconnectWiFi(true);
  
  // Inisialisasi status
  updateState("IDLE");
  updateAutoModeStatus(false);
}

void loop() {
  static unsigned long lastSensorUpdate = 0;
  static unsigned long lastCommandCheck = 0;
  unsigned long currentMillis = millis();
  
  // Update sensor setiap 3 detik
  if (currentMillis - lastSensorUpdate >= 3000) {
    updateSensorData();
    lastSensorUpdate = currentMillis;
  }
  
  // Check command setiap 1 detik
  if (currentMillis - lastCommandCheck >= 1000) {
    checkFirebaseCommand();
    lastCommandCheck = currentMillis;
  }
  
  // Logika pembersihan otomatis (jika autoMode aktif)
  if (autoMode) {
    // Implementasi logika pembersihan otomatis
    handleAutoCleaning();
  }
}

void updateSensorData() {
  float dust = readDustSensor();
  bool rain = readRainSensor();
  String state = getCurrentState();
  
  FirebaseJson json;
  json.set("debu", dust);
  json.set("hujan", rain);
  json.set("state", state);
  json.set("autoMode", autoMode);
  
  Firebase.setJSON(firebaseData, "/panel_surya_01/status", json);
}

void checkFirebaseCommand() {
  if (Firebase.getString(firebaseData, "/panel_surya_01/control/command")) {
    String command = firebaseData.stringData();
    
    if (command.length() > 0) {
      Serial.println("Command received: " + command);
      
      if (command == "START") {
        startCleaning();
        resetCommand();
      } else if (command == "STOP") {
        stopCleaning();
        resetCommand();
      } else if (command == "AUTO_ON") {
        autoMode = true;
        updateAutoModeStatus(true);
        resetCommand();
      } else if (command == "AUTO_OFF") {
        autoMode = false;
        updateAutoModeStatus(false);
        resetCommand();
      }
    }
  }
}

void resetCommand() {
  Firebase.setString(firebaseData, "/panel_surya_01/control/command", "");
}

void updateState(String state) {
  Firebase.setString(firebaseData, "/panel_surya_01/status/state", state);
}

void updateAutoModeStatus(bool status) {
  Firebase.setBool(firebaseData, "/panel_surya_01/status/autoMode", status);
}

// Implementasi fungsi-fungsi berikut sesuai hardware Anda
float readDustSensor() {
  // Baca dari sensor debu
  return 0.045; // Contoh nilai
}

bool readRainSensor() {
  // Baca dari sensor hujan
  return false; // Contoh nilai
}

String getCurrentState() {
  // Return state saat ini
  return "IDLE"; // Contoh
}

void startCleaning() {
  updateState("CLEANING");
  // Logika start cleaning
}

void stopCleaning() {
  updateState("IDLE");
  // Logika stop cleaning
}

void handleAutoCleaning() {
  // Logika pembersihan otomatis
  // Contoh: jika debu > threshold, mulai cleaning
}
```

## ⚠️ Troubleshooting

### 1. Command tidak terbaca
- Pastikan ESP32 membaca path yang benar: `/panel_surya_01/control/command`
- Pastikan command di-reset setelah dibaca
- Check koneksi WiFi dan Firebase

### 2. Data tidak terkirim
- Pastikan struktur JSON sesuai
- Check Firebase rules (harus allow write)
- Pastikan auth key benar

### 3. State tidak update
- Pastikan ESP32 mengupdate state secara berkala
- Check format string state (harus sesuai dengan yang didukung)

### 4. AutoMode tidak sinkron
- Pastikan ESP32 membaca dan mengupdate `/panel_surya_01/status/autoMode`
- Check apakah status di-reset saat startup

## 📞 Testing

### Test Manual:
1. Buka aplikasi Flutter
2. Toggle "Pembersihan" switch
3. Check di Firebase Console apakah `autoMode` berubah
4. Check di Serial Monitor ESP32 apakah command diterima

### Test Command:
1. Di Firebase Console, set `/panel_surya_01/control/command` = `"START"`
2. Check apakah ESP32 merespons
3. Check apakah command di-reset ke `""`

