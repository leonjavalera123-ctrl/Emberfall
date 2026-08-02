"""
EMBERFALL: 1940 — ui.py
The command sidebar: minimap, readouts, tile survey, and (from Phase 4 on)
the build queue. The minimap is pre-rendered once, like the terrain — only
the camera rectangle on top of it changes per frame.
"""

import pygame
from settings import *
from world import TILE_DEFS


class Sidebar:
    def __init__(self, world):
        self.world = world
        self.font_title = pygame.font.SysFont("consolas", 20, bold=True)
        self.font_text = pygame.font.SysFont("consolas", 15)
        self.font_small = pygame.font.SysFont("consolas", 12)
        self.minimap = self._bake_minimap()

        x0 = VIEW_W + 10                       # left edge of sidebar content
        mm_w = world.w * MINIMAP_SCALE         # 192 for a 64-wide map
        self.panel_minimap = pygame.Rect(x0, 58, 200, world.h * MINIMAP_SCALE + 10)
        self.minimap_rect = pygame.Rect(x0 + (200 - mm_w) // 2, 63, mm_w,
                                        world.h * MINIMAP_SCALE)
        y = self.panel_minimap.bottom + 8
        self.panel_readout = pygame.Rect(x0, y, 200, 66)
        self.panel_survey = pygame.Rect(x0, y + 74, 200, 64)
        self.panel_manual = pygame.Rect(x0, y + 146, 200, 130)
        self.panel_comms = pygame.Rect(x0, y + 284, 200, 66)
        self.dragging_minimap = False

    # --- minimap --------------------------------------------------------------

    def _bake_minimap(self):
        colors = {
            ".": (96, 93, 85), ",": (78, 75, 67), "#": (42, 41, 44),
            "~": (44, 74, 86), "E": (236, 146, 52),
        }
        w, h = self.world.w, self.world.h
        surf = pygame.Surface((w * MINIMAP_SCALE, h * MINIMAP_SCALE))
        for ty in range(h):
            for tx in range(w):
                surf.fill(colors[self.world.grid[ty][tx]],
                          (tx * MINIMAP_SCALE, ty * MINIMAP_SCALE,
                           MINIMAP_SCALE, MINIMAP_SCALE))
        for num, (sx, sy) in self.world.starts.items():
            fac = FACTIONS[START_FACTIONS.get(num, "karvath")]
            pygame.draw.circle(surf, fac["color"],
                               (sx * MINIMAP_SCALE + 1, sy * MINIMAP_SCALE + 1), 3)
        return surf.convert()

    def handle_event(self, ev, cam):
        """Click or drag on the minimap to fly the camera there."""
        if ev.type == pygame.MOUSEBUTTONDOWN and ev.button == 1 \
                and self.minimap_rect.collidepoint(ev.pos):
            self.dragging_minimap = True
            self._jump_camera(ev.pos, cam)
        elif ev.type == pygame.MOUSEMOTION and self.dragging_minimap:
            self._jump_camera(ev.pos, cam)
        elif ev.type == pygame.MOUSEBUTTONUP and ev.button == 1:
            self.dragging_minimap = False

    def _jump_camera(self, pos, cam):
        mx = min(max(pos[0], self.minimap_rect.left), self.minimap_rect.right - 1)
        my = min(max(pos[1], self.minimap_rect.top), self.minimap_rect.bottom - 1)
        wx = (mx - self.minimap_rect.x) / MINIMAP_SCALE * TILE
        wy = (my - self.minimap_rect.y) / MINIMAP_SCALE * TILE
        cam.center_on(wx, wy)

    # --- drawing ----------------------------------------------------------------

    def _panel(self, screen, rect, title=None):
        pygame.draw.rect(screen, COL_PANEL, rect)
        pygame.draw.rect(screen, COL_PANEL_EDGE, rect, 1)
        if title:
            screen.blit(self.font_small.render(title, True, COL_TEXT_DIM),
                        (rect.x + 8, rect.y + 5))

    def draw(self, screen, cam, hover, fps):
        pygame.draw.rect(screen, COL_SIDEBAR_BG, (VIEW_W, 0, SIDEBAR_W, WINDOW_H))
        pygame.draw.line(screen, COL_PANEL_EDGE, (VIEW_W, 0), (VIEW_W, WINDOW_H), 2)
        x0 = VIEW_W + 10

        screen.blit(self.font_title.render("EMBERFALL: 1940", True, COL_ACCENT), (x0, 14))
        screen.blit(self.font_small.render("PHASE 1 · FOUNDATION", True, COL_TEXT_DIM), (x0, 38))

        # minimap + camera rectangle
        self._panel(screen, self.panel_minimap)
        screen.blit(self.minimap, self.minimap_rect)
        scale = MINIMAP_SCALE / TILE           # world px -> minimap px
        cam_rect = pygame.Rect(self.minimap_rect.x + cam.x * scale,
                               self.minimap_rect.y + cam.y * scale,
                               VIEW_W * scale, VIEW_H * scale)
        pygame.draw.rect(screen, (235, 235, 235), cam_rect, 1)

        # readouts — the economy arrives in Phase 3
        self._panel(screen, self.panel_readout, "TREASURY")
        screen.blit(self.font_text.render("CREDITS      --", True, COL_TEXT_DIM),
                    (x0 + 8, self.panel_readout.y + 22))
        screen.blit(self.font_text.render("POWER        --", True, COL_TEXT_DIM),
                    (x0 + 8, self.panel_readout.y + 42))

        # tile survey (whatever the mouse hovers in the viewport)
        self._panel(screen, self.panel_survey, "SURVEY")
        if hover:
            name, tx, ty = hover
            screen.blit(self.font_text.render(name, True, COL_TEXT),
                        (x0 + 8, self.panel_survey.y + 22))
            screen.blit(self.font_small.render(f"tile ({tx}, {ty})", True, COL_TEXT_DIM),
                        (x0 + 8, self.panel_survey.y + 42))
        else:
            screen.blit(self.font_text.render("--", True, COL_TEXT_DIM),
                        (x0 + 8, self.panel_survey.y + 22))

        # controls
        self._panel(screen, self.panel_manual, "FIELD MANUAL")
        lines = [
            ("WASD/ARROWS  scroll", COL_TEXT),
            ("SCREEN EDGE  scroll", COL_TEXT),
            ("MINIMAP      jump view", COL_TEXT),
            ("LMB  select    (Phase 2)", COL_TEXT_DIM),
            ("RMB  orders    (Phase 2)", COL_TEXT_DIM),
        ]
        for i, (line, col) in enumerate(lines):
            screen.blit(self.font_small.render(line, True, col),
                        (x0 + 8, self.panel_manual.y + 22 + i * 19))

        # a word from command
        self._panel(screen, self.panel_comms, "COMMS")
        for i, line in enumerate(['"Survey the ash, Commander.', 'The war arrives soon."']):
            screen.blit(self.font_small.render(line, True, COL_TEXT_DIM),
                        (x0 + 8, self.panel_comms.y + 22 + i * 16))

        fps_text = self.font_small.render(f"{fps:4.0f} FPS · v0.1", True, COL_TEXT_DIM)
        screen.blit(fps_text, (WINDOW_W - fps_text.get_width() - 12, WINDOW_H - 20))
