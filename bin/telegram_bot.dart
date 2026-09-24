import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:smart_agri/farm_data.dart';
import 'package:smart_agri/mqtt_farm_service.dart';

const _mqttHost = '8255d88bbacc45fd89c2580a5887a138.s1.eu.hivemq.cloud';
const _soilAlertPercent = 35;
const _tankAlertPercent = 20;
const _heatAlertCelsius = 38.0;

Future<void> main(List<String> arguments) async {
  if (arguments.contains('--self-test')) {
    await _selfTest();
    return;
  }

  final environment = Platform.environment;
  final token = _required(environment, 'TELEGRAM_BOT_TOKEN');
  final mqttUsername = _required(environment, 'MQTT_USERNAME');
  final mqttPassword = _required(environment, 'MQTT_PASSWORD');
  final stateFile = File(
    environment['TELEGRAM_STATE_FILE'] ?? '.telegram_bot_state.json',
  );

  final bridge = TelegramFarmBridge(
    telegram: TelegramApi(token),
    farm: MqttFarmService(
      host: _mqttHost,
      username: mqttUsername,
      password: mqttPassword,
    ),
    stateFile: stateFile,
  );

  stdout.writeln('AquaCrop Telegram service starting...');
  await bridge.run();
}

String _required(Map<String, String> environment, String name) {
  final value = environment[name]?.trim() ?? '';
  if (value.isEmpty) {
    stderr.writeln('Missing required environment variable: $name');
    exitCode = 64;
    throw StateError(name);
  }
  return value;
}

class TelegramFarmBridge {
  TelegramFarmBridge({
    required this.telegram,
    required this.farm,
    required this.stateFile,
  });

  final TelegramApi telegram;
  final MqttFarmService farm;
  final File stateFile;
  final AlertEngine alerts = AlertEngine();

  BotState state = const BotState();
  FarmSnapshot? snapshot;
  StreamSubscription<FarmSnapshot>? farmSubscription;
  int updateOffset = 0;

  Future<void> run() async {
    state = await BotState.load(stateFile);
    await telegram.setCommands();
    snapshot = await farm.read();
    farmSubscription = farm.updates.listen(_onTelemetry);

    stdout.writeln('Telegram commands ready. Send /start to the bot.');
    while (true) {
      try {
        final updates = await telegram.getUpdates(updateOffset);
        for (final update in updates) {
          final updateId = update['update_id'];
          if (updateId is int) updateOffset = updateId + 1;
          await _handleUpdate(update);
        }
      } on TelegramApiException catch (error) {
        stderr.writeln('Telegram API error: ${error.message}');
        await Future<void>.delayed(const Duration(seconds: 3));
      } on Object {
        stderr.writeln('Telegram connection failed; retrying.');
        await Future<void>.delayed(const Duration(seconds: 3));
      }
    }
  }

  Future<void> _handleUpdate(Map<String, dynamic> update) async {
    final message = update['message'];
    if (message is! Map<String, dynamic>) return;
    final chat = message['chat'];
    if (chat is! Map<String, dynamic>) return;
    final chatId = chat['id'];
    final text = message['text'];
    if (chatId is! int || text is! String) return;

    final command = parseCommand(text);
    if (command == null) return;

    if (command == 'start' && state.ownerChatId == null) {
      if (chat['type'] != 'private') {
        await telegram.sendMessage(
          chatId,
          'Please open a private chat with this bot and send /start there.',
        );
        return;
      }
      state = BotState(ownerChatId: chatId, alertsEnabled: true);
      await state.save(stateFile);
      await telegram.sendMessage(chatId, _welcomeMessage);
      return;
    }

    if (state.ownerChatId == null) {
      await telegram.sendMessage(chatId, 'Send /start to connect this farm.');
      return;
    }
    if (chatId != state.ownerChatId) {
      await telegram.sendMessage(chatId, 'This farm bot is already paired.');
      return;
    }

    switch (command) {
      case 'start':
      case 'help':
        await telegram.sendMessage(chatId, _welcomeMessage);
        break;
      case 'status':
        await telegram.sendMessage(chatId, formatStatus(snapshot));
        break;
      case 'alerts_on':
        state = state.copyWith(alertsEnabled: true);
        alerts.reset();
        await state.save(stateFile);
        await telegram.sendMessage(chatId, '✅ Automatic farm alerts enabled.');
        break;
      case 'alerts_off':
        state = state.copyWith(alertsEnabled: false);
        await state.save(stateFile);
        await telegram.sendMessage(
          chatId,
          '🔕 Automatic farm alerts disabled.',
        );
        break;
      case 'settings':
        await telegram.sendMessage(
          chatId,
          'Alert settings\n'
          'Soil moisture: below $_soilAlertPercent%\n'
          'Water tank: below $_tankAlertPercent%\n'
          'Heat: $_heatAlertCelsius°C or above\n'
          'Rain: alert when detected\n'
          'Alerts: ${state.alertsEnabled ? 'ON' : 'OFF'}',
        );
        break;
      default:
        await telegram.sendMessage(chatId, 'Unknown command. Send /help.');
    }
  }

  void _onTelemetry(FarmSnapshot value) {
    snapshot = value;
    final chatId = state.ownerChatId;
    if (chatId == null || !state.alertsEnabled) return;

    final messages = alerts.evaluate(value);
    if (messages.isEmpty) return;
    unawaited(
      telegram.sendMessage(chatId, messages.join('\n\n')).catchError((
        Object _,
      ) {
        alerts.reset();
        stderr.writeln('Could not send a Telegram alert; will retry.');
      }),
    );
  }
}

String? parseCommand(String text) {
  final firstWord = text.trim().split(RegExp(r'\s+')).first.toLowerCase();
  if (!firstWord.startsWith('/')) return null;
  return firstWord.substring(1).split('@').first;
}

String formatStatus(FarmSnapshot? snapshot) {
  if (snapshot == null || snapshot.lastUpdated == null) {
    return '⏳ Waiting for ESP32 telemetry from MQTT.';
  }

  final zone = snapshot.zones.first;
  return '🌱 AquaCrop live status\n'
      'Soil moisture: ${zone.moisture}% (target ${zone.target}%)\n'
      'Temperature: ${snapshot.temperature.toStringAsFixed(1)}°C\n'
      'Humidity: ${snapshot.humidity.toStringAsFixed(1)}%\n'
      'Water tank: ${snapshot.tankLevel}%\n'
      'Rain sensor: ${snapshot.raining ? 'RAIN' : 'DRY'}\n'
      'Flow pulses: ${snapshot.flowPulses} / '
      '${snapshot.sampleIntervalMs / 1000}s\n'
      'MQTT: ${snapshot.connected ? 'connected' : 'offline'}';
}

class AlertEngine {
  final Set<String> _active = {};

  List<String> evaluate(FarmSnapshot snapshot) {
    final conditions = <String, (bool, String)>{
      'soil': (
        snapshot.zones.first.moisture < _soilAlertPercent,
        '⚠️ Low soil moisture: ${snapshot.zones.first.moisture}%. '
            'Check whether irrigation is needed.',
      ),
      'tank': (
        snapshot.tankLevel < _tankAlertPercent,
        '🚰 Water tank is low: ${snapshot.tankLevel}%.',
      ),
      'heat': (
        snapshot.temperature >= _heatAlertCelsius,
        '🔥 High temperature: ${snapshot.temperature.toStringAsFixed(1)}°C.',
      ),
      'rain': (
        snapshot.raining,
        '🌧️ Rain detected. Keep irrigation off while the tray is wet.',
      ),
    };

    final messages = <String>[];
    for (final MapEntry(key: key, value: condition) in conditions.entries) {
      if (condition.$1 && _active.add(key)) messages.add(condition.$2);
      if (!condition.$1) _active.remove(key);
    }
    return messages;
  }

  void reset() => _active.clear();
}

class BotState {
  const BotState({this.ownerChatId, this.alertsEnabled = true});

  final int? ownerChatId;
  final bool alertsEnabled;

  BotState copyWith({bool? alertsEnabled}) => BotState(
    ownerChatId: ownerChatId,
    alertsEnabled: alertsEnabled ?? this.alertsEnabled,
  );

  static Future<BotState> load(File file) async {
    if (!await file.exists()) return const BotState();
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, dynamic>) return const BotState();
      return BotState(
        ownerChatId: json['ownerChatId'] as int?,
        alertsEnabled: json['alertsEnabled'] != false,
      );
    } on Object {
      return const BotState();
    }
  }

  Future<void> save(File file) => file.writeAsString(
    jsonEncode({'ownerChatId': ownerChatId, 'alertsEnabled': alertsEnabled}),
  );
}

class TelegramApi {
  TelegramApi(this.token);

  final String token;
  final HttpClient _http = HttpClient();

  Future<List<Map<String, dynamic>>> getUpdates(int offset) async {
    final response = await _call('getUpdates', {
      'offset': offset,
      'timeout': 25,
      'allowed_updates': ['message'],
    });
    final result = response['result'];
    if (result is! List) return const [];
    return result.whereType<Map<String, dynamic>>().toList();
  }

  Future<void> sendMessage(int chatId, String text) async {
    await _call('sendMessage', {'chat_id': chatId, 'text': text});
  }

  Future<void> setCommands() async {
    await _call('setMyCommands', {
      'commands': const [
        {'command': 'start', 'description': 'Connect this farm bot'},
        {'command': 'status', 'description': 'Show current sensor readings'},
        {'command': 'alerts_on', 'description': 'Enable automatic alerts'},
        {'command': 'alerts_off', 'description': 'Disable automatic alerts'},
        {'command': 'settings', 'description': 'Show alert thresholds'},
        {'command': 'help', 'description': 'Show available commands'},
      ],
    });
  }

  Future<Map<String, dynamic>> _call(
    String method,
    Map<String, Object> body,
  ) async {
    final request = await _http.postUrl(
      Uri.https('api.telegram.org', '/bot$token/$method'),
    );
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
    final response = await request.close();
    final responseBody = await utf8.decoder.bind(response).join();
    final json = jsonDecode(responseBody);
    if (json is! Map<String, dynamic> || json['ok'] != true) {
      final description = json is Map<String, dynamic>
          ? json['description']?.toString()
          : null;
      throw TelegramApiException(description ?? 'Request failed');
    }
    return json;
  }
}

class TelegramApiException implements Exception {
  const TelegramApiException(this.message);
  final String message;
}

const _welcomeMessage =
    '🌿 AquaCrop bot connected.\n\n'
    '/status — current sensor readings\n'
    '/alerts_on — enable automatic alerts\n'
    '/alerts_off — disable automatic alerts\n'
    '/settings — show alert thresholds\n'
    '/help — show this message';

Future<void> _selfTest() async {
  assert(parseCommand('/STATUS@AquaCropBot now') == 'status');
  assert(parseCommand('hello') == null);

  final base = await DemoFarmService().read();
  final danger = base.copyWith(
    zones: [base.zones.first.copyWith(moisture: 20), base.zones.last],
    tankLevel: 10,
    temperature: 40,
    raining: true,
  );
  final engine = AlertEngine();
  assert(engine.evaluate(danger).length == 4);
  assert(engine.evaluate(danger).isEmpty);
  assert(formatStatus(danger).contains('Soil moisture: 20%'));
  stdout.writeln('Telegram bot self-test passed.');
}
