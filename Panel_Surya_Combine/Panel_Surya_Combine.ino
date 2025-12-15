/*
====================================================
  SISTEM PEMBERSIH PANEL SURYA OTOMATIS
  ESP32 + L298N + GP2Y1014AU0F + Rain Sensor
====================================================
*/

// ================= PIN DEFINITIONS =================

// Dust Sensor
#define DUST_PIN 34
#define DUST_LED 25

// Rain Sensor
#define RAIN_SENSOR 4

// Pump (MOSFET)
#define PUMP_PIN 13

// Motor A (L298N)
#define IN1 26
#define IN2 27
#define ENA 14   // PWM

// Motor B (L298N)
#define IN3 33
#define IN4 32
#define ENB 12   // PWM (BOOT PIN ⚠️)

// ================= PWM CONFIG =================

#define PWM_FREQ 1000
#define PWM_RES  8       // 0–255
#define PWM_CH_A 0
#define PWM_CH_B 1

int motorSpeed = 200;

// ================= MODE & STATE =================

enum Mode {
  MODE_NONE,
  MODE_AUTO,
  MODE_TIMER
};

enum State {
  IDLE,
  MONITORING_DUST,
  CLEANING_PROCESS,
  WAIT_TIMER_INPUT,
  COUNTDOWN
};

Mode currentMode = MODE_NONE;
State currentState = IDLE;

// ================= TIMING =================

unsigned long lastDustCheck = 0;
const unsigned long DUST_INTERVAL = 300000; // 5 menit

unsigned long countdownStart = 0;
unsigned long countdownDuration = 0;

// ================= GLOBAL =================

float dustPercent = 0;

// ==================================================
//                    UTILITIES
// ==================================================

void stopAll() {
  ledcWrite(PWM_CH_A, 0);
  ledcWrite(PWM_CH_B, 0);
  digitalWrite(PUMP_PIN, LOW);
}

// ==================================================
//                CLEANING PROCESS
// ==================================================

void cleaningProcess() {
  Serial.println("\n================================");
  Serial.println("🚿 PROSES PEMBERSIHAN DIMULAI");
  Serial.println("================================");

  // Pompa ON
  digitalWrite(PUMP_PIN, HIGH);
  Serial.println("💧 Pompa air MENYALA");
  delay(2000);

  // Motor A
  Serial.println("🔄 Motor A bergerak (5 detik)");
  digitalWrite(IN1, HIGH);
  digitalWrite(IN2, LOW);
  ledcWrite(PWM_CH_A, motorSpeed);
  delay(5000);
  ledcWrite(PWM_CH_A, 0);

  // Motor B
  Serial.println("🔄 Motor B bergerak (5 detik)");
  digitalWrite(IN3, HIGH);
  digitalWrite(IN4, LOW);
  ledcWrite(PWM_CH_B, motorSpeed);
  delay(5000);
  ledcWrite(PWM_CH_B, 0);

  // Pompa OFF
  digitalWrite(PUMP_PIN, LOW);

  Serial.println("✅ PEMBERSIHAN SELESAI");
  Serial.println("================================\n");
}

// ==================================================
//                   DUST SENSOR
// ==================================================

float readDustPercent() {
  digitalWrite(DUST_LED, LOW);
  delayMicroseconds(280);
  int adc = analogRead(DUST_PIN);
  delayMicroseconds(40);
  digitalWrite(DUST_LED, HIGH);
  delayMicroseconds(9680);

  float voltage = adc * (3.3 / 4096.0);
  float density = 0.17 * voltage - 0.1;
  if (density < 0) density = 0;

  return constrain(density * 100, 0, 100);
}

String dustStatus(float percent) {
  if (percent <= 30) return "BERSIH";
  if (percent <= 50) return "BERDEBU";
  return "BERDEBU BANGET";
}

// ==================================================
//                   RAIN SENSOR
// ==================================================

bool isRaining() {
  // SESUAI HARDWARE KAMU
  return digitalRead(RAIN_SENSOR) == HIGH;
}

// ==================================================
//                  SERIAL INPUT
// ==================================================

void readModeInput() {
  if (Serial.available()) {
    int input = Serial.parseInt();

    if (input == 1) {
      currentMode = MODE_AUTO;
      currentState = MONITORING_DUST;
      Serial.println("\n🟢 MODE OTOMATIS AKTIF");
    }
    else if (input == 2) {
      currentMode = MODE_TIMER;
      currentState = WAIT_TIMER_INPUT;
      Serial.println("\n🟠 MODE TIMER AKTIF");
      Serial.println("Masukkan timer (detik): ");
    }
  }
}

// ==================================================
//                MODE OTOMATIS
// ==================================================

void handleAutoMode() {
  if (currentState == MONITORING_DUST) {
    if (millis() - lastDustCheck >= DUST_INTERVAL) {
      lastDustCheck = millis();

      dustPercent = readDustPercent();
      Serial.print("📊 Debu: ");
      Serial.print(dustPercent);
      Serial.print("% | ");
      Serial.println(dustStatus(dustPercent));

      if (dustPercent >= 51) {
        currentState = CLEANING_PROCESS;
      }
    }
  }

  if (currentState == CLEANING_PROCESS) {
    cleaningProcess();
    currentState = MONITORING_DUST;
  }
}

// ==================================================
//                 MODE TIMER
// ==================================================

void handleTimerMode() {
  if (currentState == WAIT_TIMER_INPUT) {
    if (Serial.available()) {
      countdownDuration = Serial.parseInt() * 1000;
      countdownStart = millis();
      currentState = COUNTDOWN;
      Serial.println("⏳ HITUNG MUNDUR DIMULAI");
    }
  }

  if (currentState == COUNTDOWN) {

    if (isRaining()) {
      Serial.println("🌧️ HUJAN TERDETEKSI → TIMER RESET");
      countdownStart = millis();
      delay(2000);
    }

    if (millis() - countdownStart >= countdownDuration) {
      Serial.println("⏰ TIMER HABIS");
      cleaningProcess();
      countdownStart = millis();
    }
  }
}

// ==================================================
//                     SETUP
// ==================================================

void setup() {
  Serial.begin(115200);

  pinMode(DUST_LED, OUTPUT);
  pinMode(DUST_PIN, INPUT);
  pinMode(RAIN_SENSOR, INPUT);

  pinMode(PUMP_PIN, OUTPUT);

  pinMode(IN1, OUTPUT);
  pinMode(IN2, OUTPUT);
  pinMode(IN3, OUTPUT);
  pinMode(IN4, OUTPUT);

  // ===== PWM SETUP (KRITIS) =====
  ledcSetup(PWM_CH_A, PWM_FREQ, PWM_RES);
  ledcSetup(PWM_CH_B, PWM_FREQ, PWM_RES);
  ledcAttachPin(ENA, PWM_CH_A);
  ledcAttachPin(ENB, PWM_CH_B);

  stopAll();

  Serial.println("================================");
  Serial.println(" SISTEM PANEL SURYA OTOMATIS ");
  Serial.println("================================");
  Serial.println("1. Mode Otomatis");
  Serial.println("2. Mode Timer");
}

// ==================================================
//                      LOOP
// ==================================================

void loop() {
  readModeInput();

  if (currentMode == MODE_AUTO) {
    handleAutoMode();
  }
  else if (currentMode == MODE_TIMER) {
    handleTimerMode();
  }
}
