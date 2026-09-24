#include <DHT.h>
#include <PubSubClient.h>
#include <SinricPro.h>
#include <SinricProSwitch.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>

#include "root_ca.h"
#if __has_include("secrets.h")
#include "secrets.h"
#else
#error "Copy secrets.example.h to secrets.h and enter your Wi-Fi, MQTT, and Sinric Pro credentials."
#endif

// ---------- SENSOR PINS ----------
#define SOIL_PIN 1
#define WATER_LEVEL_PIN 2
#define RAIN_PIN 3
#define DHT_PIN 12
#define FLOW_PIN 21
#define PUMP_RELAY_PIN 16

#define DHT_TYPE DHT22
#define PUMP_ON LOW
#define PUMP_OFF HIGH

// ---------- MQTT ----------
constexpr char MQTT_HOST[] =
    "8255d88bbacc45fd89c2580a5887a138.s1.eu.hivemq.cloud";
constexpr uint16_t MQTT_PORT = 8883;
constexpr char TELEMETRY_TOPIC[] = "smartfarm/esp32-s3/telemetry";
constexpr char PUMP_COMMAND_TOPIC[] = "smartfarm/esp32-s3/pump/set";
constexpr unsigned long SAMPLE_INTERVAL_MS = 2500;
constexpr unsigned long RECONNECT_INTERVAL_MS = 5000;
constexpr unsigned long WIFI_RECONNECT_INTERVAL_MS = 10000;
constexpr unsigned long PUMP_MAX_RUNTIME_MS = 60000;

DHT dht(DHT_PIN, DHT_TYPE);
WiFiClientSecure secureClient;
PubSubClient mqttClient(secureClient);

volatile uint32_t flowPulses = 0;
unsigned long lastSampleAt = 0;
unsigned long lastMqttAttemptAt = 0;
unsigned long lastWiFiAttemptAt = 0;
bool wifiWasConnected = false;
bool pumpOn = false;
unsigned long pumpStartedAt = 0;

void IRAM_ATTR flowPulse() {
  flowPulses++;
}

void setPump(bool state, bool notifySinric = true) {
  pumpOn = state;
  pumpStartedAt = state ? millis() : 0;
  digitalWrite(PUMP_RELAY_PIN, state ? PUMP_ON : PUMP_OFF);
  Serial.printf("Pump: %s\n", state ? "ON" : "OFF");

  if (notifySinric) {
    SinricProSwitch &pump = SinricPro[SINRIC_DEVICE_ID];
    pump.sendPowerStateEvent(state);
  }
}

bool onSinricPumpPower(const String &deviceId, bool &state) {
  setPump(state, false);
  return true;
}

void onMqttMessage(char *topic, byte *payload, unsigned int length) {
  if (strcmp(topic, PUMP_COMMAND_TOPIC) != 0) return;

  const bool turnOn = length == 2 && payload[0] == 'O' && payload[1] == 'N';
  const bool turnOff = length == 3 && payload[0] == 'O' && payload[1] == 'F' &&
                       payload[2] == 'F';
  if (turnOn || turnOff) setPump(turnOn);
}

void maintainWiFi() {
  if (WiFi.status() == WL_CONNECTED) {
    if (!wifiWasConnected) {
      wifiWasConnected = true;
      Serial.print("Wi-Fi connected. IP: ");
      Serial.println(WiFi.localIP());
    }
    return;
  }

  if (wifiWasConnected) {
    wifiWasConnected = false;
    Serial.println("Wi-Fi disconnected.");
  }

  const unsigned long now = millis();
  if (now - lastWiFiAttemptAt < WIFI_RECONNECT_INTERVAL_MS) return;
  lastWiFiAttemptAt = now;

  Serial.println("Starting Wi-Fi connection...");
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
}

void connectMqtt() {
  if (WiFi.status() != WL_CONNECTED || mqttClient.connected()) return;

  const unsigned long now = millis();
  if (now - lastMqttAttemptAt < RECONNECT_INTERVAL_MS) return;
  lastMqttAttemptAt = now;

  const uint64_t chipId = ESP.getEfuseMac();
  char clientId[32];
  snprintf(clientId, sizeof(clientId), "smartfarm-%04X%08X",
           static_cast<unsigned int>((chipId >> 32) & 0xFFFF),
           static_cast<unsigned int>(chipId & 0xFFFFFFFF));

  Serial.print("Connecting to HiveMQ as ");
  Serial.print(clientId);
  Serial.print("... ");

  if (mqttClient.connect(clientId, MQTT_USERNAME, MQTT_PASSWORD)) {
    Serial.println("connected.");
    mqttClient.subscribe(PUMP_COMMAND_TOPIC);
  } else {
    Serial.print("failed, MQTT state = ");
    Serial.println(mqttClient.state());
  }
}

void publishSensorData() {
  const int soilRaw = analogRead(SOIL_PIN);
  const int waterLevelRaw = analogRead(WATER_LEVEL_PIN);
  const bool raining = digitalRead(RAIN_PIN) == LOW;
  const float temperature = dht.readTemperature();
  const float humidity = dht.readHumidity();

  noInterrupts();
  const uint32_t pulses = flowPulses;
  flowPulses = 0;
  interrupts();

  Serial.printf(
      "Soil: %d | Water: %d | Rain: %s | Temp: %.1f C | Humidity: %.1f %% "
      "| Pulses: %lu\n",
      soilRaw, waterLevelRaw, raining ? "YES" : "NO", temperature, humidity,
      static_cast<unsigned long>(pulses));

  if (isnan(temperature) || isnan(humidity)) {
    Serial.println("DHT22 read failed; telemetry packet skipped.");
    return;
  }

  if (!mqttClient.connected()) {
    Serial.println("MQTT offline; telemetry packet skipped.");
    return;
  }

  char payload[256];
  const int length = snprintf(
      payload, sizeof(payload),
      "{\"soilRaw\":%d,\"waterLevelRaw\":%d,\"raining\":%s,"
      "\"temperature\":%.1f,\"humidity\":%.1f,\"flowPulses\":%lu,"
      "\"intervalMs\":%lu,\"pumpOn\":%s}",
      soilRaw, waterLevelRaw, raining ? "true" : "false", temperature,
      humidity, static_cast<unsigned long>(pulses), SAMPLE_INTERVAL_MS,
      pumpOn ? "true" : "false");

  if (length < 0 || static_cast<size_t>(length) >= sizeof(payload)) {
    Serial.println("Telemetry payload buffer is too small.");
    return;
  }

  const bool published = mqttClient.publish(TELEMETRY_TOPIC, payload, true);
  Serial.print(published ? "Published: " : "Publish failed: ");
  Serial.println(payload);
}

void setup() {
  Serial.begin(115200);
  delay(500);

  dht.begin();
  analogReadResolution(12);
  pinMode(SOIL_PIN, INPUT);
  pinMode(WATER_LEVEL_PIN, INPUT);
  pinMode(RAIN_PIN, INPUT);
  pinMode(FLOW_PIN, INPUT_PULLUP);
  pinMode(PUMP_RELAY_PIN, OUTPUT);
  digitalWrite(PUMP_RELAY_PIN, PUMP_OFF);
  attachInterrupt(digitalPinToInterrupt(FLOW_PIN), flowPulse, RISING);

  WiFi.mode(WIFI_STA);
  secureClient.setCACert(HIVE_MQ_ROOT_CA);
  mqttClient.setServer(MQTT_HOST, MQTT_PORT);
  mqttClient.setCallback(onMqttMessage);
  mqttClient.setBufferSize(512);
  mqttClient.setKeepAlive(30);

  SinricProSwitch &pump = SinricPro[SINRIC_DEVICE_ID];
  pump.onPowerState(onSinricPumpPower);
  SinricPro.onConnected([]() {
    Serial.println("Sinric Pro connected.");
    SinricProSwitch &pump = SinricPro[SINRIC_DEVICE_ID];
    pump.sendPowerStateEvent(pumpOn);
  });
  SinricPro.onDisconnected(
      []() { Serial.println("Sinric Pro disconnected."); });
  SinricPro.begin(SINRIC_APP_KEY, SINRIC_APP_SECRET);

  lastWiFiAttemptAt = millis() - WIFI_RECONNECT_INTERVAL_MS;
  maintainWiFi();
  lastMqttAttemptAt = millis() - RECONNECT_INTERVAL_MS;
}

void loop() {
  maintainWiFi();
  connectMqtt();
  mqttClient.loop();
  SinricPro.handle();

  const unsigned long now = millis();
  if (pumpOn && now - pumpStartedAt >= PUMP_MAX_RUNTIME_MS) {
    Serial.println("Pump safety timeout reached.");
    setPump(false);
  }

  if (now - lastSampleAt >= SAMPLE_INTERVAL_MS) {
    lastSampleAt = now;
    publishSensorData();
  }

  delay(5);
}
