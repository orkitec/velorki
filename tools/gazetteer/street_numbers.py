"""House numbers along a street: the `street_numbers.data` blob.

build.py and merge.py write it, check.py, testset.py and query.py read it.
Standard library only, because merge.py must run without pyosmium.

A street's addresses are split by parity, odd numbers first, and each side is
thinned to the points a reader needs: the first and the last, and between two
kept points only those that interpolation by number would put more than
HOUSE_TOLERANCE_M from where they really are. The blob is

    byte 0           format version, 1
    odd run          varint(count), then count points
    even run         varint(count), then count points
    point            varint(number - previous number)   previous starts at 0 per run
                     zigzag(lat_q - cursor lat)          cursor starts at (0, 0) once
                     zigzag(lon_q - cursor lon)          per blob; it is the last point

with lat_q / lon_q in 1e-5 degrees. See README.md, "Schema".
"""

from __future__ import annotations

import bisect
import math

BLOB_VERSION = 1

# How far an interpolated number may land from the address it stands for.
HOUSE_TOLERANCE_M = 20.0

# Blob coordinates are integers in 1e-5 degrees, about a metre.
POINT_SCALE = 1e5

METERS_PER_DEG_LAT = 111320.0

# (number, lat_q, lon_q): one point of a side, coordinates in 1e-5 degrees.
Point = tuple[int, int, int]


def meters_between(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Flat-earth distance. Good enough over the few km these lookups span."""
    dlat = (lat1 - lat2) * METERS_PER_DEG_LAT
    dlon = (lon1 - lon2) * METERS_PER_DEG_LAT * math.cos(math.radians(lat1))
    return math.hypot(dlat, dlon)


# ---------------------------------------------------------------- varints ---


def zigzag(value: int) -> int:
    """0, -1, 1, -2, 2 -> 0, 1, 2, 3, 4 (64-bit signed)."""
    return ((value << 1) ^ (value >> 63)) & 0xFFFFFFFFFFFFFFFF


def unzigzag(value: int) -> int:
    return (value >> 1) ^ -(value & 1)


def write_varint(out: bytearray, value: int) -> None:
    """Unsigned LEB128: seven bits a byte, low group first."""
    if value < 0:
        raise ValueError(f"varint of a negative number: {value}")
    while value >= 0x80:
        out.append((value & 0x7F) | 0x80)
        value >>= 7
    out.append(value)


def read_varint(data: bytes, pos: int) -> tuple[int, int]:
    """The varint at `pos` and the position after it; ValueError if cut off."""
    value = 0
    shift = 0
    while True:
        if pos >= len(data):
            raise ValueError("blob ends inside a varint")
        if shift > 63:
            raise ValueError("varint longer than 64 bits")
        byte = data[pos]
        pos += 1
        value |= (byte & 0x7F) << shift
        if byte < 0x80:
            return value, pos
        shift += 7


# --------------------------------------------------------------- the blob ---


def encode(odd: list[Point], even: list[Point]) -> bytes:
    """Both sides as one blob; each side sorted by number, numbers unique."""
    out = bytearray([BLOB_VERSION])
    cursor_lat = cursor_lon = 0
    for run in (odd, even):
        write_varint(out, len(run))
        previous = 0
        for index, (number, lat, lon) in enumerate(run):
            if number < previous or (index > 0 and number == previous):
                raise ValueError(f"numbers not ascending: {previous}, {number}")
            write_varint(out, number - previous)
            write_varint(out, zigzag(lat - cursor_lat))
            write_varint(out, zigzag(lon - cursor_lon))
            previous = number
            cursor_lat, cursor_lon = lat, lon
    return bytes(out)


def decode(blob: bytes) -> tuple[list[Point], list[Point]]:
    """(odd, even) out of a blob, or ValueError if it is not a valid one."""
    if not blob or blob[0] != BLOB_VERSION:
        raise ValueError(f"blob version {blob[0] if blob else None}, expected 1")
    pos = 1
    cursor_lat = cursor_lon = 0
    runs: list[list[Point]] = []
    for parity in (1, 0):
        count, pos = read_varint(blob, pos)
        run: list[Point] = []
        number = 0
        for index in range(count):
            delta, pos = read_varint(blob, pos)
            if index > 0 and delta == 0:
                raise ValueError(f"number {number} repeated")
            number += delta
            if number % 2 != parity:
                side = "odd" if parity else "even"
                raise ValueError(f"number {number} in the {side} run")
            dlat, pos = read_varint(blob, pos)
            dlon, pos = read_varint(blob, pos)
            cursor_lat += unzigzag(dlat)
            cursor_lon += unzigzag(dlon)
            run.append((number, cursor_lat, cursor_lon))
        runs.append(run)
    if pos != len(blob):
        raise ValueError(f"{len(blob) - pos} trailing byte(s)")
    return runs[0], runs[1]


# --------------------------------------------------------------- thinning ---


def thin(
    side: list[Point], truth: list[tuple[float, float]] | None = None
) -> list[Point]:
    """The points of one side a reader needs to stay within HOUSE_TOLERANCE_M.

    Douglas-Peucker over the number axis: the first and the last point always
    stay; between two kept points, the skipped point furthest from where
    interpolation by number between them puts it is kept if that is more than
    the tolerance, and both halves are looked at again. `truth` is where each
    point really is, in degrees (build.py has the addresses' own coordinates);
    without it the points' own positions are the truth. Interpolation always
    runs between the kept points' stored positions, because that is what the
    app does. A stack, not recursion: a long road has thousands of numbers.
    """
    count = len(side)
    if count <= 2:
        return list(side)
    if truth is None:
        truth = [(lat / POINT_SCALE, lon / POINT_SCALE) for _, lat, lon in side]
    keep = [False] * count
    keep[0] = keep[-1] = True
    stack = [(0, count - 1)]
    while stack:
        first, last = stack.pop()
        if last - first < 2:
            continue
        n0, lat0, lon0 = side[first]
        n1, lat1, lon1 = side[last]
        span = n1 - n0
        worst = -1.0
        worst_index = -1
        for index in range(first + 1, last):
            share = (side[index][0] - n0) / span
            lat = (lat0 + (lat1 - lat0) * share) / POINT_SCALE
            lon = (lon0 + (lon1 - lon0) * share) / POINT_SCALE
            true_lat, true_lon = truth[index]
            distance = meters_between(true_lat, true_lon, lat, lon)
            if distance > worst:
                worst = distance
                worst_index = index
        if worst > HOUSE_TOLERANCE_M:
            keep[worst_index] = True
            stack.append((worst_index, last))
            stack.append((first, worst_index))
    return [point for point, kept in zip(side, keep) if kept]


def split(points: list[Point]) -> tuple[list[Point], list[Point]]:
    """(odd, even), each sorted by number. Numbers must already be unique."""
    ordered = sorted(points)
    return (
        [p for p in ordered if p[0] % 2 == 1],
        [p for p in ordered if p[0] % 2 == 0],
    )


def thinned_blob(entries: list[tuple[int, int, int]], coord_scale: float) -> bytes:
    """One street's blob from its unique (number, lat, lon) addresses.

    The coordinates are integers in 1 / `coord_scale` degrees: 1e7 for
    build.py's addresses, 1e5 for points merge.py read out of a blob.
    """
    factor = coord_scale / POINT_SCALE
    sides = []
    for side in split(list(entries)):
        points = [
            (number, int(round(lat / factor)), int(round(lon / factor)))
            for number, lat, lon in side
        ]
        truth = [(lat / coord_scale, lon / coord_scale) for _, lat, lon in side]
        sides.append(thin(points, truth))
    return encode(sides[0], sides[1])


# ---------------------------------------------------------------- reading ---


def locate(
    odd: list[Point], even: list[Point], number: int
) -> tuple[float, float, bool] | None:
    """Where `number` is, in degrees, and whether that counts as exact.

    Between the first and the last point of its own side it is interpolated
    by number and exact (within HOUSE_TOLERANCE_M). Past either end, or on a
    side with no points, it is the nearest end point by number and
    approximate. None when the street has no points at all.
    """
    side = odd if number % 2 else even
    if side and side[0][0] <= number <= side[-1][0]:
        index = bisect.bisect_left(side, (number,))
        n1, lat1, lon1 = side[index]
        if n1 == number:
            return lat1 / POINT_SCALE, lon1 / POINT_SCALE, True
        n0, lat0, lon0 = side[index - 1]
        share = (number - n0) / (n1 - n0)
        return (
            (lat0 + (lat1 - lat0) * share) / POINT_SCALE,
            (lon0 + (lon1 - lon0) * share) / POINT_SCALE,
            True,
        )
    if not side:
        side = even if number % 2 else odd
    if not side:
        return None
    first, last = side[0], side[-1]
    nearest = first if abs(first[0] - number) <= abs(last[0] - number) else last
    return nearest[1] / POINT_SCALE, nearest[2] / POINT_SCALE, False
