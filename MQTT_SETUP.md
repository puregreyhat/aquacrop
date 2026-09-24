# ESP32-S3 → AquaCrop MQTT contract

The ESP32 sketch publishes one JSON packet to MQTT after each 2.5-second sensor read and accepts pump commands from both MQTT and Sinric Pro.

A ready-to-upload Arduino sketch is included at `esp32/SmartFarmMqtt/SmartFarmMqtt.ino`.

## ESP32 setup

1. Install the Arduino libraries **PubSubClient** by Nick O'Leary, **DHT sensor library** by Adafruit, and **SinricPro**.
2. Copy `esp32/SmartFarmMqtt/secrets.example.h` to `secrets.h` in the same folder.
3. Put your Wi-Fi, HiveMQ, and Sinric Pro credentials in `secrets.h`. Copy the three Sinric values from the root `key.txt`; never commit either credentials file.
4. Select your ESP32-S3 board and upload `SmartFarmMqtt.ino`.
5. Open Serial Monitor at `115200` baud and look for `Published:` messages.

The password is deliberately excluded from the repository. Because credentials were shared in chat, rotate the HiveMQ password before demonstrating or publishing the project.

## Broker transport

- Native Flutter apps: secure MQTT/TLS on port `8883`
- Flutter Web: secure MQTT WebSocket on port `8884`, path `/mqtt`
- Telemetry topic: `smartfarm/esp32-s3/telemetry`
- Pump command topic: `smartfarm/esp32-s3/pump/set` (`ON` or `OFF`)

The shared pump relay uses GPIO 16 and is configured as active-low. Change
`PUMP_RELAY_PIN`, `PUMP_ON`, or `PUMP_OFF` in the sketch if your wiring differs.
Both Sinric Pro and AquaCrop control the same relay state. A local 60-second
safety timeout turns the pump off even if the internet connection fails.

## Telemetry packet

Publish this JSON shape after reading the sensors:

```json
{
  "soilRaw": 2580,
  "waterLevelRaw": 3276,
  "raining": false,
  "temperature": 28.4,
  "humidity": 52.1,
  "flowPulses": 17,
  "intervalMs": 2500,
  "pumpOn": false
}
```

Field mapping from the supplied sketch:

| ESP value | JSON field |
|---|---|
| `analogRead(SOIL_PIN)` | `soilRaw` |
| `analogRead(WATER_LEVEL_PIN)` | `waterLevelRaw` |
| `digitalRead(RAIN_PIN) == LOW` | `raining` |
| `dht.readTemperature()` | `temperature` |
| `dht.readHumidity()` | `humidity` |
| copied/reset `flowPulses` | `flowPulses` |
| loop delay | `intervalMs` |
| relay state | `pumpOn` |

The soil percentage currently uses provisional calibration values of `3200 = dry` and `1300 = wet`. Replace them after recording the sensor in fully dry and fully wet soil. The app intentionally shows flow pulses rather than invented litres until the flow sensor is calibrated.

## Start the Flutter client

Credentials are intentionally not stored in source control. Pass them at build or run time:

```sh
flutter run -d chrome \
  --dart-define=MQTT_USERNAME=your_username \
  --dart-define=MQTT_PASSWORD=your_password
```

Without both values, AquaCrop stays in safe demo mode. A compiled web app exposes embedded credentials to browser users, so direct broker login is suitable only for this local prototype. Use a backend or short-lived scoped credentials before public deployment.
