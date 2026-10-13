import 'package:velorki_api/velorki_api.dart' show WeatherForecast;

import 'route_sampling.dart';
import 'route_weather.dart';
import 'route_weather_digest.dart';

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
    required this.digest,
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
      digest: RouteWeatherDigest.of(weather),
    );
  }

  /// When the rider leaves.
  final DateTime departure;

  /// The earliest departure offered, the one the time control's "Leave now"
  /// stands for: now, to the minute, when the departure was last set
  /// (`departureAfter`). [departure] is this plus the control's offset.
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

  /// [weather] in the few facts the section's first line says.
  final RouteWeatherDigest digest;

  /// How long the ride takes.
  Duration get rideTime =>
      samples.isEmpty ? Duration.zero : samples.last.offset;

  /// Whether a ride leaving at [time] lies inside the hours fetched, so it
  /// can be evaluated without asking again.
  bool covers(DateTime time) {
    final last = window.from.add(Duration(hours: window.hours - 1));
    return !time.isBefore(window.from) && !time.add(rideTime).isAfter(last);
  }

  /// The time control's offset [departure] is at, in minutes.
  int get offsetMinutes => departure.difference(earliestDeparture).inMinutes;

  /// The same forecast for a ride leaving at [time], the time control's
  /// offset counted from [earliest] (unchanged without it).
  RouteWeatherState withDeparture(DateTime time, {DateTime? earliest}) =>
      RouteWeatherState.evaluated(
        departure: time,
        earliestDeparture: earliest ?? earliestDeparture,
        window: window,
        forecast: forecast,
        samples: samples,
        cells: cells,
      );
}
