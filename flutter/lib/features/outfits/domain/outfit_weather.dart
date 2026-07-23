final class OutfitLocation {
  const OutfitLocation({
    required this.name,
    required this.latitude,
    required this.longitude,
  });

  factory OutfitLocation.fromJson(Map<String, dynamic> json) => OutfitLocation(
    name: json['name'] as String,
    latitude: (json['latitude'] as num).toDouble(),
    longitude: (json['longitude'] as num).toDouble(),
  );

  final String name;
  final double latitude;
  final double longitude;

  Map<String, dynamic> toJson() => {
    'name': name,
    'latitude': latitude,
    'longitude': longitude,
  };
}

final class OutfitWeatherContext {
  const OutfitWeatherContext({
    required this.locationName,
    required this.localTime,
    required this.timeOfDay,
    required this.condition,
    required this.temperatureC,
    required this.apparentTemperatureC,
    required this.considerations,
    this.precipitationProbability,
    this.precipitationMm,
    this.humidityPercent,
    this.windSpeedKmh,
    this.windGustsKmh,
  });

  factory OutfitWeatherContext.fromJson(Map<String, dynamic> json) =>
      OutfitWeatherContext(
        locationName: json['location_name'] as String,
        localTime: DateTime.parse(json['local_time'] as String),
        timeOfDay: json['time_of_day'] as String,
        condition: json['condition'] as String,
        temperatureC: (json['temperature_c'] as num).toDouble(),
        apparentTemperatureC: (json['apparent_temperature_c'] as num).toDouble(),
        precipitationProbability: (json['precipitation_probability'] as num?)
            ?.toInt(),
        precipitationMm: (json['precipitation_mm'] as num?)?.toDouble(),
        humidityPercent: (json['humidity_percent'] as num?)?.toInt(),
        windSpeedKmh: (json['wind_speed_kmh'] as num?)?.toDouble(),
        windGustsKmh: (json['wind_gusts_kmh'] as num?)?.toDouble(),
        considerations:
            (json['considerations'] as List<dynamic>? ?? const []).cast<String>(),
      );

  final String locationName;
  final DateTime localTime;
  final String timeOfDay;
  final String condition;
  final double temperatureC;
  final double apparentTemperatureC;
  final int? precipitationProbability;
  final double? precipitationMm;
  final int? humidityPercent;
  final double? windSpeedKmh;
  final double? windGustsKmh;
  final List<String> considerations;
}

final class WeatherContextResult {
  const WeatherContextResult({required this.status, this.weatherContext});

  factory WeatherContextResult.fromJson(Map<String, dynamic> json) =>
      WeatherContextResult(
        status: json['status'] as String,
        weatherContext: json['weather_context'] is Map<String, dynamic>
            ? OutfitWeatherContext.fromJson(
                json['weather_context'] as Map<String, dynamic>,
              )
            : null,
      );

  final String status;
  final OutfitWeatherContext? weatherContext;
}


