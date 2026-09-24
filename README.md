# AquaCrop

A responsive Flutter prototype for a two-zone smart irrigation system with one shared water pump. It runs on Web, Android, iOS, macOS, and Windows from one Dart codebase.

## Run

```sh
flutter pub get
flutter run -d chrome
```

Use any installed Flutter device instead of `chrome` for desktop or mobile.

## Verify

```sh
flutter analyze
flutter test
flutter build web
```

## Current prototype

- A calm Home screen for daily use and a detailed Dashboard for technical data
- Two displayed crop zones; Zone 1 uses the physical soil probe and Zone 2 is clearly marked as demo-only until a second probe is added
- One shared pump with working simulated start/stop control
- Automatic/manual modes, weather forecast, charts, planning, alerts, crop profiles, and settings
- Responsive sidebar navigation on desktop and bottom navigation on mobile
- DHT22, raw soil ADC, raw water-level ADC, rain state, and 2.5-second flow-pulse readings matching the supplied ESP32-S3 sketch
- Optional HiveMQ live mode with native TLS and browser WebSocket transports

## Connect the hardware later

`lib/farm_data.dart` contains the small `FarmService` boundary. With no credentials the UI uses `DemoFarmService`; with `MQTT_USERNAME` and `MQTT_PASSWORD` Dart defines it uses `MqttFarmService`. See [MQTT_SETUP.md](MQTT_SETUP.md) for the topics and payload.

The supplied ESP32 firmware is a separate Arduino/C++ project. It currently reads one soil probe, a DHT22, rain state, water level, and flow pulses but only prints to Serial. It must publish the documented telemetry JSON before the app can receive live data. It also needs relay handling before the website can safely control the pump.

## Telegram alerts

The Dart Telegram service subscribes to the same HiveMQ telemetry and keeps the bot token out of Flutter web builds. It supports `/start`, `/status`, `/alerts_on`, `/alerts_off`, `/settings`, and `/help`, and automatically registers those commands with Telegram.

Run it from the project directory after setting `TELEGRAM_BOT_TOKEN`, `MQTT_USERNAME`, and `MQTT_PASSWORD` in your terminal environment:

```sh
dart run bin/telegram_bot.dart
```

Then open a private chat with the bot and send `/start`. The first private chat is saved as the bot owner in the ignored `.telegram_bot_state.json` file. The service alerts once when soil moisture falls below 35%, the tank falls below 20%, temperature reaches 38°C, or rain is detected. It will not repeat an alert until that condition clears and occurs again.

Do not put the Telegram token in Dart source, Flutter build arguments, or ESP32 firmware. Revoke any token that has been pasted into chat and run the service with the replacement token.
