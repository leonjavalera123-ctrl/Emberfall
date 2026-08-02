"""
EMBERFALL: 1940 — main.py
Entry point: pygame setup, the game loop, and event routing.

Run it:            python main.py
Dev screenshot:    python main.py --selftest [out.png]
                   (renders a few frames, saves a screenshot, exits —
                   lets Claude or you verify a build without playing)
"""

import os
import sys
import pygame
from settings import *
from world import World, TILE_DEFS
from camera import Camera
from ui import Sidebar

BASE_DIR = os.path.dirname(os.path.abspath(__file__))


def main():
    selftest = "--selftest" in sys.argv
    shot_path = os.path.join(BASE_DIR, "phase1_selftest.png")
    if selftest:
        i = sys.argv.index("--selftest")
        if i + 1 < len(sys.argv):
            shot_path = sys.argv[i + 1]

    pygame.init()
    screen = pygame.display.set_mode((WINDOW_W, WINDOW_H))
    pygame.display.set_caption("EMBERFALL: 1940 — Phase 1: Foundation")
    clock = pygame.time.Clock()

    world = World(os.path.join(BASE_DIR, "maps", "cradle_gate.txt"))
    cam = Camera(world)
    sidebar = Sidebar(world)

    # Open on your headquarters, like any commander would.
    if 1 in world.starts:
        sx, sy = world.starts[1]
        cam.center_on(sx * TILE + TILE // 2, sy * TILE + TILE // 2)

    frames = 0
    running = True
    while running:
        # dt = seconds since last frame (capped so a lag spike can't teleport things)
        dt = min(clock.tick(FPS_CAP) / 1000.0, 0.05)
        t = pygame.time.get_ticks() / 1000.0

        for ev in pygame.event.get():
            if ev.type == pygame.QUIT:
                running = False
            sidebar.handle_event(ev, cam)

        if not selftest:
            cam.update(dt)

        # What tile is the mouse surveying?
        hover = None
        mx, my = pygame.mouse.get_pos()
        if mx < VIEW_W and pygame.mouse.get_focused():
            wx, wy = cam.screen_to_world(mx, my)
            tx, ty = int(wx // TILE), int(wy // TILE)
            if world.in_bounds(tx, ty):
                hover = (TILE_DEFS[world.tile_at(tx, ty)]["name"], tx, ty)

        world.draw(screen, cam, t)
        world.draw_starts(screen, cam, t, sidebar.font_small)
        sidebar.draw(screen, cam, hover, clock.get_fps())
        pygame.display.flip()

        frames += 1
        if selftest and frames >= 8:
            pygame.image.save(screen, shot_path)
            print(f"selftest screenshot -> {shot_path}")
            running = False

    pygame.quit()


if __name__ == "__main__":
    main()
