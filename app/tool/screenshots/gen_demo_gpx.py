#!/usr/bin/env python3
"""Generate the demo GPX files for the website screenshots.

A plausible ~25 km loop around Funchal, Madeira: the Avenida do Mar and the
Estrada Monumental west along the coast to Praia Formosa and Camara de Lobos,
up the ER229 to Estreito de Camara de Lobos, east along the Santo Antonio /
Sao Roque shelf to Monte, then back down into Funchal. Anchor coordinates
follow the real road geometry closely enough to sit on the map.
"""
import datetime as dt, math, os, sys

ANCHORS = [
    # lat, lon, elevation (m)
    (32.6465, -16.9075, 5),    # Avenida do Mar, Praca do Povo
    (32.6455, -16.9110, 6),    # Marina do Funchal
    (32.6448, -16.9160, 9),    # Avenida do Mar, below the cathedral
    (32.6440, -16.9205, 18),   # Avenida do Infante
    (32.6430, -16.9255, 26),   # Estrada Monumental, the Casino
    (32.6416, -16.9305, 22),   # Lido
    (32.6404, -16.9358, 26),   # Ponta Gorda
    (32.6396, -16.9412, 10),   # Praia Formosa
    (32.6392, -16.9468, 14),   # Sao Martinho seafront
    (32.6382, -16.9518, 22),   # Ponta da Cruz
    (32.6402, -16.9556, 58),   # climb out of Formosa
    (32.6438, -16.9602, 82),   # Ribeira dos Socorridos
    (32.6470, -16.9648, 66),   # Socorridos viaduct
    (32.6486, -16.9706, 52),   # into Camara de Lobos
    (32.6500, -16.9762, 12),   # Camara de Lobos harbour
    (32.6522, -16.9788, 66),   # Camara de Lobos, up the ER229
    (32.6558, -16.9802, 168),  # first switchbacks
    (32.6592, -16.9788, 262),  # Ribeira da Caixa
    (32.6628, -16.9766, 352),  # terraced vineyards
    (32.6662, -16.9736, 438),  # Estreito outskirts
    (32.6682, -16.9700, 486),  # Estreito de Camara de Lobos
    (32.6722, -16.9742, 596),  # up towards Jardim da Serra
    (32.6764, -16.9782, 672),  # Jardim da Serra
    (32.6812, -16.9784, 726),  # Lombada, the top of the loop
    (32.6796, -16.9716, 704),  # the high road east
    (32.6788, -16.9636, 688),  # Corujeira
    (32.6752, -16.9592, 606),  # dropping back to the shelf
    (32.6716, -16.9572, 524),  # Vale Paraiso
    (32.6722, -16.9496, 492),  # Santo Antonio, west end
    (32.6708, -16.9424, 428),  # Santo Antonio
    (32.6694, -16.9356, 388),  # Sao Roque
    (32.6690, -16.9282, 402),  # Levada dos Tornos
    (32.6704, -16.9206, 452),  # Caminho do Monte
    (32.6722, -16.9134, 548),  # Monte, Nossa Senhora do Monte
    (32.6738, -16.9042, 542),  # Curral dos Romeiros
    (32.6700, -16.8962, 528),  # the Levada dos Tornos east
    (32.6644, -16.8908, 494),  # Palheiro Ferreiro
    (32.6592, -16.8876, 374),  # descending the Caminho do Palheiro
    (32.6534, -16.8878, 212),  # Sao Goncalo
    (32.6486, -16.8856, 96),   # Caminho do Lazareto
    (32.6448, -16.8878, 24),   # the Lazareto shore
    (32.6440, -16.8942, 14),   # Praia de Sao Goncalo
    (32.6452, -16.8998, 12),   # Praia do Almirante Reis
    (32.6463, -16.9042, 7),    # Zona Velha, the promenade
    (32.6465, -16.9075, 5),    # the loop closes
]

R = 6371000.0


def haversine(a, b):
    la1, lo1, la2, lo2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    h = (math.sin((la2 - la1) / 2) ** 2
         + math.cos(la1) * math.cos(la2) * math.sin((lo2 - lo1) / 2) ** 2)
    return 2 * R * math.asin(math.sqrt(h))


def resample(anchors, count):
    """`count` points spread evenly along the anchor polyline."""
    segs = [haversine(anchors[i], anchors[i + 1]) for i in range(len(anchors) - 1)]
    total = sum(segs)
    step = total / (count - 1)
    out = [anchors[0]]
    seg, walked = 0, 0.0
    for i in range(1, count - 1):
        target = i * step
        while seg < len(segs) - 1 and walked + segs[seg] < target:
            walked += segs[seg]
            seg += 1
        f = (target - walked) / segs[seg] if segs[seg] else 0.0
        a, b = anchors[seg], anchors[seg + 1]
        out.append((a[0] + (b[0] - a[0]) * f,
                    a[1] + (b[1] - a[1]) * f,
                    a[2] + (b[2] - a[2]) * f))
    out.append(anchors[-1])
    return out, total


def speed_for(grade):
    """A rider's speed in m/s for a grade, so the ride stats look real."""
    if grade > 0.08:
        return 2.2
    if grade > 0.04:
        return 3.2
    if grade > 0.01:
        return 4.6
    if grade < -0.05:
        return 10.5
    if grade < -0.01:
        return 8.5
    return 6.4


def ride(anchors, step_s):
    """The loop ridden, as a fix every `step_s` seconds.

    A recorded track is sampled in time, not in distance, and the app measures
    an imported ride with the same rules as a recorded one: a gap of more than
    `statsPauseGap` (30 s) between two fixes counts as a break and contributes
    neither distance nor moving time (app/lib/core/geo/ride_stats.dart). A
    track sampled every N metres therefore loses every slow climb; sampling in
    time keeps every fix well inside the window.
    """
    dense, total = resample(anchors, 2400)
    # Time at each dense point, integrating the grade-dependent speed.
    times = [0.0]
    for i in range(1, len(dense)):
        d = haversine(dense[i - 1], dense[i])
        grade = (dense[i][2] - dense[i - 1][2]) / d if d > 0.5 else 0.0
        times.append(times[-1] + d / speed_for(grade))
    out, i = [], 0
    t = 0.0
    while t <= times[-1]:
        while i < len(times) - 2 and times[i + 1] < t:
            i += 1
        span = times[i + 1] - times[i]
        f = (t - times[i]) / span if span else 0.0
        a, b = dense[i], dense[i + 1]
        out.append((a[0] + (b[0] - a[0]) * f,
                    a[1] + (b[1] - a[1]) * f,
                    a[2] + (b[2] - a[2]) * f, t))
        t += step_s
    out.append((dense[-1][0], dense[-1][1], dense[-1][2], times[-1]))
    return out, total, times[-1]


def header(name, desc):
    return (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<gpx version="1.1" creator="Velorki screenshots" '
        'xmlns="http://www.topografix.com/GPX/1/1" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xsi:schemaLocation="http://www.topografix.com/GPX/1/1 '
        'http://www.topografix.com/GPX/1/1/gpx.xsd">\n'
        f'  <metadata>\n    <name>{name}</name>\n'
        f'    <desc>{desc}</desc>\n  </metadata>\n'
    )


def write_track(path, points, total, name="Funchal coast and Monte loop",
                start=dt.datetime(2026, 9, 13, 8, 12, 0, tzinfo=dt.timezone.utc),
                shape="loop"):
    rows = []
    for p in points:
        stamp = (start + dt.timedelta(seconds=round(p[3]))).strftime(
            "%Y-%m-%dT%H:%M:%SZ")
        rows.append(
            f'      <trkpt lat="{p[0]:.6f}" lon="{p[1]:.6f}">\n'
            f'        <ele>{p[2]:.1f}</ele>\n'
            f'        <time>{stamp}</time>\n'
            f'      </trkpt>\n'
        )
    body = (
        header(name, f"A {total/1000:.1f} km {shape} around Funchal, Madeira.")
        + f'  <trk>\n    <name>{name}</name>\n'
          '    <type>cycling</type>\n    <trkseg>\n'
        + "".join(rows)
        + '    </trkseg>\n  </trk>\n</gpx>\n'
    )
    open(path, "w").write(body)


def write_route(path, points, total,
                name="Funchal coast and Monte route", shape="loop"):
    rows = "".join(
        f'    <rtept lat="{p[0]:.6f}" lon="{p[1]:.6f}">\n'
        f'      <ele>{p[2]:.1f}</ele>\n'
        f'    </rtept>\n'
        for p in points
    )
    body = (
        header(name, f"A planned {total/1000:.1f} km {shape} around Funchal, Madeira.")
        + f'  <rte>\n    <name>{name}</name>\n'
        + '    <type>cycling</type>\n'
        + rows
        + '  </rte>\n</gpx>\n'
    )
    open(path, "w").write(body)


# A handful of shorter files so the library and the Record tab do not look
# like a fresh install in the screenshots. All of them are cut from the same
# anchor list, so they sit on the same roads as the main loop.
EXTRAS = [
    # file, name, kind, anchor slice, out and back?, ride date
    ("demo-formosa.gpx", "Praia Formosa and back", "rte", (0, 9), True, None),
    ("demo-levada.gpx", "Monte and the Levada dos Tornos", "rte", (25, 35), False, None),
    ("demo-seafront.gpx", "Evening seafront spin", "trk", (0, 8), True,
     dt.datetime(2026, 9, 10, 18, 5, 0, tzinfo=dt.timezone.utc)),
    ("demo-camara.gpx", "Camara de Lobos climb", "trk", (9, 21), False,
     dt.datetime(2026, 9, 6, 9, 30, 0, tzinfo=dt.timezone.utc)),
]


def write_extras(out):
    made = []
    for file, name, kind, (a, b), back, when in EXTRAS:
        anchors = ANCHORS[a:b]
        if back:
            anchors = anchors + list(reversed(anchors[:-1]))
        if kind == "rte":
            points, total = resample(anchors, 60)
            write_route(os.path.join(out, file), points, total, name, "ride")
        else:
            points, total, _ = ride(anchors, 10)
            write_track(os.path.join(out, file), points, total, name, when, "ride")
        made.append(f"{file}: {name}, {total/1000:.1f} km")
    return made


out = sys.argv[1] if len(sys.argv) > 1 else "."
# One fix every ten seconds, the way a phone records.
track, total, seconds = ride(ANCHORS, 10)
route, _ = resample(ANCHORS, 80)
shape, _ = resample(ANCHORS, 150)
write_track(os.path.join(out, "demo-loop.gpx"), track, total)
write_route(os.path.join(out, "demo-route.gpx"), route, total)
# One `lat,lon` per line for tool/emu_ride.py --path.
with open(os.path.join(out, "demo-loop.path"), "w") as fh:
    fh.write("# The demo loop as emu_ride.py --path input (lat,lon per line).\n")
    for p in shape:
        fh.write(f"{p[0]:.6f},{p[1]:.6f}\n")
print(f"demo-loop.gpx / demo-route.gpx: {total/1000:.2f} km, {len(track)} trkpts, "
      f"{seconds/3600:.2f} h moving, {len(route)} rtepts")
for line in write_extras(out):
    print(line)
