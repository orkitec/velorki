#!/usr/bin/env python3
"""Ride a straight line on the emulator.

Feeds the emulator GPGGA/GPRMC sentences once a second so the app sees a
rider moving at `speed` km/h on `course` degrees, with a real course and
speed on every fix (what `adb emu geo fix` cannot do). The RMC sentence must
end with the magnetic-variation pair; the emulator's parser rejects the
usual trailing mode field.

    tool/emu_ride.py [course_deg] [speed_kmh] [seconds] [serial]

Starts at the Hudson river path in Manhattan, where the app's emulator
checks take place.
"""
import math, subprocess, sys, time
lat, lon = 40.8153, -73.9645
course = float(sys.argv[1]) if len(sys.argv) > 1 else 45.0
speed_kmh = float(sys.argv[2]) if len(sys.argv) > 2 else 20.0
steps = int(sys.argv[3]) if len(sys.argv) > 3 else 20
serial = sys.argv[4] if len(sys.argv) > 4 else "emulator-5554"
ADB = ["adb", "-s", serial]
def nmea(lat, lon, course, speed_kmh):
    t = time.strftime("%H%M%S", time.gmtime())
    d = time.strftime("%d%m%y", time.gmtime())
    def dm(v, pos, neg):
        h = pos if v >= 0 else neg; v = abs(v); deg = int(v); m = (v - deg) * 60
        return f"{deg:02d}{m:07.4f}" if h in "NS" else f"{deg:03d}{m:07.4f}", h
    la, ns = dm(lat, "N", "S"); lo, ew = dm(lon, "E", "W")
    def wrap(body):
        cs = 0
        for c in body: cs ^= ord(c)
        return f"${body}*{cs:02X}"
    gga = f"GPGGA,{t},{la},{ns},{lo},{ew},1,10,1.0,12.0,M,0.0,M,,"
    rmc = f"GPRMC,{t},A,{la},{ns},{lo},{ew},{speed_kmh/1.852:.1f},{course:.1f},{d},0.0,E"
    return [wrap(gga), wrap(rmc)]
mps = speed_kmh / 3.6
for i in range(steps):
    for s in nmea(lat, lon, course, speed_kmh):
        subprocess.run(ADB + ["emu", "geo", "nmea", s], capture_output=True)
    dlat = mps * math.cos(math.radians(course)) / 111320.0
    dlon = mps * math.sin(math.radians(course)) / (111320.0 * math.cos(math.radians(lat)))
    lat += dlat; lon += dlon
    time.sleep(1)
print("done", lat, lon)
