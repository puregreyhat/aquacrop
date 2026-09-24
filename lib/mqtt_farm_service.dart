import 'dart:async';
import 'dart:convert';

import 'package:mqtt_client/mqtt_client.dart';

import 'farm_data.dart';
import 'mqtt_transport.dart';

FarmSnapshot applyTelemetry(FarmSnapshot current, Map<String, dynamic> json) {
  final soilRaw = _integer(json['soilRaw']);
  final waterRaw = _integer(json['waterLevelRaw']);
  final zones = [...current.zones];
  zones[0] = zones[0].copyWith(
    moisture: (((3200 - soilRaw) / (3200 - 1300)) * 100).round().clamp(0, 100),
    live: true,
  );
  zones[1] = zones[1].copyWith(live: false);
  return current.copyWith(
    zones: zones,
    temperature: _number(json['temperature']),
    humidity: _number(json['humidity']),
    tankLevel: (waterRaw / 4095 * 100).round().clamp(0, 100),
    soilRaw: soilRaw,
    waterLevelRaw: waterRaw,
    flowPulses: _integer(json['flowPulses']),
    sampleIntervalMs: _integer(json['intervalMs'], fallback: 2500),
    raining: json['raining'] == true,
    pumpOn: json['pumpOn'] == true,
    connected: true,
    pumpControlAvailable: true,
    lastUpdated: DateTime.now(),
  );
}

int _integer(Object? value, {int fallback = 0}) =>
    value is num ? value.round() : fallback;

double _number(Object? value) =>
    value is num && value.isFinite ? value.toDouble() : 0;

class MqttFarmService implements FarmService {
  MqttFarmService({
    required this.host,
    required this.username,
    required this.password,
    this.telemetryTopic = 'smartfarm/esp32-s3/telemetry',
    this.commandTopic = 'smartfarm/esp32-s3/pump/set',
  });

  final String host;
  final String username;
  final String password;
  final String telemetryTopic;
  final String commandTopic;

  static const _emptySnapshot = FarmSnapshot(
    zones: [
      ZoneData(
        name: 'Zone 1',
        crop: 'Tomato',
        moisture: 0,
        target: 45,
        litresNeeded: 0.8,
        colorValue: 0xFF15966A,
      ),
      ZoneData(
        name: 'Zone 2',
        crop: 'Chilli',
        moisture: 0,
        target: 48,
        litresNeeded: 0.5,
        colorValue: 0xFFF59E0B,
        live: false,
      ),
    ],
    temperature: 0,
    humidity: 0,
    rainProbability: 0,
    tankLevel: 0,
    flowRate: 0,
    deliveredToday: 0,
    dailyBudget: 8,
    pumpOn: false,
    pumpControlAvailable: false,
  );

  final _updates = StreamController<FarmSnapshot>.broadcast();
  late final MqttClient _client;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage?>>>? _subscription;
  FarmSnapshot _snapshot = _emptySnapshot;

  @override
  Stream<FarmSnapshot> get updates => _updates.stream;

  @override
  Future<FarmSnapshot> read() async {
    final clientId = 'aquacrop-${DateTime.now().millisecondsSinceEpoch}';
    _client = createMqttClient(host, clientId)
      ..keepAlivePeriod = 20
      ..connectTimeoutPeriod = 5000
      ..autoReconnect = true
      ..connectionMessage = MqttConnectMessage()
          .withClientIdentifier(clientId)
          .startClean()
          .withWillQos(MqttQos.atMostOnce);

    try {
      await _client.connect(username, password);
      if (_client.connectionStatus?.state != MqttConnectionState.connected) {
        return _snapshot;
      }
      _snapshot = _snapshot.copyWith(
        connected: true,
        pumpControlAvailable: false,
      );
      _client.subscribe(telemetryTopic, MqttQos.atMostOnce);
      _subscription = _client.updates?.listen(_onMessages);
    } on Object {
      _client.disconnect();
    }
    return _snapshot;
  }

  void _onMessages(List<MqttReceivedMessage<MqttMessage?>> messages) {
    final message = messages.first.payload;
    if (message is! MqttPublishMessage) return;
    final payload = MqttPublishPayload.bytesToStringAsString(
      message.payload.message,
    );
    try {
      final json = jsonDecode(payload) as Map<String, dynamic>;
      _snapshot = applyTelemetry(_snapshot, json);
      _updates.add(_snapshot);
    } on Object {
      // Ignore malformed packets; the next 2.5-second reading can recover.
    }
  }

  @override
  Future<FarmSnapshot> setPump(bool running) async {
    if (!_snapshot.pumpControlAvailable) return _snapshot;
    final payload = MqttClientPayloadBuilder()
      ..addString(running ? 'ON' : 'OFF');
    _client.publishMessage(commandTopic, MqttQos.atLeastOnce, payload.payload!);
    _snapshot = _snapshot.copyWith(pumpOn: running);
    return _snapshot;
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    _client.disconnect();
    await _updates.close();
  }
}
