"""
EMBERFALL: 1940 — world.py
The map: loads a text file of tile characters, pre-renders the terrain once
onto one big Surface (fast!), and draws the visible slice each frame.

Key idea for this phase: PRE-RENDERING. Drawing 3,072 tiles every frame is
wasteful when the ground never changes — so we paint the whole map onto a
single big image at load time, then each frame just copy the rectangle the
camera is looking at. The only things drawn per-frame are the parts that
move or glow (emberstone, flags).
"""

import math
import pygame
from settings import *

# What each map character means. walk/build matter from Phase 2 onward,
# but defining them now keeps the map format complete.
TILE_DEFS = {
    ".": dict(name="Ashen Ground",     walk=True,  build=True,  color=(97, 94, 85)),
    ",": dict(name="Cratered Rough",   walk=True,  build=False, color=(80, 76, 68)),
    "#": dict(name="Rock & Ruin",      walk=False, build=False, color=(54, 52, 56)),
    "~": dict(name="Flooded Trench",   walk=False, build=False, color=(40, 60, 68)),
    "E": dict(name="Emberstone Field", walk=True,  build=False, color=(70, 56, 50)),
}
START_CHARS = "1234"


def tile_hash(x, y, salt=0):
    """Deterministic 'randomness' per tile — the same tile always gets the
    same pebbles/cracks, with no random module and no stored data."""
    n = (x * 73856093) ^ (y * 19349663) ^ (salt * 83492791)
    return n & 0x7FFFFFFF


def _shade(color, delta):
    """Lighten (+) or darken (-) a color, safely clamped to 0..255."""
    return tuple(max(0, min(255, c + delta)) for c in color)


def _lerp3(a, b, f):
    """Blend between two colors: f=0 gives a, f=1 gives b."""
    return tuple(int(a[i] + (b[i] - a[i]) * f) for i in range(3))


class World:
    def __init__(self, path):
        self.grid = []          # grid[y][x] -> tile character
        self.starts = {}        # start number -> (tile_x, tile_y)
        self._load(path)
        self.w = len(self.grid[0])
        self.h = len(self.grid)
        self.px_w = self.w * TILE
        self.px_h = self.h * TILE
        self.static = self._bake_terrain()
        self.embers = self._collect_embers()

    # --- loading ------------------------------------------------------------

    def _load(self, path):
        with open(path, encoding="utf-8") as f:
            lines = [ln.rstrip("\n") for ln in f if ln.strip() != ""]
        width = len(lines[0])
        for y, line in enumerate(lines):
            if len(line) != width:
                raise ValueError(f"Map row {y} is {len(line)} chars wide, expected {width}")
            row = []
            for x, ch in enumerate(line):
                if ch in START_CHARS:
                    self.starts[int(ch)] = (x, y)
                    ch = "."                      # the ground under an HQ is ground
                if ch not in TILE_DEFS:
                    raise ValueError(f"Unknown tile character {ch!r} at ({x},{y})")
                row.append(ch)
            self.grid.append(row)

    # --- helpers (used heavily from Phase 2 on) ------------------------------

    def in_bounds(self, tx, ty):
        return 0 <= tx < self.w and 0 <= ty < self.h

    def tile_at(self, tx, ty):
        return self.grid[ty][tx]

    def is_walkable(self, tx, ty):
        return self.in_bounds(tx, ty) and TILE_DEFS[self.grid[ty][tx]]["walk"]

    def is_buildable(self, tx, ty):
        return self.in_bounds(tx, ty) and TILE_DEFS[self.grid[ty][tx]]["build"]

    # --- pre-rendering the terrain -------------------------------------------

    def _bake_terrain(self):
        surf = pygame.Surface((self.px_w, self.px_h))
        for ty in range(self.h):
            for tx in range(self.w):
                ch = self.grid[ty][tx]
                base = TILE_DEFS[ch]["color"]
                h = tile_hash(tx, ty)
                px, py = tx * TILE, ty * TILE

                # Every tile gets a slight brightness jitter so the ground
                # doesn't look like flat plastic.
                jitter = (h % 13) - 6 if ch != "~" else (h % 7) - 3
                pygame.draw.rect(surf, _shade(base, jitter), (px, py, TILE, TILE))

                if ch == "." and h % 7 == 0:      # occasional pebble
                    dx, dy = 4 + h % 24, 4 + (h >> 4) % 24
                    pygame.draw.rect(surf, _shade(base, -16), (px + dx, py + dy, 2, 2))

                elif ch == ",":                   # crater pocks
                    for i in range(2 + h % 2):
                        hh = tile_hash(tx, ty, i + 1)
                        cx, cy = 5 + hh % 22, 5 + (hh >> 5) % 22
                        pygame.draw.circle(surf, _shade(base, -18), (px + cx, py + cy), 3)
                        pygame.draw.circle(surf, _shade(base, +10), (px + cx - 1, py + cy - 1), 1)

                elif ch == "#":                   # ridge lines + bottom shadow
                    hh = tile_hash(tx, ty, 2)
                    x1, y1 = px + 5 + hh % 8, py + 9 + (hh >> 3) % 6
                    pygame.draw.line(surf, _shade(base, +22), (x1, y1), (x1 + 14, y1 - 3), 2)
                    pygame.draw.line(surf, _shade(base, -20), (x1 + 2, y1 + 5), (x1 + 16, y1 + 2), 1)
                    pygame.draw.rect(surf, _shade(base, -18), (px, py + TILE - 3, TILE, 3))

                elif ch == "~":                   # still-water ripples
                    for i in range(2):
                        ry = py + 6 + (tile_hash(tx, ty, i + 3) % 20)
                        pygame.draw.line(surf, _shade(base, +12), (px + 4, ry), (px + 27, ry), 1)

                elif ch == "E":                   # scorched cracks under the stones
                    hh = tile_hash(tx, ty, 4)
                    cx, cy = px + 6 + hh % 16, py + 6 + (hh >> 4) % 16
                    pygame.draw.line(surf, _shade(base, -22), (cx, cy), (cx + 8, cy + 5), 1)
                    pygame.draw.line(surf, _shade(base, -22), (cx + 3, cy + 6), (cx + 7, cy - 3), 1)
        return surf.convert()

    def _collect_embers(self):
        """Precompute glowing stone positions for every emberstone tile."""
        embers = []
        for ty in range(self.h):
            for tx in range(self.w):
                if self.grid[ty][tx] != "E":
                    continue
                stones = []
                for i in range(3):
                    h = tile_hash(tx, ty, 10 + i)
                    stones.append((5 + h % 21, 5 + (h >> 5) % 21, 2 + (h >> 10) % 2))
                phase = (tile_hash(tx, ty, 99) % 628) / 100.0   # 0 .. 2π
                embers.append((tx, ty, phase, stones))
        return embers

    # --- per-frame drawing ----------------------------------------------------

    def draw(self, screen, cam, t):
        # 1) the pre-rendered ground: copy just the camera's rectangle
        src = pygame.Rect(int(cam.x), int(cam.y), VIEW_W, VIEW_H)
        screen.blit(self.static, (0, 0), src)

        # 2) pulsing emberstone (the living part of the terrain)
        for tx, ty, phase, stones in self.embers:
            sx = tx * TILE - int(cam.x)
            sy = ty * TILE - int(cam.y)
            if sx < -TILE or sx > VIEW_W or sy < -TILE or sy > VIEW_H:
                continue                          # off-screen: skip (culling)
            pulse = 0.5 + 0.5 * math.sin(t * 2.4 + phase)
            halo = _lerp3((96, 52, 30), (150, 86, 40), pulse)
            core = _lerp3((198, 96, 40), (255, 180, 74), pulse)
            for ox, oy, r in stones:
                pygame.draw.circle(screen, halo, (sx + ox, sy + oy), r + 2)
                pygame.draw.circle(screen, core, (sx + ox, sy + oy), r)

    def draw_starts(self, screen, cam, t, font):
        """Faction base pads at the start positions (visual markers in Phase 1 —
        they become real Command Post buildings in Phase 4)."""
        for num, (sx, sy) in self.starts.items():
            fac = FACTIONS[START_FACTIONS.get(num, "karvath")]
            px = (sx - 1) * TILE - int(cam.x)     # pad is 3x3 tiles, start = center
            py = (sy - 1) * TILE - int(cam.y)
            size = TILE * 3
            if px < -size or px > VIEW_W or py < -size or py > VIEW_H:
                continue

            pygame.draw.rect(screen, (45, 47, 52), (px, py, size, size))
            pygame.draw.rect(screen, fac["color"], (px, py, size, size), 2)
            pygame.draw.rect(screen, (26, 27, 30), (px + 6, py + 6, size - 12, size - 12), 1)
            for rx, ry in ((4, 4), (size - 6, 4), (4, size - 6), (size - 6, size - 6)):
                pygame.draw.circle(screen, (116, 122, 130), (px + rx, py + ry), 2)

            # flag with a gentle wave
            pole_x, pole_y = px + size - 14, py - 22
            pygame.draw.line(screen, (150, 150, 150), (pole_x, pole_y), (pole_x, py + 6), 2)
            wave = math.sin(t * 3.0 + num) * 2
            pygame.draw.polygon(screen, fac["color"], [
                (pole_x, pole_y),
                (pole_x + 18, pole_y + 4 + wave),
                (pole_x, pole_y + 9),
            ])

            label = fac["name"].split()[0].upper()
            text = font.render(label, True, (230, 228, 222))
            shadow = font.render(label, True, (10, 10, 10))
            tx_pos = px + size // 2 - text.get_width() // 2
            screen.blit(shadow, (tx_pos + 1, py + size + 5))
            screen.blit(text, (tx_pos, py + size + 4))
