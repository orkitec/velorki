import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/search/domain/place_links.dart';
import 'package:velorki_geo/velorki_geo.dart';

const LatLng _p = LatLng(47.141, 9.5209);

void main() {
  test('Apple Maps gets the position and the encoded name', () {
    expect(
      appleMapsUri(_p, 'Café & Bar').toString(),
      'https://maps.apple.com/?ll=47.141000,9.520900&q=Caf%C3%A9%20%26%20Bar',
    );
    expect(
      appleMapsUri(_p, '').toString(),
      'https://maps.apple.com/?ll=47.141000,9.520900&q=47.141000%2C9.520900',
    );
  });

  test('Google Maps on iOS gets the position', () {
    expect(
      googleMapsUri(_p).toString(),
      'comgooglemaps://?q=47.141000,9.520900&center=47.141000,9.520900',
    );
    expect(googleMapsProbeUri.scheme, 'comgooglemaps');
  });

  test('a geo link labels the place, its parentheses escaped', () {
    expect(
      geoUri(_p, 'Café (Old) Town').toString(),
      'geo:47.141000,9.520900?q=47.141000,9.520900'
      '(Caf%C3%A9%20%28Old%29%20Town)',
    );
    expect(
      geoUri(_p, '').toString(),
      'geo:47.141000,9.520900?q=47.141000,9.520900',
    );
  });

  test('OpenStreetMap shows the element, or a marker without one', () {
    expect(
      openStreetMapUri(_p, osmType: 'way', osmId: 42).toString(),
      'https://www.openstreetmap.org/way/42',
    );
    expect(
      openStreetMapUri(_p).toString(),
      'https://www.openstreetmap.org/?mlat=47.141000&mlon=9.520900'
      '#map=18/47.141000/9.520900',
    );
  });

  test('a shared place is its name and its link', () {
    final link = Uri.parse('https://www.openstreetmap.org/node/1');
    expect(
      placeShareText('Café Wolf', link),
      'Café Wolf\nhttps://www.openstreetmap.org/node/1',
    );
    expect(placeShareText('', link), 'https://www.openstreetmap.org/node/1');
  });
}
