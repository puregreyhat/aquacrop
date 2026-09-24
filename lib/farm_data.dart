import 'dart:async';

class ZoneData {
  const ZoneData({
    required this.name,
    required this.crop,
    required this.moisture,
    required this.target,
    required this.litresNeeded,
    required this.colorValue,
    this.live = true,
  });

  final String name;
  final String crop;
  final int moisture;
  final int target;
  final double litresNeeded;
  final int colorValue;
  final bool live;

  ZoneData copyWith({int? moisture, bool? live}) => ZoneData(
    name: name,
    crop: crop,
    moisture: moisture ?? this.moisture,
    target: target,
    litresNeeded: litresNeeded,
    colorValue: colorValue,
    live: live ?? this.live,
  );
}

class FarmSnapshot {
  const FarmSnapshot({
    required this.zones,
    required this.temperature,
    required this.humidity,
    required this.rainProbability,
    required this.tankLevel,
    required this.flowRate,
    required this.deliveredToday,
    required this.dailyBudget,
    required this.pumpOn,
    this.soilRaw = 0,
    this.waterLevelRaw = 0,
    this.flowPulses = 0,
    this.sampleIntervalMs = 2500,
    this.raining = false,
    this.connected = false,
    this.pumpControlAvailable = true,
    this.lastUpdated,
  });

  final List<ZoneData> zones;
  final double temperature;
  final double humidity;
  final int rainProbability;
  final int tankLevel;
  final double flowRate;
  final double deliveredToday;
  final double dailyBudget;
  final bool pumpOn;
  final int soilRaw;
  final int waterLevelRaw;
  final int flowPulses;
  final int sampleIntervalMs;
  final bool raining;
  final bool connected;
  final bool pumpControlAvailable;
  final DateTime? lastUpdated;

  FarmSnapshot copyWith({
    List<ZoneData>? zones,
    double? temperature,
    double? humidity,
    int? tankLevel,
    double? flowRate,
    bool? pumpOn,
    int? soilRaw,
    int? waterLevelRaw,
    int? flowPulses,
    int? sampleIntervalMs,
    bool? raining,
    bool? connected,
    bool? pumpControlAvailable,
    DateTime? lastUpdated,
  }) => FarmSnapshot(
    zones: zones ?? this.zones,
    temperature: temperature ?? this.temperature,
    humidity: humidity ?? this.humidity,
    rainProbability: rainProbability,
    tankLevel: tankLevel ?? this.tankLevel,
    flowRate: flowRate ?? this.flowRate,
    deliveredToday: deliveredToday,
    dailyBudget: dailyBudget,
    pumpOn: pumpOn ?? this.pumpOn,
    soilRaw: soilRaw ?? this.soilRaw,
    waterLevelRaw: waterLevelRaw ?? this.waterLevelRaw,
    flowPulses: flowPulses ?? this.flowPulses,
    sampleIntervalMs: sampleIntervalMs ?? this.sampleIntervalMs,
    raining: raining ?? this.raining,
    connected: connected ?? this.connected,
    pumpControlAvailable: pumpControlAvailable ?? this.pumpControlAvailable,
    lastUpdated: lastUpdated ?? this.lastUpdated,
  );
}

abstract interface class FarmService {
  Stream<FarmSnapshot> get updates;
  Future<FarmSnapshot> read();
  Future<FarmSnapshot> setPump(bool running);
  Future<void> close();
}

class DemoFarmService implements FarmService {
  FarmSnapshot _snapshot = FarmSnapshot(
    zones: const [
      ZoneData(
        name: 'Zone 1',
        crop: 'Tomato',
        moisture: 32,
        target: 45,
        litresNeeded: 0.8,
        colorValue: 0xFF15966A,
      ),
      ZoneData(
        name: 'Zone 2',
        crop: 'Chilli',
        moisture: 41,
        target: 48,
        litresNeeded: 0.5,
        colorValue: 0xFFF59E0B,
        live: false,
      ),
    ],
    temperature: 28,
    humidity: 52,
    rainProbability: 78,
    tankLevel: 80,
    flowRate: 0,
    deliveredToday: 3.2,
    dailyBudget: 8,
    pumpOn: false,
    soilRaw: 2580,
    waterLevelRaw: 3276,
    flowPulses: 0,
    lastUpdated: DateTime.now(),
  );

  @override
  Stream<FarmSnapshot> get updates => const Stream.empty();

  @override
  Future<FarmSnapshot> read() async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    return _snapshot;
  }

  @override
  Future<FarmSnapshot> setPump(bool running) async {
    await Future<void>.delayed(const Duration(milliseconds: 180));
    _snapshot = _snapshot.copyWith(
      pumpOn: running,
      flowRate: running ? 1.4 : 0,
      flowPulses: running ? 17 : 0,
      lastUpdated: DateTime.now(),
    );
    return _snapshot;
  }

  @override
  Future<void> close() async {}
}
