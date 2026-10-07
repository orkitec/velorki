/// Reads a place out of what another app hands Velorki: a `geo:` URI, a map
/// link from Google, Apple or OpenStreetMap, Velorki's own
/// `velorki://navigate`, or shared text with coordinates or an address in it.
///
/// Pure Dart and offline: nothing is fetched, so a short link whose place is
/// only known to its server comes back as [LocationLinkSource.shortLink].
library;

import 'package:velorki_geo/velorki_geo.dart';

/// Where a [LocationLink] was read from.
enum LocationLinkSource {
  /// A `geo:` URI (Android's "Open with" for a location).
  geo,

  /// A Google Maps link.
  googleMaps,

  /// An Apple Maps link, `https://maps.apple.com/` or `maps://`.
  appleMaps,

  /// An OpenStreetMap link.
  openStreetMap,

  /// Velorki's own `velorki://navigate`.
  velorki,

  /// Plain text: coordinates in it, or an address or a name.
  text,

  /// A short link (`maps.app.goo.gl`, `goo.gl/maps`, `osm.org/go`) that only
  /// its server can turn into a place: it has to be opened in a browser
  /// first. Carries a [LocationLink.query] only when the text around the link
  /// named the place.
  shortLink,
}

/// A place another app sent: a [position], or a [query] for the search to
/// resolve, or neither when it is an unresolvable [LocationLinkSource.shortLink].
class LocationLink {
  /// Creates a link result.
  const LocationLink({
    required this.source,
    this.position,
    this.query,
    this.name,
    this.shortLink,
  });

  /// The place, when the link carried coordinates.
  final LatLng? position;

  /// What to search for, when it carried an address or a name instead.
  final String? query;

  /// The place's label, when the link had one beside its coordinates.
  final String? name;

  /// What the link was.
  final LocationLinkSource source;

  /// The short link itself, kept for a [LocationLinkSource.shortLink] so it
  /// can be followed when the phone is online (`short_link_resolver.dart`).
  final Uri? shortLink;

  /// Whether the link names a place the app cannot find without a browser.
  bool get isUnresolvable => position == null && query == null;

  @override
  bool operator ==(Object other) =>
      other is LocationLink &&
      other.source == source &&
      other.position == position &&
      other.query == query &&
      other.name == name;

  @override
  int get hashCode => Object.hash(source, position, query, name);

  @override
  String toString() =>
      'LocationLink($source, position: $position, query: $query, name: $name)';
}

/// The host and path of Velorki's own link: `velorki://navigate`.
const String navigateLinkHost = 'navigate';

/// Longest text taken as a search query; anything longer is a message, not
/// a place.
const int _maxQueryLength = 200;

/// Most lines taken as a search query (a name, a street, a town, a country).
const int _maxQueryLines = 4;

/// Reads a place out of [text], or `null` when there is none in it.
///
/// Never throws: whatever another app sends is untrusted.
LocationLink? parseLocationLink(String text) {
  try {
    return _parse(text);
  } on Object {
    return null;
  }
}

LocationLink? _parse(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;

  // A link on its own, perhaps with unencoded spaces in it.
  if (!text.contains('\n') && _schemePattern.hasMatch(text)) {
    final whole = _parseLink(text);
    if (whole != null || !text.contains(RegExp(r'\s'))) return whole;
  }

  // A link inside text: "Brandenburger Tor\nhttps://maps.app.goo.gl/…".
  final linkMatch = _embeddedLinkPattern.firstMatch(text);
  if (linkMatch != null) {
    final link = _trimTrailingPunctuation(linkMatch.group(0)!);
    final around = _asQuery(
      text.replaceRange(linkMatch.start, linkMatch.end, '\n'),
    );
    final parsed = _parseLink(link);
    // Text with a link to something else is a message, not a place.
    if (parsed == null) return null;
    if (parsed.source == LocationLinkSource.shortLink) {
      return around == null
          ? parsed
          : LocationLink(
              source: LocationLinkSource.shortLink,
              query: around,
              shortLink: parsed.shortLink,
            );
    }
    if (parsed.position != null && parsed.name == null && around != null) {
      return LocationLink(
        source: parsed.source,
        position: parsed.position,
        query: parsed.query,
        name: _firstLine(text.substring(0, linkMatch.start)),
      );
    }
    return parsed;
  }

  // Coordinates anywhere in the text.
  final coordinates = _findCoordinates(text);
  if (coordinates != null) {
    return LocationLink(source: LocationLinkSource.text, position: coordinates);
  }

  final query = _asQuery(text);
  if (query == null) return null;
  return LocationLink(source: LocationLinkSource.text, query: query);
}

final RegExp _schemePattern = RegExp(
  r'^(?:https?://|geo:|maps:|velorki:)',
  caseSensitive: false,
);

final RegExp _embeddedLinkPattern = RegExp(
  r'(?:https?://|geo:|maps:|velorki:)\S+',
  caseSensitive: false,
);

String _trimTrailingPunctuation(String link) {
  var out = link;
  while (out.isNotEmpty) {
    final last = out[out.length - 1];
    if ('.,;:!?"\'>]'.contains(last) || (last == ')' && !out.contains('('))) {
      out = out.substring(0, out.length - 1);
    } else {
      break;
    }
  }
  return out;
}

/// [text] as a search query: its non-empty lines, each with its whitespace
/// collapsed, joined by commas; `null` when it is empty or too long to be an
/// address or a name.
String? _asQuery(String text) {
  final lines = text
      .split(RegExp(r'[\r\n]+'))
      .map((l) => l.replaceAll(RegExp(r'\s+'), ' ').trim())
      .where((l) => l.isNotEmpty)
      .toList();
  if (lines.isEmpty || lines.length > _maxQueryLines) return null;
  final query = lines.join(', ');
  if (query.length > _maxQueryLength) return null;
  return query;
}

String? _firstLine(String text) {
  for (final line in text.split(RegExp(r'[\r\n]+'))) {
    final trimmed = line.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (trimmed.isNotEmpty) {
      return trimmed.length > _maxQueryLength ? null : trimmed;
    }
  }
  return null;
}

// --- links ----------------------------------------------------------------

/// The parts of a link, read leniently: unencoded spaces, a broken `%` escape
/// or a scheme Dart's [Uri] does not know are all things other apps send.
class _Link {
  _Link(this.scheme, this.host, this.path, this.params, this.fragment);

  final String scheme;
  final String host;
  final String path;
  final Map<String, String> params;
  final String fragment;

  String? param(String name) {
    final value = params[name]?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  /// The path's segments, decoded, without empty ones.
  List<String> get segments => path
      .split('/')
      .where((s) => s.isNotEmpty)
      .map((s) => _decode(s, plusIsSpace: true))
      .toList();
}

_Link? _split(String link) {
  final colon = link.indexOf(':');
  if (colon <= 0) return null;
  final scheme = link.substring(0, colon).toLowerCase();
  var rest = link.substring(colon + 1);

  var fragment = '';
  final hash = rest.indexOf('#');
  if (hash >= 0) {
    fragment = rest.substring(hash + 1);
    rest = rest.substring(0, hash);
  }
  var query = '';
  final question = rest.indexOf('?');
  if (question >= 0) {
    query = rest.substring(question + 1);
    rest = rest.substring(0, question);
  }
  var host = '';
  if (rest.startsWith('//')) {
    rest = rest.substring(2);
    final slash = rest.indexOf('/');
    host = (slash < 0 ? rest : rest.substring(0, slash)).toLowerCase();
    rest = slash < 0 ? '' : rest.substring(slash);
    // No port or user info in a map link; drop them if there are.
    final at = host.lastIndexOf('@');
    if (at >= 0) host = host.substring(at + 1);
    final port = host.indexOf(':');
    if (port >= 0) host = host.substring(0, port);
  }
  final params = <String, String>{};
  for (final pair in query.split('&')) {
    if (pair.isEmpty) continue;
    final eq = pair.indexOf('=');
    final key = _decode(eq < 0 ? pair : pair.substring(0, eq)).toLowerCase();
    final value = eq < 0 ? '' : _decode(pair.substring(eq + 1));
    // The first value wins: a repeated key is a sender's mistake.
    params.putIfAbsent(key, () => value);
  }
  return _Link(scheme, host, rest, params, fragment);
}

String _decode(String s, {bool plusIsSpace = true}) {
  final spaced = plusIsSpace ? s.replaceAll('+', ' ') : s;
  try {
    return Uri.decodeComponent(spaced);
  } on ArgumentError {
    return spaced;
  } on FormatException {
    return spaced;
  }
}

LocationLink? _parseLink(String text) {
  final link = _split(text);
  if (link == null) return null;
  switch (link.scheme) {
    case 'geo':
      return _parseGeo(link);
    case 'maps':
      return _parseApple(link);
    case 'velorki':
      return _parseVelorki(link);
    case 'http':
    case 'https':
      final host = link.host.startsWith('www.')
          ? link.host.substring(4)
          : link.host;
      if (host == 'maps.app.goo.gl' ||
          (host == 'goo.gl' && link.path.startsWith('/maps')) ||
          (host == 'osm.org' && link.path.startsWith('/go/')) ||
          (host == 'openstreetmap.org' && link.path.startsWith('/go/'))) {
        return LocationLink(
          source: LocationLinkSource.shortLink,
          shortLink: Uri.tryParse(text.trim()),
        );
      }
      if (_googleHost.hasMatch(host)) {
        if (host.startsWith('maps.') || link.path.startsWith('/maps')) {
          return _parseGoogle(link);
        }
        return null;
      }
      if (host == 'maps.apple' && link.path.startsWith('/p/')) {
        return LocationLink(
          source: LocationLinkSource.shortLink,
          shortLink: Uri.tryParse(text.trim()),
        );
      }
      if (host == 'maps.apple.com' || host == 'maps.apple') {
        return _parseApple(link);
      }
      if (host == 'openstreetmap.org' || host == 'osm.org') {
        return _parseOsm(link);
      }
      return null;
    default:
      return null;
  }
}

final RegExp _googleHost = RegExp(
  r'^(?:maps\.)?google\.[a-z]{2,3}(?:\.[a-z]{2})?$',
);

/// `geo:LAT,LON[,ALT][;u=…][?z=…]` and `geo:0,0?q=LAT,LON(Label)` or
/// `geo:0,0?q=Some+Address`.
LocationLink? _parseGeo(_Link link) {
  final q = link.param('q');
  final at = _geoPathPosition(link);
  if (q != null) {
    final labelled = _parseLabelledLatLon(q);
    if (labelled != null) {
      return LocationLink(
        source: LocationLinkSource.geo,
        position: labelled.$1,
        name: labelled.$2,
      );
    }
    // Coordinates and a name: the place, labelled. Without coordinates
    // (`geo:0,0?q=…`) the name is what to search for.
    if (at != null) {
      return LocationLink(
        source: LocationLinkSource.geo,
        position: at,
        name: _firstLine(q),
      );
    }
    final query = _asQuery(q);
    if (query != null) {
      return LocationLink(source: LocationLinkSource.geo, query: query);
    }
    return null;
  }
  if (at == null) return null;
  return LocationLink(source: LocationLinkSource.geo, position: at);
}

/// The coordinates in a `geo:` URI's path, or `null` for none or `0,0`.
LatLng? _geoPathPosition(_Link link) {
  // The path, before any `;u=` uncertainty or `;crs=` parameter.
  var path = _decode(link.path, plusIsSpace: false);
  if (path.startsWith('//')) path = path.substring(2);
  final semicolon = path.indexOf(';');
  if (semicolon >= 0) path = path.substring(0, semicolon);
  final parts = path.split(',');
  if (parts.length < 2) return null;
  final position = _latLon(parts[0], parts[1]);
  // geo:0,0 is how a sender says "no position, see q".
  if (position == null || (position.lat == 0 && position.lon == 0)) {
    return null;
  }
  return position;
}

/// `velorki://navigate?lat=…&lon=…[&name=…]` or `velorki://navigate?q=…`.
LocationLink? _parseVelorki(_Link link) {
  final target = link.host.isNotEmpty
      ? link.host
      : link.path.replaceAll('/', '');
  if (target != navigateLinkHost) return null;
  final lat = link.param('lat');
  final lon = link.param('lon') ?? link.param('lng');
  final name = link.param('name');
  if (lat != null && lon != null) {
    final position = _latLon(lat, lon);
    if (position == null) return null;
    return LocationLink(
      source: LocationLinkSource.velorki,
      position: position,
      name: name,
    );
  }
  final q = link.param('q');
  if (q == null) return null;
  final labelled = _parseLabelledLatLon(q);
  if (labelled != null) {
    return LocationLink(
      source: LocationLinkSource.velorki,
      position: labelled.$1,
      name: name ?? labelled.$2,
    );
  }
  final query = _asQuery(q);
  if (query == null) return null;
  return LocationLink(source: LocationLinkSource.velorki, query: query);
}

/// Google Maps, in the shapes its apps and its URL API produce.
LocationLink? _parseGoogle(_Link link) {
  const source = LocationLinkSource.googleMaps;

  // Directions: the destination, never the origin.
  final destination = link.param('destination') ?? link.param('daddr');
  if (destination != null) {
    return _fromValue(_lastStop(destination), source);
  }

  final segments = link.segments;
  final maps = segments.indexOf('maps');
  final after = maps < 0 ? segments : segments.sublist(maps + 1);
  final kind = after.isEmpty ? '' : after.first;

  // The place's own coordinates, `!3dLAT!4dLON` in the data blob, are where
  // the pin is; the `@LAT,LON,17z` segment is only where the map looked.
  final pin = _googlePin(link.path);
  final viewport = _googleViewport(after);

  switch (kind) {
    case 'place':
      final name = after.length > 1 && !after[1].startsWith('@')
          ? after[1]
          : null;
      final position =
          pin ??
          (name == null ? null : _parseLabelledLatLon(name)?.$1) ??
          viewport;
      if (position != null) {
        final named = name == null || _parseLatLon(name) != null ? null : name;
        return LocationLink(source: source, position: position, name: named);
      }
      if (name != null) return _fromValue(name, source);
      return null;
    case 'dir':
      final stops = after
          .skip(1)
          .where((s) => !s.startsWith('@') && !s.startsWith('data='))
          .toList();
      if (stops.isNotEmpty) return _fromValue(stops.last, source);
    case 'search':
      final query = link.param('query');
      if (query != null) return _fromValue(query, source);
      if (after.length > 1 && !after[1].startsWith('@')) {
        return _fromValue(after[1], source);
      }
  }

  final q = link.param('query') ?? link.param('q') ?? link.param('ll');
  if (q != null) {
    final value = q.startsWith('loc:') ? q.substring(4) : q;
    return _fromValue(value, source);
  }
  final center = link.param('center');
  if (center != null) {
    final position = _parseLatLon(center);
    if (position != null) {
      return LocationLink(source: source, position: position);
    }
  }
  final position = pin ?? viewport;
  if (position != null) return LocationLink(source: source, position: position);
  return null;
}

/// The last stop of a Google `daddr`, which may chain several: `A to:B`.
String _lastStop(String value) {
  final stops = value.split(RegExp(r'\s*\bto:\s*'));
  return stops.lastWhere((s) => s.trim().isNotEmpty, orElse: () => value);
}

final RegExp _googlePinPattern = RegExp(
  r'!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)',
);

LatLng? _googlePin(String path) {
  final matches = _googlePinPattern.allMatches(path).toList();
  if (matches.isEmpty) return null;
  // With several, the last is the place the link is about.
  final m = matches.last;
  return _latLon(m.group(1)!, m.group(2)!);
}

final RegExp _viewportPattern = RegExp(
  r'^@(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)',
);

LatLng? _googleViewport(List<String> segments) {
  for (final segment in segments) {
    final m = _viewportPattern.firstMatch(segment);
    if (m != null) return _latLon(m.group(1)!, m.group(2)!);
  }
  return null;
}

/// Apple Maps: `https://maps.apple.com/?…` and `maps://?…`, the old
/// parameters and the newer `/place`, `/directions` and `/search` forms.
LocationLink? _parseApple(_Link link) {
  const source = LocationLinkSource.appleMaps;
  final q = link.param('q');
  final explicitName = link.param('name');

  final destination = link.param('daddr') ?? link.param('destination');
  if (destination != null) return _fromValue(destination, source);

  final ll = link.param('ll') ?? link.param('coordinate');
  if (ll != null) {
    final position = _parseLatLon(ll);
    if (position != null) {
      final name =
          explicitName ?? (q != null && _parseLatLon(q) == null ? q : null);
      return LocationLink(source: source, position: position, name: name);
    }
  }
  final address = link.param('address');
  if (address != null) return _fromValue(address, source);
  final query = q ?? link.param('query');
  if (query != null) return _fromValue(query, source);
  final sll = link.param('sll') ?? link.param('center');
  if (sll != null) {
    final position = _parseLatLon(sll);
    if (position != null) {
      return LocationLink(source: source, position: position);
    }
  }
  return null;
}

/// OpenStreetMap: a marker (`mlat`/`mlon`), the map's view (`#map=Z/LAT/LON`)
/// or a search (`/search?query=…`).
LocationLink? _parseOsm(_Link link) {
  const source = LocationLinkSource.openStreetMap;
  final mlat = link.param('mlat');
  final mlon = link.param('mlon');
  if (mlat != null && mlon != null) {
    final position = _latLon(mlat, mlon);
    if (position != null) {
      return LocationLink(source: source, position: position);
    }
  }
  if (link.path.startsWith('/search') || link.path.startsWith('/directions')) {
    final value = link.param('query') ?? link.param('to');
    if (value != null) return _fromValue(value, source);
  }
  final view = _osmViewPattern.firstMatch(link.fragment);
  if (view != null) {
    final position = _latLon(view.group(1)!, view.group(2)!);
    if (position != null) {
      return LocationLink(source: source, position: position);
    }
  }
  final lat = link.param('lat');
  final lon = link.param('lon');
  if (lat != null && lon != null) {
    final position = _latLon(lat, lon);
    if (position != null) {
      return LocationLink(source: source, position: position);
    }
  }
  return null;
}

final RegExp _osmViewPattern = RegExp(
  r'(?:^|&)map=\d+(?:\.\d+)?/(-?\d+(?:\.\d+)?)/(-?\d+(?:\.\d+)?)',
);

/// A parameter's value: coordinates (with a label in brackets, perhaps) or
/// an address.
LocationLink? _fromValue(String value, LocationLinkSource source) {
  final labelled = _parseLabelledLatLon(value);
  if (labelled != null) {
    return LocationLink(
      source: source,
      position: labelled.$1,
      name: labelled.$2,
    );
  }
  final query = _asQuery(value);
  if (query == null) return null;
  return LocationLink(source: source, query: query);
}

// --- coordinates ----------------------------------------------------------

final RegExp _labelledLatLonPattern = RegExp(
  r'^\s*([-+]?\d{1,3}(?:\.\d+)?)\s*,\s*([-+]?\d{1,3}(?:\.\d+)?)\s*(?:\((.*)\))?\s*$',
);

/// `LAT,LON` or `LAT,LON(Label)`.
(LatLng, String?)? _parseLabelledLatLon(String value) {
  final m = _labelledLatLonPattern.firstMatch(value);
  if (m == null) return null;
  final position = _latLon(m.group(1)!, m.group(2)!);
  if (position == null) return null;
  final label = m.group(3)?.trim();
  return (position, label == null || label.isEmpty ? null : label);
}

LatLng? _parseLatLon(String value) => _parseLabelledLatLon(value)?.$1;

LatLng? _latLon(String lat, String lon) {
  final la = double.tryParse(lat.trim());
  final lo = double.tryParse(lon.trim());
  return _checked(la, lo);
}

LatLng? _checked(double? lat, double? lon) {
  if (lat == null || lon == null) return null;
  if (!lat.isFinite || !lon.isFinite) return null;
  if (lat < -90 || lat > 90 || lon < -180 || lon > 180) return null;
  return LatLng(lat, lon);
}

/// One angle in degrees, minutes and seconds, any of the last two left out:
/// `52°31'12.5"`, `52° 31.2'`, `52.52°`, `52.52`.
const String _angle =
    r'''(\d{1,3}(?:[.,]\d+)?)\s*°?\s*(?:(\d{1,2}(?:[.,]\d+)?)\s*['′’]\s*)?(?:(\d{1,2}(?:[.,]\d+)?)\s*(?:"|″|”|''|′′)\s*)?''';

/// `52°31'12"N 13°24'18"E`: the hemisphere after the angle.
final RegExp _hemisphereAfter = RegExp(
  '(?<![\\w.])$_angle([NS])(?![A-Za-z])[\\s,;/]*$_angle([EWO])(?![A-Za-z])',
);

/// `N 52.52000 E 13.40500`, `N52° 31.200' E13° 24.300'`: before it.
final RegExp _hemisphereBefore = RegExp(
  '(?<![\\w])([NS])\\s*$_angle[\\s,;/]*([EWO])\\s*$_angle',
);

/// `52.5200, 13.4050` or `52.5200 13.4050`: decimal degrees, both with a
/// fraction, so a street number and a postcode never read as a place.
final RegExp _decimalPair = RegExp(
  r'(?<![\w.+-])([-+]?\d{1,3}\.\d+)\s*°?\s*(?:[,;/]\s*|\s+)([-+]?\d{1,3}\.\d+)°?(?![\w.])',
);

LatLng? _findCoordinates(String text) {
  final after = _hemisphereAfter.firstMatch(text);
  if (after != null) {
    final lat = _degrees(after.group(1), after.group(2), after.group(3));
    final lon = _degrees(after.group(5), after.group(6), after.group(7));
    final position = _signed(lat, after.group(4)!, lon, after.group(8)!);
    if (position != null) return position;
  }
  final before = _hemisphereBefore.firstMatch(text);
  if (before != null) {
    final lat = _degrees(before.group(2), before.group(3), before.group(4));
    final lon = _degrees(before.group(6), before.group(7), before.group(8));
    final position = _signed(lat, before.group(1)!, lon, before.group(5)!);
    if (position != null) return position;
  }
  for (final m in _decimalPair.allMatches(text)) {
    final position = _latLon(m.group(1)!, m.group(2)!);
    if (position != null) return position;
  }
  return null;
}

double? _degrees(String? d, String? m, String? s) {
  double? number(String? v) =>
      v == null ? null : double.tryParse(v.replaceAll(',', '.'));
  final degrees = number(d);
  if (degrees == null) return null;
  final minutes = number(m) ?? 0;
  final seconds = number(s) ?? 0;
  if (minutes >= 60 || seconds >= 60) return null;
  return degrees + minutes / 60 + seconds / 3600;
}

LatLng? _signed(double? lat, String ns, double? lon, String ew) {
  if (lat == null || lon == null) return null;
  return _checked(ns == 'S' ? -lat : lat, ew == 'W' ? -lon : lon);
}
