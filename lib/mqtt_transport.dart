import 'package:mqtt_client/mqtt_client.dart';

import 'mqtt_transport_stub.dart'
    if (dart.library.io) 'mqtt_transport_io.dart'
    if (dart.library.js_interop) 'mqtt_transport_web.dart'
    as platform;

MqttClient createMqttClient(String host, String clientId) =>
    platform.createMqttClient(host, clientId);
