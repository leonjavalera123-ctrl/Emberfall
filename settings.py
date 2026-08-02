"""
EMBERFALL: 1940 — settings.py
Every tunable number in the game lives here, so balancing and tweaking
never means hunting through game logic. (See GAME_DESIGN.md section 2.)
"""

# --- window & timing -------------------------------------------------------
WINDOW_W, WINDOW_H = 1280, 720
FPS_CAP = 60

# --- the tile grid ---------------------------------------------------------
# "1 tile" is our unit of distance everywhere in the design doc.
TILE = 32                          # pixels per tile

# --- screen layout ---------------------------------------------------------
SIDEBAR_W = 220                    # command sidebar on the right
VIEW_W = WINDOW_W - SIDEBAR_W      # 1060 px — the map viewport
VIEW_H = WINDOW_H                  # 720 px

# --- camera ----------------------------------------------------------------
CAM_SPEED = 520                    # px/second (keyboard and edge scrolling)
EDGE_MARGIN = 20                   # px from the WINDOW edge that triggers scroll

# --- minimap ---------------------------------------------------------------
MINIMAP_SCALE = 3                  # px per tile → a 64x48 map becomes 192x144

# --- factions --------------------------------------------------------------
# Start position number on the map -> faction (Phase 1: visual markers only)
FACTIONS = {
    "karvath": {"name": "Karvath Iron Concord", "color": (178, 62, 46)},
    "aurelia": {"name": "Aurelian League",      "color": (72, 132, 186)},
    "ashfall": {"name": "Ashfall Compact",      "color": (122, 128, 74)},
    "luminar": {"name": "Luminar Covenant",     "color": (168, 130, 224)},
}
START_FACTIONS = {1: "karvath", 2: "ashfall", 3: "aurelia", 4: "luminar"}

# --- UI palette (dark riveted steel) ---------------------------------------
COL_SIDEBAR_BG  = (24, 26, 30)
COL_PANEL       = (33, 36, 42)
COL_PANEL_EDGE  = (64, 70, 80)
COL_TEXT        = (206, 203, 195)
COL_TEXT_DIM    = (128, 126, 120)
COL_ACCENT      = (226, 148, 59)   # emberstone orange
