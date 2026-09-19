#!/usr/bin/env python3
"""Print a saved route's geometry as `lat,lon` lines for tool/emu_ride.py.

    unpack_route.py <velorki.sqlite> <route name> > path.txt

The `routes.geometry` blob is `PackedTrack`
(app/packages/velorki_geo/lib/src/packed_track.dart): a one-byte version
header, then fixed-size little-endian records of f64 latitude, f64 longitude,
f32 elevation, i64 time in milliseconds, f32 speed and f32 accuracy — 36 bytes
in version 1, plus three u16 sensor readings (heart rate, cadence, power) in
version 2, which is 42. Only the two coordinates are read here, so both
versions decode the same way; the record size is what the version decides.
"""
import sqlite3
import struct
import sys

database, name = sys.argv[1], sys.argv[2]
row = sqlite3.connect(database).execute(
    "select geometry from routes where name = ?", (name,)
).fetchone()
if row is None:
    sys.exit(f"no route called {name!r} in {database}")
blob = row[0]
RECORD_BYTES = {1: 36, 2: 42}
size = RECORD_BYTES.get(blob[0])
if size is None:
    sys.exit(f"unknown PackedTrack version {blob[0]}")
body = blob[1:]
print(f"# {name}, {len(body) // size} points, v{blob[0]}, from {database}")
for offset in range(0, len(body) - size + 1, size):
    latitude, longitude = struct.unpack_from("<dd", body, offset)
    print(f"{latitude:.6f},{longitude:.6f}")
