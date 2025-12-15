#include <Arduino.h>
#include <WiFi.h>
#include <Firebase_ESP_Client.h>

// Helper wajib untuk library ini
#include <addons/TokenHelper.h>
#include <addons/RTDBHelper.h>

/*
  PROJECT: SOLAR PANEL CLEANER (FINAL VERSION)
  AUTH METHOD: Database Secret (Legacy) -> Paling Stabil
*/

// ================= 1. KREDENSIAL (JANGAN SALAH KETIK) =================
// WiFi (Pastikan iPhone Hotspot "Maximize Compatibility" ON)
#define WIFI_SSID "Rpl1"
#define WIFI_PASSWORD ""

// Firebase Database Secret (Kunci Master)
#define DATABASE_SECRET "O7dnWOEJbhOxCgaecBgsTeF05iAXU13HeNaDFNIC"
#define DATABASE_URL "https://surya-panel-default-rtdb.asia-southeast1.firebasedatabase.app/"

// Object Firebase
FirebaseData fbdo;
FirebaseAuth auth;
FirebaseConfig config;
bool signupOK = false;

// ================= 2. DEFINISI PIN HARDWARE =================
// Motor Gerak (Naik/Turun)
#define PIN_M_GERAK_IN1  26
#define PIN_M_GERAK_IN2  27
#define PIN_M_GERAK_ENA  14

// Motor Sikat (Putar)
#define PIN_M_SIKAT_IN3  33
#define PIN_M_SIKAT_IN4  32
#define PIN_M_SIKAT_ENB  12

// Lainnya
#define PIN_POMPA        23
#define PIN_SENSOR_DEBU  34
#define PIN_LED_DEBU     25
#define PIN_SENSOR_HUJAN 4

// ================= 3. SETTING WAKTU & SENSOR =================
const unsigned long WAKTU_TURUN = 5000; // 5 Detik
const unsigned long WAKTU_NAIK  = 6000; // 6 Detik (Dilebihkan biar aman)
const unsigned long WAKTU_BILAS = 2000; // 2 Detik diam di bawah

const float BATAS_DEBU_AUTO = 0.20; // Ambang batas debu
const int SPEED_GERAK = 255;        // Kecepatan Max
const int SPEED_SIKAT = 200;

// Path di Database
String pathStatus = "/panel_surya_01/status";
String pathControl = "/panel_surya_01/control";

// ================= 4. STATUS MESIN (STATE MACHINE) =================
enum SystemState {
  STATE_IDLE,         // Diam
  STATE_PRE_WASH,     // Persiapan (Air Nyala)
  STATE_MOVING_DOWN,  // Turun
  STATE_PAUSE_BOTTOM, // Bilas Bawah
  STATE_MOVING_UP,    // Naik (Pulang)
  STATE_RAIN_ABORT    // Stop Darurat Hujan
};

SystemState currentState = STATE_IDLE;
String currentStateStr = "IDLE";

unsigned long stateStartTime = 0;
unsigned long lastCloudUpdate = 0;
float dustValue = 0.0;
bool isRaining = false;

// ================= 5. MODE OTOMATIS & TIMER =================
bool autoModeEnabled = true; // Default true (sesuai behavior lama)
bool timerModeEnabled = false; // Mode timer (bersih berkala)
unsigned long timerInterval = 15; // Interval dalam menit (default 15 menit)
unsigned long lastTimerClean = 0; // Waktu terakhir cleaning dari timer

// ================= 5. FUNGSI KONTROL HARDWARE =================

void stopAllHardware() {
  digitalWrite(PIN_M_GERAK_IN1, LOW);
  digitalWrite(PIN_M_GERAK_IN2, LOW);
  analogWrite(PIN_M_GERAK_ENA, 0);

  digitalWrite(PIN_M_SIKAT_IN3, LOW);
  digitalWrite(PIN_M_SIKAT_IN4, LOW);
  analogWrite(PIN_M_SIKAT_ENB, 0);

  digitalWrite(PIN_POMPA, LOW);
  currentStateStr = "IDLE";
}

void setPumpAndBrush(bool on) {
  if (on) {
    digitalWrite(PIN_POMPA, HIGH);
    digitalWrite(PIN_M_SIKAT_IN3, HIGH);
    digitalWrite(PIN_M_SIKAT_IN4, LOW);
    analogWrite(PIN_M_SIKAT_ENB, SPEED_SIKAT);
  } else {
    digitalWrite(PIN_POMPA, LOW);
    digitalWrite(PIN_M_SIKAT_IN3, LOW);
    digitalWrite(PIN_M_SIKAT_IN4, LOW);
    analogWrite(PIN_M_SIKAT_ENB, 0);
  }
}

void moveDown() {
  digitalWrite(PIN_M_GERAK_IN1, HIGH);
  digitalWrite(PIN_M_GERAK_IN2, LOW);
  analogWrite(PIN_M_GERAK_ENA, SPEED_GERAK);
}

void moveUp() {
  digitalWrite(PIN_M_GERAK_IN1, LOW);
  digitalWrite(PIN_M_GERAK_IN2, HIGH);
  analogWrite(PIN_M_GERAK_ENA, SPEED_GERAK);
}

void stopMovement() {
  digitalWrite(PIN_M_GERAK_IN1, LOW);
  digitalWrite(PIN_M_GERAK_IN2, LOW);
  analogWrite(PIN_M_GERAK_ENA, 0);
}

void readSensors() {
  // 1. Cek Hujan (0 = Basah, 1 = Kering)
  isRaining = (digitalRead(PIN_SENSOR_HUJAN) == 0);

  // 2. Cek Debu
  digitalWrite(PIN_LED_DEBU, LOW);
  delayMicroseconds(280);
  int adc = analogRead(PIN_SENSOR_DEBU);
  delayMicroseconds(40);
  digitalWrite(PIN_LED_DEBU, HIGH);
  delayMicroseconds(9680);

  float voltage = adc * (3.3 / 4095.0);
  dustValue = 0.17 * voltage - 0.1;
  if (dustValue < 0) dustValue = 0;
}

// ================= 6. SETUP UTAMA =================

void setup() {
  Serial.begin(115200);
  
  // Setup Pin
  pinMode(PIN_M_GERAK_IN1, OUTPUT); pinMode(PIN_M_GERAK_IN2, OUTPUT); pinMode(PIN_M_GERAK_ENA, OUTPUT);
  pinMode(PIN_M_SIKAT_IN3, OUTPUT); pinMode(PIN_M_SIKAT_IN4, OUTPUT); pinMode(PIN_M_SIKAT_ENB, OUTPUT);
  pinMode(PIN_POMPA, OUTPUT);
  pinMode(PIN_SENSOR_DEBU, INPUT); pinMode(PIN_LED_DEBU, OUTPUT);
  pinMode(PIN_SENSOR_HUJAN, INPUT);

  stopAllHardware(); // Pastikan mati semua dulu

  // KONEKSI WIFI
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  Serial.print("Menghubungkan ke Wi-Fi");
  while (WiFi.status() != WL_CONNECTED) {
    Serial.print(".");
    delay(300);
  }
  Serial.println("\nTerhubung WiFi!");
  Serial.print("IP Address: ");
  Serial.println(WiFi.localIP());

  // KONEKSI FIREBASE (METODE LEGACY TOKEN)
  config.database_url = DATABASE_URL;
  config.signer.tokens.legacy_token = DATABASE_SECRET; // Kunci Master dipakai disini

  // Inisialisasi Firebase
  Firebase.begin(&config, &auth);
  Firebase.reconnectWiFi(true);

  // Tunggu sebentar untuk memastikan koneksi stabil
  delay(1000);
  
  if (Firebase.ready()) {
    signupOK = true;
    Serial.println("=== SISTEM SIAP & TERHUBUNG FIREBASE (Mode Admin) ===");
    
    // Set default autoMode dan timerMode ke Firebase
    Firebase.RTDB.setBool(&fbdo, pathStatus + "/autoMode", true);
    Firebase.RTDB.setBool(&fbdo, pathStatus + "/timerMode", false);
    Firebase.RTDB.setInt(&fbdo, pathStatus + "/timerInterval", 15);
  } else {
    Serial.println("Gagal konek ke Firebase (Cek URL/Secret)");
  }
}

// ================= 7. LOOPING PROGRAM =================

void loop() {
  // A. BACA SENSOR
  readSensors();

  // B. SAFETY CHECK (Prioritas Tertinggi)
  // Jika hujan turun saat mesin jalan -> MATIKAN SEMUA
  if (isRaining && currentState != STATE_IDLE && currentState != STATE_RAIN_ABORT) {
    Serial.println("⛔ HUJAN! Stop Darurat.");
    currentState = STATE_RAIN_ABORT;
    stateStartTime = millis();
    stopAllHardware();
  }

  // C. STATE MACHINE (Logika Kerja)
  switch (currentState) {
    case STATE_IDLE:
      currentStateStr = "IDLE";
      
      // 1. Auto Start jika debu tebal & tidak hujan & autoMode aktif
      if (autoModeEnabled && dustValue > BATAS_DEBU_AUTO && !isRaining) {
         Serial.println("🤖 Auto Start: Debu Tinggi");
         currentState = STATE_PRE_WASH;
         stateStartTime = millis();
      }
      // 2. Timer Mode: Bersih berkala berdasarkan interval
      else if (timerModeEnabled && !isRaining) {
        unsigned long currentTime = millis();
        unsigned long intervalMs = timerInterval * 60 * 1000; // Convert menit ke millis
        
        // Cek apakah sudah waktunya cleaning (dan belum pernah cleaning atau sudah lewat interval)
        if (lastTimerClean == 0 || (currentTime - lastTimerClean >= intervalMs)) {
          Serial.print("⏰ Timer Start: Interval ");
          Serial.print(timerInterval);
          Serial.println(" menit");
          currentState = STATE_PRE_WASH;
          stateStartTime = millis();
          lastTimerClean = currentTime;
        }
      }
      break;

    case STATE_PRE_WASH:
      currentStateStr = "PRE_WASH";
      setPumpAndBrush(true);
      if (millis() - stateStartTime > 2000) {
        currentState = STATE_MOVING_DOWN;
        stateStartTime = millis();
        moveDown();
      }
      break;

    case STATE_MOVING_DOWN:
      currentStateStr = "MOVING_DOWN";
      if (millis() - stateStartTime > WAKTU_TURUN) {
        stopMovement();
        currentState = STATE_PAUSE_BOTTOM;
        stateStartTime = millis();
      }
      break;

    case STATE_PAUSE_BOTTOM:
      currentStateStr = "RINSING";
      if (millis() - stateStartTime > WAKTU_BILAS) {
        currentState = STATE_MOVING_UP;
        stateStartTime = millis();
        moveUp();
      }
      break;

    case STATE_MOVING_UP:
      currentStateStr = "MOVING_UP";
      if (millis() - stateStartTime > WAKTU_NAIK) {
        stopAllHardware();
        currentState = STATE_IDLE;
        
        // Reset tombol di Firebase
        if (signupOK) {
           Firebase.RTDB.setString(&fbdo, pathControl + "/command", "NONE");
        }
        
        // Reset timer jika cleaning selesai (untuk timer mode)
        // lastTimerClean sudah di-set saat cleaning dimulai, jadi tidak perlu reset di sini
      }
      break;

    case STATE_RAIN_ABORT:
      currentStateStr = "RAIN_STOP";
      // Diam 5 detik sebelum boleh jalan lagi
      if (millis() - stateStartTime > 5000) {
        currentState = STATE_IDLE;
      }
      break;
  }

  // D. KOMUNIKASI FIREBASE (Setiap 1 Detik)
  if (Firebase.ready() && signupOK && (millis() - lastCloudUpdate > 1000)) {
    lastCloudUpdate = millis();

    // 1. UPLOAD DATA STATUS
    Firebase.RTDB.setFloat(&fbdo, pathStatus + "/debu", dustValue);
    Firebase.RTDB.setBool(&fbdo, pathStatus + "/hujan", isRaining);
    Firebase.RTDB.setString(&fbdo, pathStatus + "/state", currentStateStr);
    Firebase.RTDB.setBool(&fbdo, pathStatus + "/autoMode", autoModeEnabled);
    Firebase.RTDB.setBool(&fbdo, pathStatus + "/timerMode", timerModeEnabled);
    Firebase.RTDB.setInt(&fbdo, pathStatus + "/timerInterval", timerInterval);
    
    // 2. BACA PERINTAH (Hanya jika IDLE)
    if (currentState == STATE_IDLE) {
      if (Firebase.RTDB.getString(&fbdo, pathControl + "/command")) {
        String cmd = fbdo.stringData();
        
        if (cmd == "START") {
          Serial.println("🔥 Perintah START dari Firebase!");
          currentState = STATE_PRE_WASH;
          stateStartTime = millis();
          // Ubah status biar tidak dibaca ulang
          Firebase.RTDB.setString(&fbdo, pathControl + "/command", "RUNNING");
        }
        else if (cmd == "STOP") {
          Serial.println("🛑 Perintah STOP dari Firebase!");
          stopAllHardware();
          Firebase.RTDB.setString(&fbdo, pathControl + "/command", "NONE");
        }
        // TAMBAHAN: Support AUTO_ON/AUTO_OFF
        else if (cmd == "AUTO_ON") {
          Serial.println("✅ Mode Otomatis AKTIF");
          autoModeEnabled = true;
          timerModeEnabled = false; // Pastikan timer mode nonaktif
          Firebase.RTDB.setBool(&fbdo, pathStatus + "/autoMode", true);
          Firebase.RTDB.setBool(&fbdo, pathStatus + "/timerMode", false);
          Firebase.RTDB.setString(&fbdo, pathControl + "/command", "NONE");
        }
        else if (cmd == "AUTO_OFF") {
          Serial.println("❌ Mode Otomatis NONAKTIF");
          autoModeEnabled = false;
          // AUTO_OFF berarti switch ke Timer mode
          timerModeEnabled = true;
          Firebase.RTDB.setBool(&fbdo, pathStatus + "/autoMode", false);
          Firebase.RTDB.setBool(&fbdo, pathStatus + "/timerMode", true);
          Firebase.RTDB.setString(&fbdo, pathControl + "/command", "NONE");
        }
      }
    }
    
    // 3. BACA TIMER MODE & INTERVAL dari Firebase
    if (Firebase.RTDB.getBool(&fbdo, pathStatus + "/timerMode")) {
      bool firebaseTimerMode = fbdo.boolData();
      if (firebaseTimerMode != timerModeEnabled) {
        timerModeEnabled = firebaseTimerMode;
        // Pastikan hanya satu mode aktif
        if (timerModeEnabled) {
          autoModeEnabled = false;
        }
        Serial.print("🔄 TimerMode di-sync dari Firebase: ");
        Serial.println(timerModeEnabled ? "AKTIF" : "NONAKTIF");
      }
    }
    
    if (Firebase.RTDB.getInt(&fbdo, pathStatus + "/timerInterval")) {
      int firebaseInterval = fbdo.intData();
      // Validasi range: 5-180 menit
      if (firebaseInterval >= 5 && firebaseInterval <= 180 && firebaseInterval != (int)timerInterval) {
        timerInterval = (unsigned long)firebaseInterval;
        Serial.print("🔄 TimerInterval di-sync dari Firebase: ");
        Serial.print(timerInterval);
        Serial.println(" menit");
        // Reset timer jika interval berubah
        lastTimerClean = 0;
      }
    }
    
    // 4. BACA autoMode dari Firebase (jika diubah manual di Firebase Console)
    if (Firebase.RTDB.getBool(&fbdo, pathStatus + "/autoMode")) {
      bool firebaseAutoMode = fbdo.boolData();
      if (firebaseAutoMode != autoModeEnabled) {
        autoModeEnabled = firebaseAutoMode;
        // Pastikan hanya satu mode aktif
        if (autoModeEnabled) {
          timerModeEnabled = false;
        }
        Serial.print("🔄 AutoMode di-sync dari Firebase: ");
        Serial.println(autoModeEnabled ? "AKTIF" : "NONAKTIF");
      }
    }
  }
}