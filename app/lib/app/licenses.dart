import 'package:flutter/foundation.dart';

/// Registers the licences of the data and services Velorki uses.
///
/// Flutter's `LicensePage` collects the licences of every Dart package in the
/// bundle by itself. What it cannot know about is the rest: the map data, the
/// tiles, the routing engine and the geocoder are not pub packages, yet their
/// licences — ODbL in particular — require attribution wherever the data is
/// used. Registering them here puts them on the same screen as everything
/// else, which is what the store checklist asks for.
///
/// Called once from `bootstrap()`, before `runApp`. [LicenseRegistry] calls
/// the collector lazily, so nothing is read until the licence page is opened.
void registerVelorkiLicenses() {
  LicenseRegistry.addLicense(_velorkiLicenses);
}

Stream<LicenseEntry> _velorkiLicenses() async* {
  for (final entry in _entries) {
    yield LicenseEntryWithLineBreaks(<String>[entry.package], entry.text);
  }
}

/// One third party whose licence is not carried by a pub package.
@immutable
class _DataLicense {
  const _DataLicense(this.package, this.text);

  /// The name shown in the list.
  final String package;

  /// The licence notice shown when the entry is opened.
  final String text;
}

const List<_DataLicense> _entries = <_DataLicense>[
  _DataLicense('OpenStreetMap', '''
Map data © OpenStreetMap contributors.

The map data Velorki draws, routes on and searches in comes from
OpenStreetMap and is available under the Open Database License (ODbL) 1.0.
Individual map tiles and rendered images are available under the Creative
Commons Attribution-ShareAlike 2.0 licence (CC BY-SA 2.0).

You are free to copy, distribute, transmit and adapt the data, as long as you
credit OpenStreetMap and its contributors, and distribute any adapted database
under the same licence.

https://www.openstreetmap.org/copyright
https://opendatacommons.org/licenses/odbl/1-0/'''),
  _DataLicense('BRouter', '''
Routing by BRouter, © Arndt Brenschede and contributors, MIT licence.

Velorki plans bike routes with BRouter and ships its routing profiles; the
Dart port of the routing runtime in app/packages/brouter_dart follows the same
upstream source.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

https://github.com/abrensch/brouter'''),
  _DataLicense('OpenFreeMap and OpenMapTiles', '''
Vector map tiles by OpenFreeMap, built with OpenMapTiles from OpenStreetMap
data.

OpenFreeMap serves the default map style and requires no key. Its software is
published under the MIT licence, the OpenMapTiles schema and styles under the
BSD 3-Clause licence, and the tiles themselves carry the licence of the
underlying OpenStreetMap data (ODbL 1.0), with the design attributed as
"© OpenMapTiles".

https://openfreemap.org/
https://openmaptiles.org/
https://github.com/openmaptiles/openmaptiles/blob/master/LICENSE.md'''),
  _DataLicense('CyclOSM', '''
The optional cycling overlay is rendered by CyclOSM, a cycle-oriented map
style for OpenStreetMap, published under the CC BY-SA 4.0 licence and served
by the OpenStreetMap Foundation's tile servers.

The style may be shared and adapted with attribution, under the same licence.
Velorki follows the OSMF tile usage policy: tiles are fetched only for what is
on screen, and are never bulk downloaded or pre-cached.

https://www.cyclosm.org/
https://github.com/cyclosm/cyclosm-cartocss-style
https://operations.osmfoundation.org/policies/tiles/'''),
  _DataLicense('Photon', '''
Place search by Photon, © komoot GmbH and contributors, Apache License 2.0.

Photon geocodes the place names typed into the search field and the names the
assistant proposes. It is built on OpenStreetMap data (ODbL 1.0).

Licensed under the Apache License, Version 2.0 (the "License"); you may not
use this file except in compliance with the License. You may obtain a copy of
the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
License for the specific language governing permissions and limitations under
the License.

https://photon.komoot.io/
https://github.com/komoot/photon'''),
];
