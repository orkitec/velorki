import 'package:dio/dio.dart';

/// The User-Agent every HTTP client of the app sends. Public services such
/// as Photon reject Dart's default `Dart/x (dart:io)` agent, and the OSM
/// usage policies ask for a distinct, identifiable one.
const String velorkiUserAgent =
    'Velorki (+https://velorki.app; +https://github.com/orkitec/velorki)';

/// [BaseOptions] carrying the app's User-Agent on top of [base].
BaseOptions velorkiBaseOptions([BaseOptions? base]) {
  final options = base ?? BaseOptions();
  options.headers = <String, dynamic>{
    ...options.headers,
    'User-Agent': velorkiUserAgent,
  };
  return options;
}

/// A [Dio] with the app's User-Agent set.
Dio velorkiDio([BaseOptions? base]) => Dio(velorkiBaseOptions(base));
