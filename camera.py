"""
EMBERFALL: 1940 — camera.py
The camera is just an (x, y) offset into the world, in pixels.
Everything drawn in the viewport subtracts it:  screen = world - camera.
"""

import pygame
from settings import *


class Camera:
    def __init__(self, world):
        self.x = 0.0
        self.y = 0.0
        # How far the camera may travel before the map edge shows.
        self.max_x = max(0, world.px_w - VIEW_W)
        self.max_y = max(0, world.px_h - VIEW_H)

    def update(self, dt):
        keys = pygame.key.get_pressed()
        dx = dy = 0
        if keys[pygame.K_a] or keys[pygame.K_LEFT]:
            dx -= 1
        if keys[pygame.K_d] or keys[pygame.K_RIGHT]:
            dx += 1
        if keys[pygame.K_w] or keys[pygame.K_UP]:
            dy -= 1
        if keys[pygame.K_s] or keys[pygame.K_DOWN]:
            dy += 1

        # Classic RTS edge scrolling — only while the window has the mouse.
        if pygame.mouse.get_focused():
            mx, my = pygame.mouse.get_pos()
            if mx < EDGE_MARGIN:
                dx -= 1
            elif mx > WINDOW_W - EDGE_MARGIN:
                dx += 1
            if my < EDGE_MARGIN:
                dy -= 1
            elif my > WINDOW_H - EDGE_MARGIN:
                dy += 1

        if dx or dy:
            # dt makes speed frame-rate independent: px/sec, not px/frame.
            self.x += dx * CAM_SPEED * dt
            self.y += dy * CAM_SPEED * dt
            self._clamp()

    def center_on(self, wx, wy):
        """Jump so the world point (wx, wy) sits mid-viewport (minimap clicks)."""
        self.x = wx - VIEW_W / 2
        self.y = wy - VIEW_H / 2
        self._clamp()

    def _clamp(self):
        self.x = max(0.0, min(self.x, self.max_x))
        self.y = max(0.0, min(self.y, self.max_y))

    def screen_to_world(self, sx, sy):
        return sx + self.x, sy + self.y

    def world_to_screen(self, wx, wy):
        return wx - self.x, wy - self.y
