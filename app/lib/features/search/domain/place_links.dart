/// The links that open a place in another map, or share it.
library;

import 'package:velorki_geo/velorki_geo.dart';

/// [value] in degrees, as the links write it.
String _deg(double value) => value.toStringAsFixed(6);

/// `lat,lon` of [p].
String _ll(LatLng p) => '${_deg(p.lat)},${_deg(p.lon)}';

/// The place at [position] called [name] in Apple Maps.
Uri appleMapsUri(LatLng position, String name) => Uri.parse(
  'https://maps.apple.com/?ll=${_ll(position)}'
  '&q=${Uri.encodeComponent(name.isEmpty ? _ll(position) : name)}',
);

/// The scheme whose presence says Google Maps is installed on iOS.
final Uri googleMapsProbeUri = Uri.parse('comgooglemaps://');

/// The place at [position] in the Google Maps app on iOS.
Uri googleMapsUri(LatLng position) =>
    Uri.parse('comgooglemaps://?q=${_ll(position)}&center=${_ll(position)}');

/// A `geo:` link to the place at [position] called [name], which Android
/// offers to every installed map app.
Uri geoUri(LatLng position, String name) {
  // The label sits in parentheses, so its own ones are escaped.
  final label = Uri.encodeComponent(name)
      .replaceAll('(', '%28')
      .replaceAll(')', '%29');
  final q = name.isEmpty ? _ll(position) : '${_ll(position)}($label)';
  return Uri.parse('geo:${_ll(position)}?q=$q');
}

/// The place on openstreetmap.org: the element itself when [osmType] and
/// [osmId] are known, else a marker at [position].
Uri openStreetMapUri(LatLng position, {String? osmType, int? osmId}) {
  if (osmType != null && osmId != null) {
    return Uri.parse('https://www.openstreetmap.org/$osmType/$osmId');
  }
  final lat = _deg(position.lat);
  final lon = _deg(position.lon);
  return Uri.parse(
    'https://www.openstreetmap.org/?mlat=$lat&mlon=$lon#map=18/$lat/$lon',
  );
}

/// The text a shared place is sent as: its [name] and its [link].
String placeShareText(String name, Uri link) =>
    name.isEmpty ? '$link' : '$name\n$link';
