#!/usr/bin/env python3
"""Ride a straight line on the emulator.

Feeds the emulator GPGGA/GPRMC sentences once a second so the app sees a
rider moving at `speed` km/h on `course` degrees, with a real course and
speed on every fix (what `adb emu geo fix` cannot do). The RMC sentence must
end with the magnetic-variation pair; the emulator's parser rejects the
usual trailing mode field.

    tool/emu_ride.py [course_deg] [speed_kmh] [seconds] [serial]
    tool/emu_ride.py --path points.txt [speed_kmh] [serial]

The first form rides a straight line from the Hudson river path in
Manhattan, where the app's emulator checks take place. The second follows
a polyline read from a file with one `lat,lon` per line (a GeoJSON
LineString's coordinates, for instance), so a planned route can be ridden
end to end at a steady speed; the course is the bearing to the next point.
"""
import math, subprocess, sys, time
lat, lon = 40.8153, -73.9645
path_mode = len(sys.argv) > 1 and sys.argv[1] == "--path"
if not path_mode:
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
def send(lat, lon, course, speed_kmh):
    for s in nmea(lat, lon, course, speed_kmh):
        subprocess.run(ADB + ["emu", "geo", "nmea", s], capture_output=True)


def bearing(a, b):
    la1, lo1, la2, lo2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    y = math.sin(lo2 - lo1) * math.cos(la2)
    x = math.cos(la1) * math.sin(la2) - math.sin(la1) * math.cos(la2) * math.cos(lo2 - lo1)
    return (math.degrees(math.atan2(y, x)) + 360) % 360


def distance(a, b):
    la1, lo1, la2, lo2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    h = math.sin((la2 - la1) / 2) ** 2 + math.cos(la1) * math.cos(la2) * math.sin((lo2 - lo1) / 2) ** 2
    return 2 * 6371000 * math.asin(math.sqrt(h))


if path_mode:
    points = []
    for line in open(sys.argv[2]):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        a, b = line.split(",")[:2]
        points.append((float(a), float(b)))
    speed_kmh = float(sys.argv[3]) if len(sys.argv) > 3 else 20.0
    serial = sys.argv[4] if len(sys.argv) > 4 else "emulator-5554"
    ADB = ["adb", "-s", serial]
    mps = speed_kmh / 3.6
    # Walk the polyline one second of travel at a time.
    seg = 0
    pos = points[0]
    ticks = 0
    while seg < len(points) - 1:
        budget = mps
        while budget > 0 and seg < len(points) - 1:
            nxt = points[seg + 1]
            d = distance(pos, nxt)
            if d <= budget:
                budget -= d
                pos = nxt
                seg += 1
            else:
                f = budget / d
                pos = (pos[0] + (nxt[0] - pos[0]) * f, pos[1] + (nxt[1] - pos[1]) * f)
                budget = 0
        course = bearing(pos, points[min(seg + 1, len(points) - 1)]) if seg < len(points) - 1 else course_last
        course_last = course
        send(pos[0], pos[1], course, speed_kmh)
        ticks += 1
        time.sleep(1)
    print("done", ticks, "s", pos)
    sys.exit(0)

mps = speed_kmh / 3.6
for i in range(steps):
    send(lat, lon, course, speed_kmh)
    dlat = mps * math.cos(math.radians(course)) / 111320.0
    dlon = mps * math.sin(math.radians(course)) / (111320.0 * math.cos(math.radians(lat)))
    lat += dlat; lon += dlon
    time.sleep(1)
print("done", lat, lon)
