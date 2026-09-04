r"""Stamp mountain ranges into an Emberfall map.

    python tools\carve_mountains.py godot\maps\greyfen_expanse.txt --seed 3

WHY RANGES AND NOT RIDGES
-------------------------
world.gd sizes each rock tile by how deep inside the rock body it sits, so the
fringe stays low and the core rears up. That only produces a mountain if the
body is THICK. Every existing map draws rock as one-tile lines — "######" — and
a one-tile line is depth 1 everywhere, which is a wall, not a massif. So this
lays down blobs several tiles thick with ragged edges, which the renderer then
reads as foothills climbing to a peak.

Ranges are placed like rivers and obey the same rules: never over ember, ruins,
water, fords or near a start pad, and the map must still be connected
afterwards — a range across a choke point can seal off a base as effectively as
an uncrossable river, so the flood fill runs and the file is not written if it
fails. Rock is impassable, and unlike a river it has no ford to soften it.
"""
import argparse
import math
import os
import random
import sys
from collections import deque

ROCK = "#"
CARVEABLE = set(".,")
PROTECTED = set("EBRCW1234~f")
WALKABLE = set(".,Ef1234")


def read_map(path):
    with open(path, "r", encoding="utf-8") as fh:
        rows = [ln.rstrip("\n") for ln in fh if ln.strip()]
    width = max(len(r) for r in rows)
    return [list(r.ljust(width, ".")) for r in rows]


def starts_of(g):
    out = {}
    for y, row in enumerate(g):
        for x, ch in enumerate(row):
            if ch in "1234":
                out[ch] = (x, y)
    return out


def connected(g, starts):
    if not starts:
        return True, "no starts"
    h, w = len(g), len(g[0])
    src = list(starts.values())[0]
    seen = {src}
    q = deque([src])
    while q:
        x, y = q.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h and (nx, ny) not in seen \
                    and g[ny][nx] in WALKABLE:
                seen.add((nx, ny))
                q.append((nx, ny))
    missing = [k for k, p in starts.items() if p not in seen]
    return not missing, ("unreachable starts: %s" % missing if missing else "ok")


def open_fraction(g):
    tot = sum(len(r) for r in g)
    return sum(sum(1 for c in r if c in WALKABLE) for r in g) / float(tot)


def stamp_range(g, rng, st, clear_radius, thickness, length_frac):
    """One ragged range: a wandering spine swollen to a few tiles either side."""
    h, w = len(g), len(g[0])
    horizontal = rng.random() < 0.5
    span = w if horizontal else h
    cross = h if horizontal else w
    n = max(6, int(span * length_frac))
    i0 = rng.randint(0, max(0, span - n - 1))
    base = cross * rng.uniform(0.2, 0.8)
    ph = rng.uniform(0, 6.28)
    amp = cross * rng.uniform(0.04, 0.12)

    def near_start(x, y):
        return any((x - sx) ** 2 + (y - sy) ** 2 < clear_radius ** 2
                   for sx, sy in st.values())

    placed = 0
    for k in range(n):
        t = k / float(n - 1)
        c = base + amp * math.sin(t * 4.2 + ph) + amp * 0.45 * math.sin(t * 9.7)
        # taper the ends so a range fades into the ground instead of stopping dead
        taper = math.sin(math.pi * t) ** 0.55
        half = thickness * taper * rng.uniform(0.82, 1.18)
        r = int(round(half))
        for d in range(-r, r + 1):
            # ragged edge: the outermost tile of each rib drops out half the time
            if abs(d) == r and rng.random() < 0.5:
                continue
            x, y = (i0 + k, int(round(c + d))) if horizontal \
                else (int(round(c + d)), i0 + k)
            if not (0 <= x < w and 0 <= y < h):
                continue
            if g[y][x] not in CARVEABLE or g[y][x] in PROTECTED:
                continue
            if near_start(x, y):
                continue
            g[y][x] = ROCK
            placed += 1
    return placed


def carve(path_file, seed=1, ranges=3, thickness=3.2, clear_radius=13,
          length_frac=0.42, dry=False):
    g = read_map(path_file)
    rng = random.Random(seed)
    st = starts_of(g)
    before = open_fraction(g)
    snapshot = [row[:] for row in g]

    placed = 0
    for _ in range(ranges):
        # each range is tried on its own and rolled back if it seals the map,
        # so one bad placement does not cost the whole carve
        trial = [row[:] for row in g]
        got = stamp_range(trial, rng, st, clear_radius, thickness, length_frac)
        ok, _why = connected(trial, st)
        if ok and got:
            g = trial
            placed += got

    ok, why = connected(g, st)
    if not ok:
        return False, "connectivity FAILED (%s)" % why
    after = open_fraction(g)
    if before - after > 0.18:
        g = snapshot
        return False, "would eat %.0f%% of the open ground - refused" % (
            (before - after) * 100.0)
    if not dry:
        with open(path_file, "w", encoding="utf-8") as fh:
            fh.write("\n".join("".join(r) for r in g) + "\n")
    rock = sum(r.count(ROCK) for r in g)
    return True, "rock=%d (+%d placed) open %.1f%% -> %.1f%% | %s" % (
        rock, placed, before * 100.0, after * 100.0, why)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("maps", nargs="+")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--ranges", type=int, default=3)
    ap.add_argument("--thickness", type=float, default=3.2)
    ap.add_argument("--dry", action="store_true")
    a = ap.parse_args()
    rc = 0
    for i, m in enumerate(a.maps):
        ok, msg = carve(m, seed=a.seed + i * 11, ranges=a.ranges,
                        thickness=a.thickness, dry=a.dry)
        print("%-28s %s %s" % (os.path.basename(m), "OK " if ok else "SKIP", msg))
        if not ok:
            rc = 1
    sys.exit(rc)
