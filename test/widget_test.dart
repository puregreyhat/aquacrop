import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_agri/demo_page.dart';
import 'package:smart_agri/farm_data.dart';
import 'package:smart_agri/main.dart';
import 'package:smart_agri/mqtt_farm_service.dart';
import 'package:smart_agri/weather_service.dart';

final testWeather = LocalWeather(
  location: 'Pune',
  region: 'Maharashtra',
  latitude: 18.5204,
  longitude: 73.8567,
  temperature: 29.5,
  apparentTemperature: 31.2,
  humidity: 61,
  windSpeed: 8.4,
  precipitation: 0,
  rainProbability: 72,
  weatherCode: 2,
  updatedAt: DateTime(2026),
);

Future<LocalWeather> loadTestWeather() async => testWeather;

void main() {
  test('telemetry maps the supplied ESP32 fields', () async {
    final initial = await DemoFarmService().read();
    final result = applyTelemetry(initial, {
      'soilRaw': 1525,
      'soilMoisture': 48,
      'waterLevelRaw': 1500,
      'waterLevel': 49,
      'raining': true,
      'temperature': 29.4,
      'humidity': 61.2,
      'flowPulses': 17,
      'intervalMs': 2500,
      'pumpOn': true,
    });

    expect(result.zones.first.moisture, 48);
    expect(result.zones.last.live, isFalse);
    expect(result.tankLevel, 49);
    expect(result.raining, isTrue);
    expect(result.flowPulses, 17);
    expect(result.temperature, 29.4);
    expect(result.pumpOn, isTrue);
    expect(result.connected, isTrue);
    expect(result.pumpControlAvailable, isTrue);
  });

  test('telemetry keeps the last DHT reading when a read fails', () async {
    final initial = await DemoFarmService().read();
    final result = applyTelemetry(initial, {
      'soilRaw': 1525,
      'waterLevelRaw': 1500,
      'temperature': null,
      'humidity': null,
    });

    expect(result.zones.first.moisture, 50);
    expect(result.tankLevel, 50);
    expect(result.temperature, initial.temperature);
    expect(result.humidity, initial.humidity);
  });

  test('local weather parser uses the highest 24-hour rain chance', () {
    final result = parseLocalWeather(
      {
        'current': {
          'temperature_2m': 29.5,
          'apparent_temperature': 31.2,
          'relative_humidity_2m': 61,
          'wind_speed_10m': 8.4,
          'precipitation': 0,
          'weather_code': 2,
        },
        'hourly': {
          'precipitation_probability': [10, 42, 72, 31],
        },
      },
      {
        'locality': 'Pune',
        'city': 'Pune',
        'principalSubdivision': 'Maharashtra',
      },
      18.5204,
      73.8567,
    );

    expect(result.location, 'Pune');
    expect(result.rainProbability, 72);
    expect(result.condition, 'Partly cloudy');
  });

  testWidgets('home shows two zones and toggles shared pump', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      SmartAgriApp(service: DemoFarmService(), weatherLoader: loadTestWeather),
    );
    await tester.pumpAndSettle();

    expect(find.text('Good morning, Akash'), findsOneWidget);
    expect(find.text('Zone 1 · Tomato'), findsOneWidget);
    expect(find.text('Zone 2 · Chilli'), findsOneWidget);
    expect(find.text('Start irrigation'), findsOneWidget);

    await tester.ensureVisible(find.text('Start irrigation'));
    await tester.tap(find.text('Start irrigation'));
    await tester.pumpAndSettle();
    expect(find.text('Stop irrigation'), findsOneWidget);
    await expectLater(
      find.byType(SmartAgriApp),
      matchesGoldenFile('goldens/home_desktop.png'),
    );
  });

  testWidgets('home adapts to a phone viewport', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      SmartAgriApp(service: DemoFarmService(), weatherLoader: loadTestWeather),
    );
    await tester.pumpAndSettle();

    expect(find.text('Good morning, Akash'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Zones'), findsOneWidget);
    expect(find.text('Irrigation'), findsOneWidget);
    expect(find.text('Analytics'), findsOneWidget);
    await expectLater(
      find.byType(SmartAgriApp),
      matchesGoldenFile('goldens/home_mobile.png'),
    );
  });

  testWidgets('demo explains and animates the two-zone system', (tester) async {
    tester.view.physicalSize = const Size(1180, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: DemoPage()));
    await tester.pump();

    expect(find.text('See every drop\nmake a decision.'), findsOneWidget);
    expect(find.text('Sugarcane'), findsOneWidget);
    expect(find.text('Pearl millet'), findsOneWidget);
    expect(find.text('1.8 L'), findsOneWidget);
    expect(find.text('0.5 L'), findsOneWidget);
    expect(find.text('Run irrigation demo'), findsOneWidget);
    await expectLater(
      find.byType(DemoPage),
      matchesGoldenFile('goldens/demo_desktop.png'),
    );

    await tester.tap(find.text('Run irrigation demo'));
    await tester.pump(const Duration(milliseconds: 4200));
    expect(find.text('Pump ON'), findsOneWidget);
    expect(find.text('Irrigating precisely'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('demo rain mode keeps the pump off', (tester) async {
    tester.view.physicalSize = const Size(1180, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: DemoPage()));
    await tester.tap(find.byType(Switch));
    await tester.pump();

    expect(find.text('Pump OFF'), findsOneWidget);
    expect(
      find.text('Rain is coming. Every drop stays in the tank.'),
      findsOneWidget,
    );
    expect(find.textContaining('keeps the pump OFF'), findsOneWidget);
  });

  testWidgets('/demo opens the system walkthrough', (tester) async {
    await tester.pumpWidget(
      SmartAgriApp(service: DemoFarmService(), weatherLoader: loadTestWeather),
    );
    await tester.pumpAndSettle();

    Navigator.of(tester.element(find.byType(FarmShell))).pushNamed('/demo');
    await tester.pumpAndSettle();

    expect(find.byType(DemoPage), findsOneWidget);
    expect(find.text('Run irrigation demo'), findsOneWidget);
  });

  testWidgets('desktop navigation opens every product screen', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      SmartAgriApp(service: DemoFarmService(), weatherLoader: loadTestWeather),
    );
    await tester.pumpAndSettle();

    for (final label in [
      'Dashboard',
      'Zones',
      'Live data',
      'Irrigation',
      'Weather',
      'Analytics',
      'Crop profiles',
      'Alerts',
      'Settings',
    ]) {
      await tester.tap(find.text(label).first);
      await tester.pumpAndSettle();
      expect(find.text(label), findsWidgets);
    }
  });
}
