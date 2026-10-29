#include <DHT.h>
#include <PubSubClient.h>
#include <SinricPro.h>
#include <SinricProDimSwitch.h>
#include <SinricProSwitch.h>
#include <SinricProTemperaturesensor.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>

#include "root_ca.h"
#if __has_include("secrets.h")
#include "secrets.h"
#else
#error "Copy secrets.example.h to secrets.h and enter your Wi-Fi, MQTT, and Sinric Pro credentials."
#endif

// ---------- PINS ----------
#define SOIL_PIN 1
#define WATER_LEVEL_PIN 2
#define RAIN_PIN 3
#define DHT_PIN 12
#define PUMP_RELAY_PIN 16
#define PUMP_BUTTON_PIN 17
#define FLOW_PIN 21

#define DHT_TYPE DHT22
#define PUMP_ON LOW
#define PUMP_OFF HIGH

// ---------- CALIBRATION ----------
constexpr int SOIL_DRY_VALUE = 2050;
constexpr int SOIL_WET_VALUE = 1000;
constexpr int WATER_EMPTY_VALUE = 0;
constexpr int WATER_FULL_VALUE = 3000;

// ---------- MQTT / TIMING ----------
constexpr char MQTT_HOST[] =
    "6356f8b40c434ceea40f3ba7d1954153.s1.eu.hivemq.cloud";
constexpr uint16_t MQTT_PORT = 8883;
constexpr char TELEMETRY_TOPIC[] = "smartfarm/esp32-s3/telemetry";
constexpr char PUMP_COMMAND_TOPIC[] = "smartfarm/esp32-s3/pump/set";
constexpr unsigned long SAMPLE_INTERVAL_MS = 2500;
constexpr unsigned long MQTT_RECONNECT_INTERVAL_MS = 5000;
constexpr unsigned long WIFI_RECONNECT_INTERVAL_MS = 10000;
constexpr unsigned long SINRIC_SENSOR_INTERVAL_MS = 60000;
constexpr unsigned long PUMP_MAX_RUNTIME_MS = 60000;
constexpr unsigned long BUTTON_DEBOUNCE_MS = 50;

DHT dht(DHT_PIN, DHT_TYPE);
WiFiClientSecure secureClient;
PubSubClient mqttClient(secureClient);

volatile uint32_t flowPulses = 0;
unsigned long lastSampleAt = 0;
unsigned long lastMqttAttemptAt = 0;
unsigned long lastWiFiAttemptAt = 0;
unsigned long lastSinricSensorAt = 0;
unsigned long pumpStartedAt = 0;
unsigned long buttonChangedAt = 0;
bool wifiWasConnected = false;
bool pumpOn = false;
bool lastButtonReading = HIGH;
bool stableButtonState = HIGH;
int latestSoilMoisture = -1;
float latestTemperature = NAN;
float latestHumidity = NAN;

void IRAM_ATTR flowPulse() { flowPulses++; }

int percentageFromRaw(int raw, int emptyValue, int fullValue) {
  return constrain(map(raw, emptyValue, fullValue, 0, 100), 0, 100);
}

void setPump(bool state, bool notifySinric = true) {
  pumpOn = state;
  pumpStartedAt = state ? millis() : 0;
  digitalWrite(PUMP_RELAY_PIN, state ? PUMP_ON : PUMP_OFF);
  Serial.printf("Pump: %s\n", state ? "ON" : "OFF");

  if (notifySinric) {
    SinricProSwitch &pump = SinricPro[SINRIC_PUMP_DEVICE_ID];
    pump.sendPowerStateEvent(state);
  }
}

bool onSinricPumpPower(const String &deviceId, bool &state) {
  setPump(state, false);
  return true;
}

#ifdef SINRIC_SOIL_DEVICE_ID
bool onSoilPower(const String &deviceId, bool &state) {
  state = true;
  return true;
}

bool onSoilPowerLevel(const String &deviceId, int &powerLevel) {
  if (latestSoilMoisture >= 0) powerLevel = latestSoilMoisture;
  return true;
}
#endif

void onMqttMessage(char *topic, byte *payload, unsigned int length) {
  if (strcmp(topic, PUMP_COMMAND_TOPIC) != 0) return;

  const bool turnOn = length == 2 && payload[0] == 'O' && payload[1] == 'N';
  const bool turnOff = length == 3 && payload[0] == 'O' && payload[1] == 'F' &&
                       payload[2] == 'F';
  if (turnOn || turnOff) setPump(turnOn);
}

void handlePumpButton(unsigned long now) {
  const bool reading = digitalRead(PUMP_BUTTON_PIN);
  if (reading != lastButtonReading) {
    lastButtonReading = reading;
    buttonChangedAt = now;
  }

  if (now - buttonChangedAt >= BUTTON_DEBOUNCE_MS &&
      reading != stableButtonState) {
    stableButtonState = reading;
    if (stableButtonState == LOW) setPump(!pumpOn);
  }
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
  if (now - lastMqttAttemptAt < MQTT_RECONNECT_INTERVAL_MS) return;
  lastMqttAttemptAt = now;

  const uint64_t chipId = ESP.getEfuseMac();
  char clientId[32];
  snprintf(clientId, sizeof(clientId), "smartfarm-%04X%08X",
           static_cast<unsigned int>((chipId >> 32) & 0xFFFF),
           static_cast<unsigned int>(chipId & 0xFFFFFFFF));

  Serial.printf("Connecting to HiveMQ as %s... ", clientId);
  if (mqttClient.connect(clientId, MQTT_USERNAME, MQTT_PASSWORD)) {
    Serial.println("connected.");
    mqttClient.subscribe(PUMP_COMMAND_TOPIC);
  } else {
    Serial.printf("failed, MQTT state = %d\n", mqttClient.state());
  }
}

void publishSinricSensors(unsigned long now) {
  if (latestSoilMoisture < 0 && isnan(latestTemperature)) return;
  if (now - lastSinricSensorAt < SINRIC_SENSOR_INTERVAL_MS) return;
  lastSinricSensorAt = now;

#ifdef SINRIC_SOIL_DEVICE_ID
  if (latestSoilMoisture >= 0) {
    SinricProDimSwitch &soil = SinricPro[SINRIC_SOIL_DEVICE_ID];
    soil.sendPowerStateEvent(true);
    soil.sendPowerLevelEvent(latestSoilMoisture);
  }
#endif

#ifdef SINRIC_CLIMATE_DEVICE_ID
  if (!isnan(latestTemperature) && !isnan(latestHumidity)) {
    SinricProTemperaturesensor &climate =
        SinricPro[SINRIC_CLIMATE_DEVICE_ID];
    climate.sendTemperatureEvent(latestTemperature, latestHumidity);
  }
#endif
}

void readAndPublishSensors() {
  const int soilRaw = analogRead(SOIL_PIN);
  const int waterRaw = analogRead(WATER_LEVEL_PIN);
  const int soilMoisture =
      percentageFromRaw(soilRaw, SOIL_DRY_VALUE, SOIL_WET_VALUE);
  const int waterLevel =
      percentageFromRaw(waterRaw, WATER_EMPTY_VALUE, WATER_FULL_VALUE);
  const bool raining = digitalRead(RAIN_PIN) == LOW;
  const float temperature = dht.readTemperature();
  const float humidity = dht.readHumidity();

  noInterrupts();
  const uint32_t pulses = flowPulses;
  flowPulses = 0;
  interrupts();

  latestSoilMoisture = soilMoisture;
  if (!isnan(temperature) && !isnan(humidity)) {
    latestTemperature = temperature;
    latestHumidity = humidity;
  }

  Serial.printf("Soil: %d (%d%%) | Water: %d (%d%%) | Rain: %s | ", soilRaw,
                soilMoisture, waterRaw, waterLevel,
                raining ? "WET" : "DRY");
  if (isnan(temperature) || isnan(humidity)) {
    Serial.print("DHT22: ERROR");
  } else {
    Serial.printf("Temp: %.1f C | Humidity: %.1f%%", temperature, humidity);
  }
  Serial.printf(" | Flow pulses: %lu | Pump: %s\n",
                static_cast<unsigned long>(pulses), pumpOn ? "ON" : "OFF");

  if (!mqttClient.connected()) {
    Serial.println("MQTT offline; telemetry packet skipped.");
    return;
  }

  char temperatureJson[16];
  char humidityJson[16];
  if (isnan(temperature) || isnan(humidity)) {
    strcpy(temperatureJson, "null");
    strcpy(humidityJson, "null");
  } else {
    snprintf(temperatureJson, sizeof(temperatureJson), "%.1f", temperature);
    snprintf(humidityJson, sizeof(humidityJson), "%.1f", humidity);
  }

  char payload[384];
  const int length = snprintf(
      payload, sizeof(payload),
      "{\"soilRaw\":%d,\"soilMoisture\":%d,\"waterLevelRaw\":%d,"
      "\"waterLevel\":%d,\"raining\":%s,\"temperature\":%s,"
      "\"humidity\":%s,\"flowPulses\":%lu,\"intervalMs\":%lu,"
      "\"pumpOn\":%s}",
      soilRaw, soilMoisture, waterRaw, waterLevel,
      raining ? "true" : "false", temperatureJson, humidityJson,
      static_cast<unsigned long>(pulses), SAMPLE_INTERVAL_MS,
      pumpOn ? "true" : "false");

  if (length < 0 || static_cast<size_t>(length) >= sizeof(payload)) {
    Serial.println("Telemetry payload buffer is too small.");
    return;
  }

  const bool published = mqttClient.publish(TELEMETRY_TOPIC, payload, true);
  Serial.print(published ? "Published: " : "Publish failed: ");
  Serial.println(payload);
}

void setupSinricPro() {
  SinricProSwitch &pump = SinricPro[SINRIC_PUMP_DEVICE_ID];
  pump.onPowerState(onSinricPumpPower);

#ifdef SINRIC_SOIL_DEVICE_ID
  SinricProDimSwitch &soil = SinricPro[SINRIC_SOIL_DEVICE_ID];
  soil.onPowerState(onSoilPower);
  soil.onPowerLevel(onSoilPowerLevel);
#endif

#ifdef SINRIC_CLIMATE_DEVICE_ID
  SinricProTemperaturesensor &climate =
      SinricPro[SINRIC_CLIMATE_DEVICE_ID];
#endif

  SinricPro.onConnected([]() {
    Serial.println("Sinric Pro connected.");
    SinricProSwitch &pump = SinricPro[SINRIC_PUMP_DEVICE_ID];
    pump.sendPowerStateEvent(pumpOn);
    lastSinricSensorAt = millis() - SINRIC_SENSOR_INTERVAL_MS;
  });
  SinricPro.onDisconnected(
      []() { Serial.println("Sinric Pro disconnected."); });
  SinricPro.begin(SINRIC_APP_KEY, SINRIC_APP_SECRET);
}

void setup() {
  Serial.begin(115200);
  delay(2000);
  Serial.println("\n=== AquaCrop ESP32-S3 starting ===");

  dht.begin();
  analogReadResolution(12);
  pinMode(SOIL_PIN, INPUT);
  pinMode(WATER_LEVEL_PIN, INPUT);
  pinMode(RAIN_PIN, INPUT);
  pinMode(FLOW_PIN, INPUT_PULLUP);
  pinMode(PUMP_RELAY_PIN, OUTPUT);
  pinMode(PUMP_BUTTON_PIN, INPUT_PULLUP);
  digitalWrite(PUMP_RELAY_PIN, PUMP_OFF);
  attachInterrupt(digitalPinToInterrupt(FLOW_PIN), flowPulse, RISING);

  WiFi.mode(WIFI_STA);
  secureClient.setCACert(HIVE_MQ_ROOT_CA);
  mqttClient.setServer(MQTT_HOST, MQTT_PORT);
  mqttClient.setCallback(onMqttMessage);
  mqttClient.setBufferSize(512);
  mqttClient.setKeepAlive(30);
  setupSinricPro();

  lastWiFiAttemptAt = millis() - WIFI_RECONNECT_INTERVAL_MS;
  lastMqttAttemptAt = millis() - MQTT_RECONNECT_INTERVAL_MS;
  lastSinricSensorAt = millis() - SINRIC_SENSOR_INTERVAL_MS;
  maintainWiFi();
}

void loop() {
  maintainWiFi();
  connectMqtt();
  mqttClient.loop();
  SinricPro.handle();

  const unsigned long now = millis();
  handlePumpButton(now);

  if (pumpOn && now - pumpStartedAt >= PUMP_MAX_RUNTIME_MS) {
    Serial.println("Pump safety timeout reached.");
    setPump(false);
  }

  if (now - lastSampleAt >= SAMPLE_INTERVAL_MS) {
    lastSampleAt = now;
    readAndPublishSensors();
  }
  publishSinricSensors(now);
  delay(5);
}
