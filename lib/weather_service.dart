import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

class LocalWeather {
  const LocalWeather({
    required this.location,
    required this.region,
    required this.latitude,
    required this.longitude,
    required this.temperature,
    required this.apparentTemperature,
    required this.humidity,
    required this.windSpeed,
    required this.precipitation,
    required this.rainProbability,
    required this.weatherCode,
    required this.updatedAt,
  });

  final String location;
  final String region;
  final double latitude;
  final double longitude;
  final double temperature;
  final double apparentTemperature;
  final int humidity;
  final double windSpeed;
  final double precipitation;
  final int rainProbability;
  final int weatherCode;
  final DateTime updatedAt;

  String get condition => switch (weatherCode) {
    0 => 'Clear sky',
    1 || 2 => 'Partly cloudy',
    3 => 'Overcast',
    45 || 48 => 'Foggy',
    >= 51 && <= 57 => 'Drizzle',
    >= 61 && <= 67 => 'Rain',
    >= 71 && <= 77 => 'Snow',
    >= 80 && <= 82 => 'Rain showers',
    >= 85 && <= 86 => 'Snow showers',
    >= 95 => 'Thunderstorm',
    _ => 'Current weather',
  };
}

class WeatherLocationException implements Exception {
  const WeatherLocationException(this.message);
  final String message;

  @override
  String toString() => message;
}

class WeatherLocationService {
  Future<LocalWeather> load({http.Client? client}) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const WeatherLocationException(
        'Location services are off. Enable them and try again.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw const WeatherLocationException(
        'Location permission is required for local weather.',
      );
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 15),
      ),
    );

    final ownsClient = client == null;
    final httpClient = client ?? http.Client();
    try {
      final latitude = position.latitude;
      final longitude = position.longitude;
      final responses = await Future.wait([
        httpClient.get(
          Uri.https('api.open-meteo.com', '/v1/forecast', {
            'latitude': '$latitude',
            'longitude': '$longitude',
            'current':
                'temperature_2m,relative_humidity_2m,apparent_temperature,'
                'precipitation,weather_code,wind_speed_10m',
            'hourly': 'precipitation_probability',
            'forecast_hours': '24',
            'timezone': 'auto',
          }),
        ),
        httpClient.get(
          Uri.https('api.bigdatacloud.net', '/data/reverse-geocode-client', {
            'latitude': '$latitude',
            'longitude': '$longitude',
            'localityLanguage': 'en',
          }),
        ),
      ]);

      if (responses.any((response) => response.statusCode != 200)) {
        throw const WeatherLocationException(
          'Weather service is temporarily unavailable.',
        );
      }

      return parseLocalWeather(
        jsonDecode(responses[0].body) as Map<String, dynamic>,
        jsonDecode(responses[1].body) as Map<String, dynamic>,
        latitude,
        longitude,
      );
    } on WeatherLocationException {
      rethrow;
    } on Object {
      throw const WeatherLocationException(
        'Could not load local weather. Check your connection and retry.',
      );
    } finally {
      if (ownsClient) httpClient.close();
    }
  }
}

LocalWeather parseLocalWeather(
  Map<String, dynamic> weatherJson,
  Map<String, dynamic> placeJson,
  double latitude,
  double longitude,
) {
  final current = weatherJson['current'];
  final hourly = weatherJson['hourly'];
  if (current is! Map<String, dynamic> || hourly is! Map<String, dynamic>) {
    throw const WeatherLocationException('Weather response was incomplete.');
  }

  var rainProbability = 0;
  final probabilities = hourly['precipitation_probability'];
  if (probabilities is List) {
    for (final probability in probabilities.whereType<num>()) {
      if (probability > rainProbability) rainProbability = probability.round();
    }
  }

  final locality = _text(placeJson['locality']);
  final city = _text(placeJson['city']);
  final region = _text(placeJson['principalSubdivision']);
  final location = locality.isNotEmpty
      ? locality
      : city.isNotEmpty
      ? city
      : '${latitude.toStringAsFixed(3)}, ${longitude.toStringAsFixed(3)}';

  return LocalWeather(
    location: location,
    region: region,
    latitude: latitude,
    longitude: longitude,
    temperature: _number(current['temperature_2m']),
    apparentTemperature: _number(current['apparent_temperature']),
    humidity: _number(current['relative_humidity_2m']).round(),
    windSpeed: _number(current['wind_speed_10m']),
    precipitation: _number(current['precipitation']),
    rainProbability: rainProbability.clamp(0, 100),
    weatherCode: _number(current['weather_code']).round(),
    updatedAt: DateTime.now(),
  );
}

double _number(Object? value) {
  if (value is num && value.isFinite) return value.toDouble();
  throw const WeatherLocationException('Weather response was incomplete.');
}

String _text(Object? value) => value is String ? value.trim() : '';
