import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_agri/farm_data.dart';
import 'package:smart_agri/main.dart';
import 'package:smart_agri/mqtt_farm_service.dart';

void main() {
  test('telemetry maps the supplied ESP32 fields', () async {
    final initial = await DemoFarmService().read();
    final result = applyTelemetry(initial, {
      'soilRaw': 2250,
      'waterLevelRaw': 2048,
      'raining': true,
      'temperature': 29.4,
      'humidity': 61.2,
      'flowPulses': 17,
      'intervalMs': 2500,
      'pumpOn': true,
    });

    expect(result.zones.first.moisture, 50);
    expect(result.zones.last.live, isFalse);
    expect(result.tankLevel, 50);
    expect(result.raining, isTrue);
    expect(result.flowPulses, 17);
    expect(result.temperature, 29.4);
    expect(result.pumpOn, isTrue);
    expect(result.connected, isTrue);
    expect(result.pumpControlAvailable, isTrue);
  });

  testWidgets('home shows two zones and toggles shared pump', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const SmartAgriApp());
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

    await tester.pumpWidget(const SmartAgriApp());
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

  testWidgets('desktop navigation opens every product screen', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const SmartAgriApp());
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
