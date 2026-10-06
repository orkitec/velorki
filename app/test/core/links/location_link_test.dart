import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/links/location_link.dart';
import 'package:velorki_geo/velorki_geo.dart';

void main() {
  const berlin = LatLng(52.52, 13.405);

  void expectAt(
    String input,
    LatLng position, {
    required LocationLinkSource source,
    String? name,
  }) {
    final link = parseLocationLink(input);
    expect(link, isNotNull, reason: input);
    expect(link!.source, source, reason: input);
    expect(link.position, isNotNull, reason: input);
    expect(link.position!.lat, closeTo(position.lat, 1e-6), reason: input);
    expect(link.position!.lon, closeTo(position.lon, 1e-6), reason: input);
    expect(link.query, isNull, reason: input);
    expect(link.name, name, reason: input);
  }

  void expectQuery(
    String input,
    String query, {
    required LocationLinkSource source,
  }) {
    final link = parseLocationLink(input);
    expect(link, isNotNull, reason: input);
    expect(link!.source, source, reason: input);
    expect(link.position, isNull, reason: input);
    expect(link.query, query, reason: input);
  }

  group('geo:', () {
    const geo = LocationLinkSource.geo;
    test(
      'coordinates',
      () => expectAt('geo:52.52,13.405', berlin, source: geo),
    );
    test(
      'with a zoom',
      () => expectAt('geo:52.52,13.405?z=17', berlin, source: geo),
    );
    test(
      'with altitude and uncertainty',
      () => expectAt('geo:52.52,13.405,34;u=35', berlin, source: geo),
    );
    test(
      'q with coordinates and a label',
      () => expectAt(
        'geo:0,0?q=52.52,13.405(Brandenburger%20Tor)',
        berlin,
        source: geo,
        name: 'Brandenburger Tor',
      ),
    );
    test(
      'q with an address',
      () => expectQuery(
        'geo:0,0?q=Pariser+Platz+1,+Berlin',
        'Pariser Platz 1, Berlin',
        source: geo,
      ),
    );
    test(
      'q with unencoded spaces',
      () => expectQuery(
        'geo:0,0?q=Pariser Platz 1, Berlin',
        'Pariser Platz 1, Berlin',
        source: geo,
      ),
    );
    test(
      'coordinates and a name in q',
      () => expectAt(
        'geo:52.52,13.405?q=Bakery',
        berlin,
        source: geo,
        name: 'Bakery',
      ),
    );
    test('0,0 alone is nothing', () {
      expect(parseLocationLink('geo:0,0'), isNull);
    });
    test('out of range', () {
      expect(parseLocationLink('geo:91,13'), isNull);
      expect(parseLocationLink('geo:52,181'), isNull);
    });
    test('garbage', () {
      expect(parseLocationLink('geo:'), isNull);
      expect(parseLocationLink('geo:abc,def'), isNull);
      expect(parseLocationLink('geo:52.5'), isNull);
      expect(parseLocationLink('geo:0,0?q=%E0%A4%A'), isNotNull);
    });
  });

  group('Google Maps', () {
    const google = LocationLinkSource.googleMaps;
    test(
      'maps.google.com/?q=LAT,LON',
      () => expectAt(
        'https://maps.google.com/?q=52.52,13.405',
        berlin,
        source: google,
      ),
    );
    test(
      'search API',
      () => expectAt(
        'https://www.google.com/maps/search/?api=1&query=52.52%2C13.405',
        berlin,
        source: google,
      ),
    );
    test(
      'search API with an address',
      () => expectQuery(
        'https://www.google.com/maps/search/?api=1&query=Pariser+Platz+1+Berlin',
        'Pariser Platz 1 Berlin',
        source: google,
      ),
    );
    test(
      'place with a viewport',
      () => expectAt(
        'https://www.google.com/maps/place/Brandenburger+Tor/@52.52,13.405,17z/',
        berlin,
        source: google,
        name: 'Brandenburger Tor',
      ),
    );
    test(
      'place: the pin wins over the viewport',
      () => expectAt(
        'https://www.google.com/maps/place/Brandenburger+Tor/'
        '@52.5,13.4,17z/data=!3m1!4b1!4m6!3m5!1s0x0:0x0!8m2!3d52.52!4d13.405',
        berlin,
        source: google,
        name: 'Brandenburger Tor',
      ),
    );
    test(
      'place in another country domain',
      () => expectAt(
        'https://www.google.de/maps/place/Brandenburger%20Tor/@52.52,13.405,17z',
        berlin,
        source: google,
        name: 'Brandenburger Tor',
      ),
    );
    test(
      'directions API with coordinates, not the origin',
      () => expectAt(
        'https://www.google.com/maps/dir/?api=1&origin=48.1,11.5'
        '&destination=52.52,13.405',
        berlin,
        source: google,
      ),
    );
    test(
      'directions API with an address',
      () => expectQuery(
        'https://www.google.com/maps/dir/?api=1&destination=Pariser+Platz+1%2C+Berlin',
        'Pariser Platz 1, Berlin',
        source: google,
      ),
    );
    test(
      'directions path: the last stop',
      () => expectQuery(
        'https://www.google.com/maps/dir/Munich/Pariser+Platz,+Berlin/@50,12,6z',
        'Pariser Platz, Berlin',
        source: google,
      ),
    );
    test(
      'daddr, not saddr',
      () => expectAt(
        'https://maps.google.com/maps?saddr=48.1,11.5&daddr=52.52,13.405',
        berlin,
        source: google,
      ),
    );
    test(
      'daddr chained: the last stop',
      () => expectQuery(
        'https://maps.google.com/maps?daddr=Potsdam+to:Berlin',
        'Berlin',
        source: google,
      ),
    );
    test(
      'q with an address',
      () => expectQuery(
        'https://www.google.com/maps?q=Pariser+Platz+1,+Berlin',
        'Pariser Platz 1, Berlin',
        source: google,
      ),
    );
    test(
      'q with loc:',
      () => expectAt(
        'https://maps.google.com/?q=loc:52.52,13.405',
        berlin,
        source: google,
      ),
    );
    test(
      'viewport alone',
      () => expectAt(
        'https://www.google.com/maps/@52.52,13.405,15z',
        berlin,
        source: google,
      ),
    );
    test('short links cannot be resolved', () {
      for (final link in [
        'https://maps.app.goo.gl/AbCdEf123',
        'https://goo.gl/maps/AbCdEf123',
      ]) {
        final parsed = parseLocationLink(link);
        expect(parsed?.source, LocationLinkSource.shortLink, reason: link);
        expect(parsed!.isUnresolvable, isTrue);
      }
    });
    test('google.com without maps is not a place', () {
      expect(
        parseLocationLink('https://www.google.com/search?q=berlin'),
        isNull,
      );
    });
  });

  group('Apple Maps', () {
    const apple = LocationLinkSource.appleMaps;
    test(
      'll with a name',
      () => expectAt(
        'https://maps.apple.com/?ll=52.52,13.405&q=Brandenburger%20Tor',
        berlin,
        source: apple,
        name: 'Brandenburger Tor',
      ),
    );
    test(
      'daddr',
      () => expectAt(
        'https://maps.apple.com/?saddr=48.1,11.5&daddr=52.52,13.405',
        berlin,
        source: apple,
      ),
    );
    test(
      'daddr with an address',
      () => expectQuery(
        'https://maps.apple.com/?daddr=Pariser+Platz+1,+Berlin',
        'Pariser Platz 1, Berlin',
        source: apple,
      ),
    );
    test(
      'address',
      () => expectQuery(
        'https://maps.apple.com/?address=Pariser%20Platz%201,%2010117%20Berlin',
        'Pariser Platz 1, 10117 Berlin',
        source: apple,
      ),
    );
    test(
      'q',
      () => expectQuery(
        'https://maps.apple.com/?q=Brandenburger+Tor',
        'Brandenburger Tor',
        source: apple,
      ),
    );
    test(
      'the place form with coordinate and name',
      () => expectAt(
        'https://maps.apple.com/place?coordinate=52.52,13.405'
        '&name=Brandenburger%20Tor&address=Pariser%20Platz',
        berlin,
        source: apple,
        name: 'Brandenburger Tor',
      ),
    );
    test(
      'maps:// with ll',
      () => expectAt(
        'maps://?ll=52.52,13.405&q=Tor',
        berlin,
        source: apple,
        name: 'Tor',
      ),
    );
    test(
      'maps: with daddr',
      () => expectAt('maps:?daddr=52.52,13.405', berlin, source: apple),
    );
    test(
      'maps:// with an address',
      () => expectQuery(
        'maps://?address=Pariser+Platz',
        'Pariser Platz',
        source: apple,
      ),
    );
    test('maps.apple short links cannot be resolved', () {
      expect(
        parseLocationLink('https://maps.apple/p/AbCdEf')?.source,
        LocationLinkSource.shortLink,
      );
    });
  });

  group('OpenStreetMap', () {
    const osm = LocationLinkSource.openStreetMap;
    test(
      'marker and view: the marker',
      () => expectAt(
        'https://www.openstreetmap.org/?mlat=52.52&mlon=13.405#map=17/52.5/13.4',
        berlin,
        source: osm,
      ),
    );
    test(
      'view alone',
      () => expectAt(
        'https://www.openstreetmap.org/#map=17/52.52/13.405',
        berlin,
        source: osm,
      ),
    );
    test(
      'view with layers',
      () => expectAt(
        'https://www.openstreetmap.org/#map=17/52.52/13.405&layers=C',
        berlin,
        source: osm,
      ),
    );
    test(
      'search',
      () => expectQuery(
        'https://www.openstreetmap.org/search?query=Pariser%20Platz%201%2C%20Berlin',
        'Pariser Platz 1, Berlin',
        source: osm,
      ),
    );
    test(
      'search with coordinates',
      () => expectAt(
        'https://www.openstreetmap.org/search?query=52.52%2C13.405',
        berlin,
        source: osm,
      ),
    );
    test('osm.org/go short links cannot be resolved', () {
      expect(
        parseLocationLink('https://osm.org/go/0MbEUuVi-')?.source,
        LocationLinkSource.shortLink,
      );
    });
    test('a node without coordinates is nothing', () {
      expect(parseLocationLink('https://www.openstreetmap.org/node/1'), isNull);
    });
  });

  group('velorki://navigate', () {
    const velorki = LocationLinkSource.velorki;
    test(
      'coordinates',
      () => expectAt(
        'velorki://navigate?lat=52.52&lon=13.405',
        berlin,
        source: velorki,
      ),
    );
    test(
      'coordinates with a name',
      () => expectAt(
        'velorki://navigate?lat=52.52&lon=13.405&name=Brandenburger%20Tor',
        berlin,
        source: velorki,
        name: 'Brandenburger Tor',
      ),
    );
    test(
      'a query',
      () => expectQuery(
        'velorki://navigate?q=Pariser+Platz+1%2C+Berlin',
        'Pariser Platz 1, Berlin',
        source: velorki,
      ),
    );
    test('out of range or missing', () {
      expect(parseLocationLink('velorki://navigate?lat=95&lon=13'), isNull);
      expect(parseLocationLink('velorki://navigate?lat=52'), isNull);
      expect(parseLocationLink('velorki://navigate'), isNull);
      expect(parseLocationLink('velorki://navigate?lat=x&lon=y'), isNull);
    });
    test('other velorki links are not places', () {
      expect(parseLocationLink('velorki://share/7Kq2mZ0aTb'), isNull);
      expect(parseLocationLink('velorki://oauth/strava?code=1'), isNull);
    });
  });

  group('text', () {
    const text = LocationLinkSource.text;
    test(
      'decimal with a comma',
      () => expectAt('52.5200, 13.4050', berlin, source: text),
    );
    test(
      'decimal with a space',
      () => expectAt('52.5200 13.4050', berlin, source: text),
    );
    test(
      'negative decimal',
      () => expectAt(
        '-33.8568, -151.2153',
        const LatLng(-33.8568, -151.2153),
        source: text,
      ),
    );
    test(
      'coordinates inside a sentence',
      () => expectAt(
        'Meet me at 52.5200, 13.4050 at noon!',
        berlin,
        source: text,
      ),
    );
    test(
      'degrees, minutes, seconds',
      () => expectAt(
        '52°31\'12"N 13°24\'18"E',
        const LatLng(52.52, 13.405),
        source: text,
      ),
    );
    test(
      'degrees, minutes, seconds south and west',
      () => expectAt(
        '22°54\'30"S 43°11\'47"W',
        const LatLng(-(22 + 54 / 60 + 30 / 3600), -(43 + 11 / 60 + 47 / 3600)),
        source: text,
      ),
    );
    test(
      'hemisphere first',
      () => expectAt('N 52.52000 E 13.40500', berlin, source: text),
    );
    test(
      'hemisphere first with decimal minutes',
      () => expectAt(
        "N52° 31.200' E13° 24.300'",
        const LatLng(52.52, 13.405),
        source: text,
      ),
    );
    test(
      'an address',
      () => expectQuery(
        'Pariser Platz 1\n10117 Berlin',
        'Pariser Platz 1, 10117 Berlin',
        source: text,
      ),
    );
    test(
      'a name',
      () => expectQuery(
        '  Brandenburger Tor ',
        'Brandenburger Tor',
        source: text,
      ),
    );
    test('a street number and a postcode are not coordinates', () {
      expectQuery(
        'Hauptstraße 12, 10115 Berlin',
        'Hauptstraße 12, 10115 Berlin',
        source: text,
      );
    });
    test('a long message is not a place', () {
      expect(parseLocationLink('word ' * 60), isNull);
      expect(parseLocationLink('a\nb\nc\nd\ne\nf'), isNull);
    });
    test(
      'a map link inside text, named by the line before it',
      () => expectAt(
        'Brandenburger Tor\nhttps://maps.google.com/?q=52.52,13.405',
        berlin,
        source: LocationLinkSource.googleMaps,
        name: 'Brandenburger Tor',
      ),
    );
    test('a short link inside text searches for the text around it', () {
      final link = parseLocationLink(
        'Brandenburger Tor\nPariser Platz, 10117 Berlin\n'
        'https://maps.app.goo.gl/AbCdEf123',
      );
      expect(link?.source, LocationLinkSource.shortLink);
      expect(link!.query, 'Brandenburger Tor, Pariser Platz, 10117 Berlin');
    });
    test('a link to something else is not a place', () {
      expect(parseLocationLink('https://example.com/page'), isNull);
      expect(parseLocationLink('Look at this https://example.com'), isNull);
    });
  });

  group('bad input', () {
    test('empty and whitespace', () {
      expect(parseLocationLink(''), isNull);
      expect(parseLocationLink('   \n '), isNull);
    });
    test('does not throw on junk', () {
      for (final junk in [
        'geo:%%%',
        'https://',
        'https://www.google.com/maps/place/%E0%A4%A',
        'velorki://navigate?lat=%&lon=%',
        'maps://?ll=,',
        ':::',
        '°°° N E',
        'https://maps.apple.com/?ll=999,999',
        'https://www.openstreetmap.org/#map=a/b/c',
      ]) {
        expect(() => parseLocationLink(junk), returnsNormally, reason: junk);
      }
    });
    test('out of range coordinates in text', () {
      expect(parseLocationLink('95.0, 13.0')?.position, isNull);
      expect(parseLocationLink('52.0, 190.0')?.position, isNull);
    });
  });
}
