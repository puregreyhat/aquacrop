# ESP32-S3 → AquaCrop MQTT contract

The ESP32 sketch publishes one JSON packet to MQTT after each 2.5-second sensor read and accepts pump commands from both MQTT and Sinric Pro.

A ready-to-upload Arduino sketch is included at `esp32/SmartFarmMqtt/SmartFarmMqtt.ino`.

## ESP32 setup

1. Install the Arduino libraries **PubSubClient** by Nick O'Leary, **DHT sensor library** by Adafruit, and **SinricPro**.
2. The local `esp32/SmartFarmMqtt/secrets.h` contains the prototype's Wi-Fi, HiveMQ, Sinric Pro app credentials, and all three device IDs. It is ignored by Git.
3. Use `secrets.example.h` as the safe template when copying the project to another computer.
4. Select your ESP32-S3 board and upload `SmartFarmMqtt.ino`.
5. Open Serial Monitor at `115200` baud and look for `Published:` messages.

The password is deliberately excluded from the repository. Because credentials were shared in chat, rotate the HiveMQ password before demonstrating or publishing the project.

## Broker transport

- Native Flutter apps: secure MQTT/TLS on port `8883`
- Flutter Web: secure MQTT WebSocket on port `8884`, path `/mqtt`
- Telemetry topic: `smartfarm/esp32-s3/telemetry`
- Pump command topic: `smartfarm/esp32-s3/pump/set` (`ON` or `OFF`)

The shared pump relay uses GPIO 16 and is configured as active-low. A momentary
push button between GPIO 17 and GND toggles it locally. Change `PUMP_RELAY_PIN`,
`PUMP_BUTTON_PIN`, `PUMP_ON`, or `PUMP_OFF` if your wiring differs.
Both Sinric Pro and AquaCrop control the same relay state. A local 60-second
safety timeout turns the pump off even if the internet connection fails.

## Telemetry packet

Publish this JSON shape after reading the sensors:

```json
{
  "soilRaw": 2580,
  "soilMoisture": 48,
  "waterLevelRaw": 3276,
  "waterLevel": 80,
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
| calibrated soil percentage | `soilMoisture` |
| `analogRead(WATER_LEVEL_PIN)` | `waterLevelRaw` |
| calibrated tank percentage | `waterLevel` |
| `digitalRead(RAIN_PIN) == LOW` | `raining` |
| `dht.readTemperature()` | `temperature` |
| `dht.readHumidity()` | `humidity` |
| copied/reset `flowPulses` | `flowPulses` |
| loop delay | `intervalMs` |
| relay state | `pumpOn` |

The team-provided provisional calibration is `2050 = dry`, `1000 = wet`,
`0 = empty tank`, and `3000 = full tank`. Replace these constants after taking
real dry/wet and empty/full readings. The app intentionally shows flow pulses
rather than invented litres until the flow sensor is calibrated.

## Sinric Pro devices

All three configured devices are enabled:

- `SINRIC_PUMP_DEVICE_ID`: Switch controlling the shared pump relay
- `SINRIC_SOIL_DEVICE_ID`: Dimmable Switch showing soil percentage as brightness
- `SINRIC_CLIMATE_DEVICE_ID`: Temperature Sensor showing DHT22 temperature and humidity

The firmware sends sensor events once per minute to respect Sinric Pro event
limits. Pump changes from Sinric Pro, MQTT, or the physical button are all
synchronized to the same relay state.

## Start the Flutter client

Flutter reads the local MQTT credentials from the ignored
`lib/local_secrets.dart`, so no command-line credentials are required:

```sh
flutter run -d chrome
```

A compiled web app exposes embedded credentials to browser users, so direct
broker login is suitable only for this local prototype. Use a backend or
short-lived scoped credentials before public deployment.
