#include <DHT.h>
#include <PubSubClient.h>
#include <SinricPro.h>
#include <SinricProDimSwitch.h>
#include <SinricProSwitch.h>
#include <SinricProTemperaturesensor.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>

// =====================================================
// LOCAL CREDENTIALS (IGNORED BY GIT)
// =====================================================

#if __has_include("esp32/SmartFarmMqtt/secrets.h")
#include "esp32/SmartFarmMqtt/secrets.h"
#else
#error "Missing esp32/SmartFarmMqtt/secrets.h"
#endif

// =====================================================
// PIN DEFINITIONS — TEAM LEAD VALUES PRESERVED
// =====================================================

#define SOIL_PIN 1
#define WATER_LEVEL_PIN 2
#define RAIN_PIN 3
#define DHT_PIN 12
#define FLOW_PIN 21

// Added for pump control.
#define PUMP_RELAY_PIN 16
#define PUMP_BUTTON_PIN 17

#define DHT_TYPE DHT22

// Most relay modules are active-low.
#define PUMP_ON LOW
#define PUMP_OFF HIGH

DHT dht(DHT_PIN, DHT_TYPE);

// =====================================================
// CALIBRATION — TEAM LEAD VALUES PRESERVED
// =====================================================

const int SOIL_DRY_VALUE = 2050;
const int SOIL_WET_VALUE = 1000;

const int WATER_EMPTY_VALUE = 0;
const int WATER_FULL_VALUE = 3000;

// =====================================================
// MQTT
// =====================================================

const char MQTT_HOST[] =
    "6356f8b40c434ceea40f3ba7d1954153.s1.eu.hivemq.cloud";

const uint16_t MQTT_PORT = 8883;

const char TELEMETRY_TOPIC[] =
    "smartfarm/esp32-s3/telemetry";

const char PUMP_COMMAND_TOPIC[] =
    "smartfarm/esp32-s3/pump/set";

// =====================================================
// TIMING
// =====================================================

const unsigned long SAMPLE_INTERVAL_MS = 2500;
const unsigned long MQTT_RECONNECT_INTERVAL_MS = 5000;
const unsigned long WIFI_RECONNECT_INTERVAL_MS = 10000;
const unsigned long SINRIC_SENSOR_INTERVAL_MS = 60000;
const unsigned long PUMP_MAX_RUNTIME_MS = 60000;
const unsigned long BUTTON_DEBOUNCE_MS = 50;

// =====================================================
// HIVE MQ TLS ROOT CERTIFICATE
// Public certificate — not a secret
// =====================================================

static const char HIVE_MQ_ROOT_CA[] PROGMEM = R"EOF(
-----BEGIN CERTIFICATE-----
MIIFazCCA1OgAwIBAgIRAIIQz7DSQONZRGPgu2OCiwAwDQYJKoZIhvcNAQELBQAw
TzELMAkGA1UEBhMCVVMxKTAnBgNVBAoTIEludGVybmV0IFNlY3VyaXR5IFJlc2Vh
cmNoIEdyb3VwMRUwEwYDVQQDEwxJU1JHIFJvb3QgWDEwHhcNMTUwNjA0MTEwNDM4
WhcNMzUwNjA0MTEwNDM4WjBPMQswCQYDVQQGEwJVUzEpMCcGA1UEChMgSW50ZXJu
ZXQgU2VjdXJpdHkgUmVzZWFyY2ggR3JvdXAxFTATBgNVBAMTDElTUkcgUm9vdCBY
MTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAK3oJHP0FDfzm54rVygc
h77ct984kIxuPOZXoHj3dcKi/vVqbvYATyjb3miGbESTtrFj/RQSa78f0uoxmyF+
0TM8ukj13Xnfs7j/EvEhmkvBioZxaUpmZmyPfjxwv60pIgbz5MDmgK7iS4+3mX6U
A5/TR5d8mUgjU+g4rk8Kb4Mu0UlXjIB0ttov0DiNewNwIRt18jA8+o+u3dpjq+sW
T8KOEUt+zwvo/7V3LvSye0rgTBIlDHCNAymg4VMk7BPZ7hm/ELNKjD+Jo2FR3qyH
B5T0Y3HsLuJvW5iB4YlcNHlsdu87kGJ55tukmi8mxdAQ4Q7e2RCOFvu396j3x+UC
B5iPNgiV5+I3lg02dZ77DnKxHZu8A/lJBdiB3QW0KtZB6awBdpUKD9jf1b0SHzUv
KBds0pjBqAlkd25HN7rOrFleaJ1/ctaJxQZBKT5ZPt0m9STJEadao0xAH0ahmbWn
OlFuhjuefXKnEgV4We0+UXgVCwOPjdAvBbI+e0ocS3MFEvzG6uBQE3xDk3SzynTn
jh8BCNAw1FtxNrQHusEwMFxIt4I7mKZ9YIqioymCzLq9gwQbooMDQaHWBfEbwrbw
qHyGO0aoSCqI3Haadr8faqU9GY/rOPNk3sgrDQoo//fb4hVC1CLQJ13hef4Y53CI
rU7m2Ys6xt0nUW7/vGT1M0NPAgMBAAGjQjBAMA4GA1UdDwEB/wQEAwIBBjAPBgNV
HRMBAf8EBTADAQH/MB0GA1UdDgQWBBR5tFnme7bl5AFzgAiIyBpY9umbbjANBgkq
hkiG9w0BAQsFAAOCAgEAVR9YqbyyqFDQDLHYGmkgJykIrGF1XIpu+ILlaS/V9lZL
ubhzEFnTIZd+50xx+7LSYK05qAvqFyFWhfFQDlnrzuBZ6brJFe+GnY+EgPbk6ZGQ
3BebYhtF8GaV0nxvwuo77x/Py9auJ/GpsMiu/X1+mvoiBOv/2X/qkSsisRcOj/KK
NFtY2PwByVS5uCbMiogziUwthDyC3+6WVwW6LLv3xLfHTjuCvjHIInNzktHCgKQ5
ORAzI4JMPJ+GslWYHb4phowim57iaztXOoJwTdwJx4nLCgdNbOhdjsnvzqvHu7Ur
TkXWStAmzOVyyghqpZXjFaH3pO3JLF+l+/+sKAIuvtd7u+Nxe5AW0wdeRlN8NwdC
jNPElpzVmbUq4JUagEiuTDkHzsxHpFKVK7q4+63SM1N95R1NbdWhscdCb+ZAJzVc
oyi3B43njTOQ5yOf+1CceWxG1bQVs5ZufpsMljq4Ui0/1lvh+wjChP4kqKOJ2qxq
4RgqsahDYVvTH9w7jXbyLeiNdd8XM2w9U/t7y0Ff/9yi0GE44Za4rF2LN9d11TPA
mRGunUHBcnWEvgJBQl9nJEiU0Zsnvgc/ubhPgXRR4Xq37Z0j4r7g1SgEEzwxA57d
emyPxgcYxn/eR44/KJ4EBs+lVDR3veyJm+kXQ99b21/+jh5Xos1AnX5iItreGCc=
-----END CERTIFICATE-----
)EOF";

// =====================================================
// GLOBAL OBJECTS AND STATE
// =====================================================

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

// =====================================================
// FLOW SENSOR INTERRUPT
// =====================================================

void IRAM_ATTR flowPulse()
{
  flowPulses++;
}

// =====================================================
// CALIBRATION HELPER
// =====================================================

int percentageFromRaw(
    int raw,
    int emptyValue,
    int fullValue)
{
  int percentage = map(
      raw,
      emptyValue,
      fullValue,
      0,
      100);

  return constrain(percentage, 0, 100);
}

// =====================================================
// PUMP CONTROL
// =====================================================

void setPump(bool state, bool notifySinric = true)
{
  pumpOn = state;

  if (state)
  {
    pumpStartedAt = millis();
  }
  else
  {
    pumpStartedAt = 0;
  }

  digitalWrite(
      PUMP_RELAY_PIN,
      state ? PUMP_ON : PUMP_OFF);

  Serial.print("Pump: ");
  Serial.println(state ? "ON" : "OFF");

  if (notifySinric)
  {
    SinricProSwitch &pump =
        SinricPro[SINRIC_PUMP_DEVICE_ID];

    pump.sendPowerStateEvent(state);
  }
}

// Called when Sinric Pro or Google Home controls the pump.
bool onSinricPumpPower(
    const String &deviceId,
    bool &state)
{
  setPump(state, false);
  return true;
}

// =====================================================
// SOIL-MOISTURE GOOGLE HOME WORKAROUND
// =====================================================

// The soil moisture is represented as brightness.
// Google can then answer the brightness percentage.

bool onSoilPower(
    const String &deviceId,
    bool &state)
{
  // The sensor should always remain logically on.
  state = true;
  return true;
}

bool onSoilPowerLevel(
    const String &deviceId,
    int &brightness)
{
  if (latestSoilMoisture >= 0)
  {
    brightness = latestSoilMoisture;
  }

  return true;
}

// =====================================================
// MQTT PUMP COMMAND
// =====================================================

void onMqttMessage(
    char *topic,
    byte *payload,
    unsigned int length)
{
  if (strcmp(topic, PUMP_COMMAND_TOPIC) != 0)
  {
    return;
  }

  bool turnOn =
      length == 2 &&
      payload[0] == 'O' &&
      payload[1] == 'N';

  bool turnOff =
      length == 3 &&
      payload[0] == 'O' &&
      payload[1] == 'F' &&
      payload[2] == 'F';

  if (turnOn)
  {
    setPump(true);
  }
  else if (turnOff)
  {
    setPump(false);
  }
  else
  {
    Serial.println("Invalid MQTT pump command.");
  }
}

// =====================================================
// PHYSICAL PUMP BUTTON
// =====================================================

// Connect a momentary button between GPIO 17 and GND.

void handlePumpButton(unsigned long now)
{
  bool reading = digitalRead(PUMP_BUTTON_PIN);

  if (reading != lastButtonReading)
  {
    lastButtonReading = reading;
    buttonChangedAt = now;
  }

  if (
      now - buttonChangedAt >= BUTTON_DEBOUNCE_MS &&
      reading != stableButtonState)
  {
    stableButtonState = reading;

    if (stableButtonState == LOW)
    {
      setPump(!pumpOn);
    }
  }
}

// =====================================================
// WI-FI
// =====================================================

void maintainWiFi()
{
  if (WiFi.status() == WL_CONNECTED)
  {
    if (!wifiWasConnected)
    {
      wifiWasConnected = true;

      Serial.print("Wi-Fi connected. IP: ");
      Serial.println(WiFi.localIP());
    }

    return;
  }

  if (wifiWasConnected)
  {
    wifiWasConnected = false;
    Serial.println("Wi-Fi disconnected.");
  }

  unsigned long now = millis();

  if (
      now - lastWiFiAttemptAt <
      WIFI_RECONNECT_INTERVAL_MS)
  {
    return;
  }

  lastWiFiAttemptAt = now;

  Serial.println("Starting Wi-Fi connection...");
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
}

// =====================================================
// MQTT CONNECTION
// =====================================================

void connectMqtt()
{
  if (
      WiFi.status() != WL_CONNECTED ||
      mqttClient.connected())
  {
    return;
  }

  unsigned long now = millis();

  if (
      now - lastMqttAttemptAt <
      MQTT_RECONNECT_INTERVAL_MS)
  {
    return;
  }

  lastMqttAttemptAt = now;

  uint64_t chipId = ESP.getEfuseMac();

  char clientId[32];

  snprintf(
      clientId,
      sizeof(clientId),
      "smartfarm-%04X%08X",
      static_cast<unsigned int>(
          (chipId >> 32) & 0xFFFF),
      static_cast<unsigned int>(
          chipId & 0xFFFFFFFF));

  Serial.print("Connecting to HiveMQ as ");
  Serial.print(clientId);
  Serial.print("... ");

  if (
      mqttClient.connect(
          clientId,
          MQTT_USERNAME,
          MQTT_PASSWORD))
  {
    Serial.println("connected.");

    mqttClient.subscribe(
        PUMP_COMMAND_TOPIC);
  }
  else
  {
    Serial.print(
        "failed, MQTT state = ");

    Serial.println(
        mqttClient.state());
  }
}

// =====================================================
// SINRIC SENSOR UPDATES
// =====================================================

void publishSinricSensors(unsigned long now)
{
  // Wait until at least one sensor reading exists.
  if (
      latestSoilMoisture < 0 &&
      isnan(latestTemperature))
  {
    return;
  }

  if (
      now - lastSinricSensorAt <
      SINRIC_SENSOR_INTERVAL_MS)
  {
    return;
  }

  lastSinricSensorAt = now;

  // Send soil moisture as brightness percentage.
  if (latestSoilMoisture >= 0)
  {
    SinricProDimSwitch &soil =
        SinricPro[SINRIC_SOIL_DEVICE_ID];

    soil.sendPowerStateEvent(true);

    soil.sendPowerLevelEvent(
        latestSoilMoisture);
  }

  // Send DHT22 temperature and humidity.
  if (
      !isnan(latestTemperature) &&
      !isnan(latestHumidity))
  {
    SinricProTemperaturesensor &climate =
        SinricPro[SINRIC_CLIMATE_DEVICE_ID];

    climate.sendTemperatureEvent(
        latestTemperature,
        latestHumidity);
  }
}

// =====================================================
// READ AND PUBLISH ALL SENSORS
// =====================================================

void readAndPublishSensors()
{
  // -------------------------------------------------
  // SOIL MOISTURE
  // -------------------------------------------------

  int soilRaw =
      analogRead(SOIL_PIN);

  int soilMoisture =
      percentageFromRaw(
          soilRaw,
          SOIL_DRY_VALUE,
          SOIL_WET_VALUE);

  // -------------------------------------------------
  // WATER LEVEL
  // -------------------------------------------------

  int waterRaw =
      analogRead(WATER_LEVEL_PIN);

  int waterLevel =
      percentageFromRaw(
          waterRaw,
          WATER_EMPTY_VALUE,
          WATER_FULL_VALUE);

  // -------------------------------------------------
  // RAIN SENSOR
  // -------------------------------------------------

  bool raining =
      digitalRead(RAIN_PIN) == LOW;

  // -------------------------------------------------
  // DHT22
  // -------------------------------------------------

  float temperature =
      dht.readTemperature();

  float humidity =
      dht.readHumidity();

  // -------------------------------------------------
  // FLOW SENSOR
  // -------------------------------------------------

  noInterrupts();

  uint32_t pulses = flowPulses;
  flowPulses = 0;

  interrupts();

  // Store latest values for Sinric Pro.
  latestSoilMoisture =
      soilMoisture;

  if (
      !isnan(temperature) &&
      !isnan(humidity))
  {
    latestTemperature =
        temperature;

    latestHumidity =
        humidity;
  }

  // -------------------------------------------------
  // SERIAL MONITOR
  // -------------------------------------------------

  Serial.print("Soil Raw      : ");
  Serial.println(soilRaw);

  Serial.print("Soil Moisture : ");
  Serial.print(soilMoisture);
  Serial.println(" %");

  Serial.print("Water Raw     : ");
  Serial.println(waterRaw);

  Serial.print("Water Level   : ");
  Serial.print(waterLevel);
  Serial.println(" %");

  Serial.print("Rain Sensor   : ");
  Serial.println(
      raining
          ? "WET / RAIN"
          : "DRY / NO RAIN");

  if (
      isnan(temperature) ||
      isnan(humidity))
  {
    Serial.println(
        "DHT22          : ERROR - CHECK WIRING");
  }
  else
  {
    Serial.print("Temperature   : ");
    Serial.print(temperature, 1);
    Serial.println(" C");

    Serial.print("Humidity      : ");
    Serial.print(humidity, 1);
    Serial.println(" %");
  }

  Serial.print("Flow Pulses   : ");
  Serial.println(pulses);

  Serial.print("Water Flow    : ");
  Serial.println(
      pulses > 0
          ? "DETECTED"
          : "NO FLOW");

  Serial.print("Pump          : ");
  Serial.println(
      pumpOn
          ? "ON"
          : "OFF");

  // -------------------------------------------------
  // MQTT JSON
  // -------------------------------------------------

  if (!mqttClient.connected())
  {
    Serial.println(
        "MQTT           : OFFLINE - PACKET SKIPPED");

    Serial.println(
        "----------------------------------------");

    return;
  }

  char temperatureJson[16];
  char humidityJson[16];

  if (
      isnan(temperature) ||
      isnan(humidity))
  {
    strcpy(
        temperatureJson,
        "null");

    strcpy(
        humidityJson,
        "null");
  }
  else
  {
    snprintf(
        temperatureJson,
        sizeof(temperatureJson),
        "%.1f",
        temperature);

    snprintf(
        humidityJson,
        sizeof(humidityJson),
        "%.1f",
        humidity);
  }

  char payload[384];

  int payloadLength =
      snprintf(
          payload,
          sizeof(payload),
          "{"
          "\"soilRaw\":%d,"
          "\"soilMoisture\":%d,"
          "\"waterLevelRaw\":%d,"
          "\"waterLevel\":%d,"
          "\"raining\":%s,"
          "\"temperature\":%s,"
          "\"humidity\":%s,"
          "\"flowPulses\":%lu,"
          "\"intervalMs\":%lu,"
          "\"pumpOn\":%s"
          "}",
          soilRaw,
          soilMoisture,
          waterRaw,
          waterLevel,
          raining ? "true" : "false",
          temperatureJson,
          humidityJson,
          static_cast<unsigned long>(pulses),
          SAMPLE_INTERVAL_MS,
          pumpOn ? "true" : "false");

  if (
      payloadLength < 0 ||
      payloadLength >= sizeof(payload))
  {
    Serial.println(
        "MQTT payload buffer is too small.");

    return;
  }

  bool published =
      mqttClient.publish(
          TELEMETRY_TOPIC,
          payload,
          true);

  Serial.print(
      published
          ? "MQTT Published : "
          : "MQTT Failed    : ");

  Serial.println(payload);

  Serial.println(
      "----------------------------------------");
}

// =====================================================
// SINRIC PRO SETUP
// =====================================================

void setupSinricPro()
{
  // Pump switch.
  SinricProSwitch &pump =
      SinricPro[SINRIC_PUMP_DEVICE_ID];

  pump.onPowerState(
      onSinricPumpPower);

  // Soil moisture dimmable-switch workaround.
  SinricProDimSwitch &soil =
      SinricPro[SINRIC_SOIL_DEVICE_ID];

  soil.onPowerState(
      onSoilPower);

  soil.onPowerLevel(
      onSoilPowerLevel);

  // Register climate sensor.
  SinricProTemperaturesensor &climate =
      SinricPro[SINRIC_CLIMATE_DEVICE_ID];

  SinricPro.onConnected([]()
  {
    Serial.println(
        "Sinric Pro connected.");

    SinricProSwitch &pump =
        SinricPro[SINRIC_PUMP_DEVICE_ID];

    pump.sendPowerStateEvent(
        pumpOn);

    // Force sensor synchronization after connecting.
    lastSinricSensorAt =
        millis() -
        SINRIC_SENSOR_INTERVAL_MS;
  });

  SinricPro.onDisconnected([]()
  {
    Serial.println(
        "Sinric Pro disconnected.");
  });

  SinricPro.begin(
      SINRIC_APP_KEY,
      SINRIC_APP_SECRET);
}

// =====================================================
// SETUP
// =====================================================

void setup()
{
  Serial.begin(115200);

  delay(2000);

  Serial.println();
  Serial.println(
      "========================================");
  Serial.println(
      "       AQUACROP SMART FARM SYSTEM");
  Serial.println(
      "              ESP32-S3");
  Serial.println(
      "========================================");

  // Start DHT22.
  dht.begin();

  // ESP32-S3 ADC resolution.
  analogReadResolution(12);

  // Team lead sensor pins.
  pinMode(SOIL_PIN, INPUT);
  pinMode(WATER_LEVEL_PIN, INPUT);
  pinMode(RAIN_PIN, INPUT);

  // Flow sensor.
  pinMode(
      FLOW_PIN,
      INPUT_PULLUP);

  attachInterrupt(
      digitalPinToInterrupt(FLOW_PIN),
      flowPulse,
      RISING);

  // Pump relay.
  pinMode(
      PUMP_RELAY_PIN,
      OUTPUT);

  // Always start safely with the pump off.
  digitalWrite(
      PUMP_RELAY_PIN,
      PUMP_OFF);

  // Physical pump button.
  pinMode(
      PUMP_BUTTON_PIN,
      INPUT_PULLUP);

  // Wi-Fi.
  WiFi.mode(WIFI_STA);

  // Secure HiveMQ connection.
  secureClient.setCACert(
      HIVE_MQ_ROOT_CA);

  mqttClient.setServer(
      MQTT_HOST,
      MQTT_PORT);

  mqttClient.setCallback(
      onMqttMessage);

  mqttClient.setBufferSize(512);
  mqttClient.setKeepAlive(30);

  // Sinric Pro.
  setupSinricPro();

  // Allow immediate connection attempts.
  lastWiFiAttemptAt =
      millis() -
      WIFI_RECONNECT_INTERVAL_MS;

  lastMqttAttemptAt =
      millis() -
      MQTT_RECONNECT_INTERVAL_MS;

  lastSinricSensorAt =
      millis() -
      SINRIC_SENSOR_INTERVAL_MS;

  maintainWiFi();

  Serial.println(
      "Sensors and services initialized.");
}

// =====================================================
// LOOP
// =====================================================

void loop()
{
  maintainWiFi();

  connectMqtt();
  mqttClient.loop();

  SinricPro.handle();

  unsigned long now =
      millis();

  // Handle physical pump button.
  handlePumpButton(now);

  // Local safety cutoff.
  if (
      pumpOn &&
      now - pumpStartedAt >=
          PUMP_MAX_RUNTIME_MS)
  {
    Serial.println(
        "Pump safety timeout reached.");

    setPump(false);
  }

  // Read and publish sensors every 2.5 seconds.
  if (
      now - lastSampleAt >=
      SAMPLE_INTERVAL_MS)
  {
    lastSampleAt = now;

    readAndPublishSensors();
  }

  // Update Sinric sensor devices once per minute.
  publishSinricSensors(now);

  delay(5);
}
