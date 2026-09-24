import 'package:mqtt_client/mqtt_browser_client.dart';

MqttBrowserClient createMqttClient(String host, String clientId) =>
    MqttBrowserClient.withPort('wss://$host/mqtt', clientId, 8884)
      ..websocketProtocols = const ['mqtt']
      ..setProtocolV311();
