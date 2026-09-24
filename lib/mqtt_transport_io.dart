import 'package:mqtt_client/mqtt_server_client.dart';

MqttServerClient createMqttClient(String host, String clientId) =>
    MqttServerClient.withPort(host, clientId, 8883)
      ..secure = true
      ..setProtocolV311();
