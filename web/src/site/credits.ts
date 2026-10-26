// SPDX-License-Identifier: AGPL-3.0-only

export interface CreditLink {
  /** Shown as written, in every language: a project or a licence name. */
  label: string;
  href: string;
}

export interface Credit {
  /** The key of its texts under `credits.items` in the messages. */
  id: string;
  links: readonly CreditLink[];
  /**
   * The entries of `app/lib/app/licenses.dart` this credit stands for, by the
   * name the app's licence page lists them under; empty for what the app's
   * licence page lists by itself (Flutter and its packages) or the website
   * alone uses. `test/credits.test.ts` holds the two lists together.
   */
  app: readonly string[];
}

/**
 * The data, services, fonts and frameworks Velorki is built on, in the order
 * the ride uses them: the data, the routing, the tiles, the weather, the
 * search, then the renderer, the voices, the type and the toolkit. The wording
 * and the licence names follow `app/lib/app/licenses.dart`, which registers
 * the same list in the app, so the website and the About screen cannot drift
 * apart.
 */
export const CREDITS: readonly Credit[] = [
  {
    id: 'osm',
    links: [
      { label: 'openstreetmap.org/copyright', href: 'https://www.openstreetmap.org/copyright' },
      { label: 'ODbL 1.0', href: 'https://opendatacommons.org/licenses/odbl/1-0/' },
    ],
    app: ['OpenStreetMap'],
  },
  {
    id: 'brouter',
    links: [{ label: 'github.com/abrensch/brouter', href: 'https://github.com/abrensch/brouter' }],
    app: ['BRouter'],
  },
  {
    id: 'openfreemap',
    links: [
      { label: 'openfreemap.org', href: 'https://openfreemap.org/' },
      { label: 'openmaptiles.org', href: 'https://openmaptiles.org/' },
    ],
    app: ['OpenFreeMap and OpenMapTiles'],
  },
  {
    id: 'cyclosm',
    links: [
      { label: 'cyclosm.org', href: 'https://www.cyclosm.org/' },
      { label: 'CyclOSM licence', href: 'https://github.com/cyclosm/cyclosm-cartocss-style/blob/master/LICENSE.md' },
      { label: 'openstreetmap.fr', href: 'https://www.openstreetmap.fr/' },
    ],
    app: ['CyclOSM'],
  },
  {
    id: 'weatherMap',
    links: [
      { label: 'DWD', href: 'https://www.dwd.de/' },
      { label: 'KNMI', href: 'https://www.knmi.nl/' },
      { label: 'FMI', href: 'https://en.ilmatieteenlaitos.fi/open-data' },
      { label: 'EUMETNET', href: 'https://www.eumetnet.eu/' },
      { label: 'Radar-DPC', href: 'https://radar.protezionecivile.it/' },
      { label: 'NOAA NWS', href: 'https://www.weather.gov/' },
      { label: 'Iowa Environmental Mesonet', href: 'https://mesonet.agron.iastate.edu/' },
      { label: 'NASA GIBS', href: 'https://www.earthdata.nasa.gov/gibs' },
      { label: 'EUMETSAT', href: 'https://www.eumetsat.int/' },
      { label: 'H SAF', href: 'https://hsaf.meteoam.it/' },
      { label: 'CC BY 4.0', href: 'https://creativecommons.org/licenses/by/4.0/' },
      { label: 'CC BY-SA 4.0', href: 'https://creativecommons.org/licenses/by-sa/4.0/' },
    ],
    app: ['Weather map: rain radar, clouds and wind'],
  },
  {
    id: 'routeWeather',
    links: [
      { label: 'opendata.dwd.de', href: 'https://opendata.dwd.de/' },
      { label: 'brightsky.dev', href: 'https://brightsky.dev/' },
      { label: 'api.weather.gov', href: 'https://www.weather.gov/documentation/services-web-api' },
      { label: 'api.met.no', href: 'https://api.met.no/weatherapi/locationforecast/2.0/documentation' },
      { label: 'MET Norway licence', href: 'https://api.met.no/doc/License' },
    ],
    app: ['Route weather'],
  },
  {
    id: 'photon',
    links: [{ label: 'photon.komoot.io', href: 'https://photon.komoot.io/' }],
    app: ['Photon'],
  },
  {
    id: 'maplibre',
    links: [
      { label: 'maplibre.org', href: 'https://maplibre.org/' },
      { label: 'MapLibre Native', href: 'https://github.com/maplibre/maplibre-native' },
      { label: 'MapLibre GL JS', href: 'https://github.com/maplibre/maplibre-gl-js' },
    ],
    app: ['MapLibre Native'],
  },
  {
    id: 'voices',
    links: [
      {
        label: 'web-speech-recommended-voices',
        href: 'https://github.com/HadrienGardeur/web-speech-recommended-voices',
      },
    ],
    app: ['Voice catalogue'],
  },
  {
    id: 'fonts',
    links: [
      { label: 'Barlow Condensed', href: 'https://github.com/jpt/barlow' },
      { label: 'Manrope', href: 'https://github.com/sharanda/manrope' },
      { label: 'SIL Open Font License 1.1', href: 'https://openfontlicense.org/' },
    ],
    app: ['Manrope (font)', 'Barlow Condensed (font)'],
  },
  { id: 'flutter', links: [{ label: 'flutter.dev', href: 'https://flutter.dev/' }], app: [] },
];
