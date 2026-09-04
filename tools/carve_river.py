r"""Carve a meandering river, with fords, into an Emberfall map.

    python tools\carve_river.py godot\maps\greyfen_expanse.txt --seed 4

WHY FORDS ARE NOT OPTIONAL
--------------------------
A river spanning a map divides it. Ground units path on walkable tiles only, so
an uncrossable channel does not make the map interesting, it makes half of it
unreachable — the AI simply never attacks, and a 2v2 becomes two 1v0s. Every
carve therefore lays down 'f' (Ford: shallow, walkable) crossings and then
PROVES the map is still connected by flood-filling from one start to the others.
If that check fails the file is not written.

Rivers refuse to touch anything load-bearing: ember fields, ruins, walls,
refineries and a generous radius around every start pad. A river through a
player's build space would be a map bug, not a feature.
"""
import argparse
import math
import os
import random
import sys
from collections import deque

WATER, FORD = "~", "f"
BANK = ","
CARVEABLE = set(".,")             # never carve ember, ruins, walls or rock
PROTECTED = set("EBRCW1234")
# must match TILE_DEFS walk=true in world.gd. The digits belong here because
# world.gd's parser rewrites a start marker to "." as it reads the map — leave
# them out and every start is unreachable by construction, which reads as a
# connectivity failure the carve did not actually cause.
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
    """Flood fill from the first start; every other start must be reachable."""
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


def river_path(w, h, rng, vertical, meander, bow):
    """A course down (or across) the map: a slow bow plus two wobbles."""
    span, cross = (h, w) if vertical else (w, h)
    base = cross * rng.uniform(0.34, 0.66)
    ph1, ph2 = rng.uniform(0, 6.28), rng.uniform(0, 6.28)
    pts = []
    for i in range(span):
        t = i / float(span - 1)
        off = (bow * cross * math.sin(math.pi * t)
               + meander * cross * 0.5 * math.sin(t * 5.1 + ph1)
               + meander * cross * 0.28 * math.sin(t * 11.3 + ph2))
        c = int(round(base + off))
        pts.append((c, i) if vertical else (i, c))
    return pts


def carve(path_file, seed=1, width=3.0, fords=3, vertical=None,
          clear_radius=11, dry=False):
    g = read_map(path_file)
    h, w = len(g), len(g[0])
    rng = random.Random(seed)
    st = starts_of(g)
    if vertical is None:
        vertical = w >= h          # cut across the long axis
    pts = river_path(w, h, rng, vertical, meander=rng.uniform(0.05, 0.09),
                     bow=rng.uniform(-0.10, 0.10))

    def too_near_start(x, y):
        return any((x - sx) ** 2 + (y - sy) ** 2 < clear_radius ** 2
                   for sx, sy in st.values())

    # width breathes along the course so the channel is not a corridor
    cells = {}
    for i, (cx, cy) in enumerate(pts):
        t = i / float(len(pts) - 1)
        half = max(1.0, width * (0.72 + 0.5 * abs(math.sin(t * 7.3 + seed))))
        r = int(round(half))
        for d in range(-r, r + 1):
            x, y = (cx + d, cy) if vertical else (cx, cy + d)
            if not (0 <= x < w and 0 <= y < h):
                continue
            if g[y][x] in PROTECTED or too_near_start(x, y):
                continue
            if g[y][x] not in CARVEABLE:
                continue
            cells[(x, y)] = i          # remember position along the course

    if not cells:
        return False, "nothing carveable", None

    for (x, y) in cells:
        g[y][x] = WATER

    # FORDS: evenly spaced along the course, each a band a few tiles long.
    n = len(pts)
    ford_at = [int(n * (k + 1) / float(fords + 1)) for k in range(fords)]
    for centre in ford_at:
        for (x, y), i in cells.items():
            if abs(i - centre) <= 2:
                g[y][x] = FORD

    # BANKS: soften the edge so the channel does not read as a stamped trench
    for (x, y) in list(cells):
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and g[ny][nx] == ".":
                    if rng.random() < 0.55:
                        g[ny][nx] = BANK

    ok, why = connected(g, st)
    if not ok:
        return False, "connectivity FAILED (%s)" % why, None
    text = "\n".join("".join(r) for r in g) + "\n"
    if not dry:
        with open(path_file, "w", encoding="utf-8") as fh:
            fh.write(text)
    water = sum(r.count(WATER) for r in g)
    ford = sum(r.count(FORD) for r in g)
    return True, "water=%d ford=%d (%s) %s" % (
        water, ford, "N-S" if vertical else "E-W", why), (water, ford)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("maps", nargs="+")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--width", type=float, default=3.0)
    ap.add_argument("--fords", type=int, default=3)
    ap.add_argument("--dry", action="store_true")
    a = ap.parse_args()
    rc = 0
    for i, m in enumerate(a.maps):
        ok, msg, _ = carve(m, seed=a.seed + i * 7, width=a.width,
                           fords=a.fords, dry=a.dry)
        print("%-28s %s %s" % (os.path.basename(m), "OK " if ok else "SKIP", msg))
        if not ok:
            rc = 1
    sys.exit(rc)
