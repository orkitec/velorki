import 'package:velorki_api/velorki_api.dart' show WeatherForecast;

import 'route_sampling.dart';
import 'route_weather.dart';

/// The weather along the planned route, as the Plan tab shows it.
class RouteWeatherState {
  /// Creates the state.
  const RouteWeatherState({
    required this.departure,
    required this.earliestDeparture,
    required this.window,
    required this.forecast,
    required this.samples,
    required this.cells,
    required this.weather,
    required this.summary,
  });

  /// Evaluates [forecast] for [departure].
  factory RouteWeatherState.evaluated({
    required DateTime departure,
    required DateTime earliestDeparture,
    required WeatherWindow window,
    required WeatherForecast forecast,
    required List<RouteWeatherSample> samples,
    required WeatherCells cells,
  }) {
    final weather = evaluate(forecast, samples, cells.sampleToCell, departure);
    return RouteWeatherState(
      departure: departure,
      earliestDeparture: earliestDeparture,
      window: window,
      forecast: forecast,
      samples: samples,
      cells: cells,
      weather: weather,
      summary: RouteWeatherSummary.of(weather),
    );
  }

  /// When the rider leaves.
  final DateTime departure;

  /// The earliest departure offered: now, rounded up to the quarter hour,
  /// when the forecast was asked for.
  final DateTime earliestDeparture;

  /// The hours [forecast] was asked for.
  final WeatherWindow window;

  /// The relay's answer.
  final WeatherForecast forecast;

  /// Where along the route the weather is looked up.
  final List<RouteWeatherSample> samples;

  /// The cells asked about, and which answers which sample.
  final WeatherCells cells;

  /// [forecast] evaluated for [departure].
  final RouteWeather weather;

  /// [weather] in a few figures.
  final RouteWeatherSummary summary;

  /// How long the ride takes.
  Duration get rideTime =>
      samples.isEmpty ? Duration.zero : samples.last.offset;

  /// Whether a ride leaving at [time] lies inside the hours fetched, so it
  /// can be evaluated without asking again.
  bool covers(DateTime time) {
    final last = window.from.add(Duration(hours: window.hours - 1));
    return !time.isBefore(window.from) && !time.add(rideTime).isAfter(last);
  }

  /// The same forecast for a ride leaving at [time].
  RouteWeatherState withDeparture(DateTime time) => RouteWeatherState.evaluated(
    departure: time,
    earliestDeparture: earliestDeparture,
    window: window,
    forecast: forecast,
    samples: samples,
    cells: cells,
  );
}
