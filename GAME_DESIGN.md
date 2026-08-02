# EMBERFALL: 1940 — Game Design Document
### v1 — the buildable spec

Companion to `LORE.md`. Lore says *why*; this file says *what and how*.
All numbers are provisional — we balance by playtesting, not by faith.

---

## 1. DESIGN PILLARS

Four things that make it feel like Red Alert. If a feature doesn't serve one of
these, it waits.

1. **The loop:** gather emberstone → build base → build army → break their base.
2. **The sidebar:** all construction through a right-side panel; buildings placed
   onto the map with a green/red ghost. Base layout is a real decision.
3. **Asymmetric factions:** same core rules, different personalities — heavy iron,
   sky raiders, scrap swarms, arc elites.
4. **Readable battles:** big health bars, chunky sprites, steam puffs and explosions.
   You always know what's happening.

**Scope honesty:** a full RTS is the biggest project yet. We get there in phases
(section 12), and the game is *playable and fun* by Phase 7 — everything after
that is more factions and more toys.

---

## 2. TECHNICAL FOUNDATION

| Thing | Decision |
|---|---|
| Engine | Python + pygame (same stack as your other five games) |
| Window | 1280 × 720, 60 FPS cap |
| Tile size | 32 × 32 px — "1 tile" is our unit of distance |
| Map size | 64 × 48 tiles (2048 × 1536 px world) to start |
| Viewport | 1060 × 720 (map view) + 220 px sidebar on the right |
| Coordinates | world position in pixels; `screen = world - camera` |
| Camera | scrolls with arrow keys / WASD / mouse at screen edge / minimap click |

**Distance/speed convention:** ranges and speeds are written in *tiles* (range 5.5
= 176 px). Speeds are tiles/second. Keeps the stat tables human-readable.

---

## 3. THE MAP

Tile types, stored as characters in a plain text file — you can draw new maps in
Notepad:

| Char | Tile | Walk? | Build? | Notes |
|---|---|---|---|---|
| `.` | Ashen ground | yes | yes | the default |
| `#` | Rock / ruin | no | no | blocks everything |
| `~` | Flooded trench | no | no | blocks ground; air flies over |
| `,` | Cratered rough | yes | no | passable, unbuildable |
| `E` | Emberstone field | yes | no | harvestable; ~1500 credits per tile, glows |
| `1`–`4` | Start positions | — | — | player/AI spawn (HQ placed here) |

Example (top-left corner of `maps/cradle_gate.txt`):

```
############....................
#..1........,,....E.E...........
#........,,,,,....EEE...........
#..........,,......E....~~~~....
```

First map: **Cradle Gate** — two start corners, ember fields near each base plus
one rich contested field in the middle, a flooded trench line splitting the map
with two crossings. Classic knife-fight geometry.

---

## 4. CONTROLS

**MVP set:**
- **Left-click:** select unit/building. **Drag:** box-select. **Shift+click:** add to selection.
- **Right-click:** context order — move to ground, attack enemy, harvest field (harvester), repair (engineer).
- **S:** stop. **Esc:** deselect / cancel placement.
- **Camera:** WASD / arrows / mouse at screen edge / click minimap.
- Sidebar: click a build button to queue; click the ready building, then click the map to place (ghost shows green = legal, red = no).

**Later (Phase 10):** attack-move (A+click), control groups (Ctrl+1–9), double-click to select all of a type on screen, rally points.

---

## 5. ECONOMY

- **One resource: emberstone**, measured in **credits**.
- **Harvester loop (a state machine):** `SEEK FIELD → DRIVE → MINE (fills 400 credits over ~10s) → RETURN → UNLOAD at Refinery (4s) → repeat`. If its field runs dry it finds the nearest other field; if none, it idles and blinks a warning.
- **Start of match:** HQ pre-placed + **4000 credits**. First Refinery comes with a free Harvester.
- **Power:** every building produces or draws power (see table §9). If draw exceeds supply: build speed ×0.5 and powered defenses go offline. Power is just two numbers on the sidebar — simple to implement, big strategic teeth (killing Boiler Houses is a real tactic).
- **Build costs drain as you build** (RA style): queueing a 700-credit tank drains ~100 credits/sec until done, at full power. Build time ≈ `cost / 100` seconds.

---

## 6. BASE BUILDING

- Buildings are queued in the sidebar (HQ is the "factory" for buildings).
- **Placement rules:** footprint tiles must be buildable + empty, and within **4 tiles of an existing friendly building** — bases grow outward, no tower-rushing across the map.
- **Walls** are 1×1 segments, drag-placeable later; they block ground units and projectiles have to shoot them down. Gates in Phase 10.
- **Tech tree:**

```
Command Post (start)
 └─ Boiler House ── Barracks ──── Walls, Gun Turret
        └───────── Refinery ──── Vehicle Works ── AA Turret, Airfield
                                        └──────── (Phase 9: superunit facility)
```

- **Sell** a building for 50% back; **repair** drains credits slowly (Phase 10; MVP uses Engineer repair).

---

## 7. COMBAT MODEL

Damage = `weapon damage × armor multiplier`. One small table runs all combat —
it's a dict lookup, and rebalancing the whole game means editing numbers here.

**Armor classes:** INFANTRY, LIGHT (cars/harvesters), HEAVY (tanks), AIR, BUILDING.

| Weapon class | vs INF | vs LIGHT | vs HEAVY | vs AIR | vs BLDG | Flavor |
|---|---|---|---|---|---|---|
| BULLET | 1.0 | 0.6 | 0.3 | 0.4 | 0.25 | rifles, MGs |
| CANNON | 0.5 | 1.0 | 1.0 | — | 0.9 | tank guns |
| ROCKET | 0.4 | 0.9 | 1.25 | 0.9 | 1.0 | AT + AA capable |
| FLAK | 0.6 | 0.4 | 0.2 | 1.5 | 0.2 | dedicated AA |
| BLAST | 1.2 | 0.8 | 0.6 | — | 1.5 | mortars, demo charges |
| ARC | 1.3 | 1.0 | 0.8 | 0.5 | 0.7 | Luminar; chains to 2 extra targets ≤2 tiles for 50%/25% |

- Units auto-fire at enemies in range; right-click attack forces a target.
- Projectiles are drawn and travel (shells arc, rockets fly, arcs are instant zigzag lines) — reads better than instant damage.
- Destroyed vehicles leave a **wreck** for 30s (cosmetic for everyone… except Ashfall, §8).
- Health bars over damaged/selected things. Buildings smoke below 50%, burn below 25%.

---

## 8. THE FOUR FACTIONS — HOW WE KEEP THEM BUILDABLE

**The trick: one shared roster of ROLES, with faction names, stat skews, and a few
uniques on top.** We write the code once per role; factions are data, not code.

### 8a. Core roster (baseline stats, before faction skew)

| Role | Cost | HP | Speed | Weapon | Dmg | Shots/s | Range | Sight | Armor |
|---|---|---|---|---|---|---|---|---|---|
| Rifleman | 100 | 55 | 2.2 | BULLET | 8 | 1.0 | 4 | 5 | INF |
| Tank Hunter | 300 | 50 | 1.9 | ROCKET | 30 | 0.5 | 5.5 | 5 | INF |
| Engineer | 250 | 40 | 2.0 | repairs 10 HP/s | — | — | 1 | 4 | INF |
| Harvester | 800 | 400 | 2.0 | — (carries 400) | — | — | — | 4 | LIGHT |
| Scout Car | 350 | 110 | 4.5 | BULLET | 10 | 1.5 | 4 | 8 | LIGHT |
| Battle Tank | 700 | 320 | 2.4 | CANNON | 45 | 0.55 | 5.5 | 6 | HEAVY |
| AA Vehicle | 500 | 160 | 3.2 | FLAK | 12 | 2.0 | 6 | 6 | LIGHT |
| Attack Plane | 900 | 130 | 7.0 | CANNON | 20 | 2.0 | 5 | 9 | AIR |

### 8b. Faction names for each role

| Role | Karvath | Aurelia | Ashfall | Luminar |
|---|---|---|---|---|
| Rifleman | Iron Guard | Sky Marine | Conscript | **Arc Templar** (ARC weapon) |
| Tank Hunter | Grenadier (BLAST) | Rocketeer | **Cinder Sapper** (BLAST, ×2 vs BLDG) | Lance Warden |
| Engineer | Forge Guard | Rigger | **Vulture Crew** (salvages) | Dynamo Acolyte |
| Harvester | Mule | Dray | Magpie | Collector |
| Scout Car | Outrider | Dart | Rat Tankette | Glimmer |
| Battle Tank | Bastion | Pavise (light) | Warpig (rebuilt wreck) | **Faraday Walker** (ARC) |
| AA Vehicle | Sperrwagen | Zephyr | Stovepipe Truck | Ion Carriage |
| Attack Plane | Kondor (gunship) | Sparrowhawk | Duster | Seraph |

### 8c. Faction skews (multipliers applied to baseline)

| Faction | Skew | Feel |
|---|---|---|
| **Karvath** | HP ×1.3, speed ×0.85, cost ×1.15 · buildings/walls HP ×1.5, walls half cost | slow, unkillable, cheap fortress |
| **Aurelia** | air cost ×0.8 + HP ×1.15 · ground vehicles HP ×0.8 · +1 sight everywhere | owns the sky, glass on the ground |
| **Ashfall** | cost ×0.7, HP ×0.75 · infantry build 2-at-a-time | twice the bodies, half the armor |
| **Luminar** | cost ×1.5, damage ×1.3 · all units get a **+40 shield** that regens 5/s near powered buildings | few, brilliant, grid-dependent |

### 8d. Faction signature mechanics (Phase 9)

- **Karvath:** *Hammerfall* mortar crawler (siege, outranges turrets). Superunit: **Juggernaut** land dreadnought.
- **Aurelia:** *Pelican* transport (5 infantry or 1 vehicle, flies), *Wasp* gyrocopter. Superunit: **Stratos Leviathan** (launches free Sparrowhawks).
- **Ashfall:** **Salvage** — Vulture Crew channels 3s on any wreck → +40% of that unit's cost. *Burrow* tunnel pairs (infantry teleport between). Superunit: **Ashworm** war-train.
- **Luminar:** *Pylon* shield crawler (projects 150 HP dome over nearby units), *Dynamo* wagon (mobile shield-regen zone). Superunit: **Cathedral** storm-zeppelin.
- **Superweapons** (one per faction, ~6 min charge, sidebar button, big warning for the defender): Worldhammer / Tempest Protocol / The Undermine / Second Sun — all are "pick a zone, big delayed boom" variants of one mechanic.

**MVP faction pair: Karvath vs Ashfall.** Both ground-centric (no air needed until
Phase 6), and heavy-vs-swarm is the best possible balance test. Aurelia arrives
with the air phase, Luminar last (shields + chains are the most new code).

---

## 9. BUILDINGS

| Building | Cost | HP | Size | Power | Needs | Does |
|---|---|---|---|---|---|---|
| Command Post | start | 1800 | 3×3 | +50 | — | builds buildings; **lose it = lose** |
| Boiler House | 300 | 600 | 2×2 | +100 | HQ | power |
| Refinery | 1200 | 900 | 3×3 | −25 | Boiler | harvester drop-off, +1 free Harvester |
| Barracks | 400 | 700 | 2×2 | −15 | Boiler | trains infantry |
| Vehicle Works | 1000 | 1000 | 3×3 | −30 | Refinery | builds vehicles |
| Airfield | 800 | 800 | 3×3 | −25 | Vehicle Works | builds aircraft |
| Wall | 50 | 350 | 1×1 | 0 | Barracks | blocks ground |
| Gun Turret | 500 | 500 | 1×1 | −15 | Barracks | CANNON 40, 0.7/s, range 6 |
| AA Turret | 500 | 450 | 1×1 | −15 | Vehicle Works | FLAK 14, 2.5/s, range 7 |

Faction visual identity comes from palette + silhouette: Karvath riveted slabs,
Aurelia brass + mooring masts, Ashfall sandbags + corrugated scrap, Luminar white
panels + violet glow. Same footprints, different skins.

---

## 10. PATHFINDING & MOVEMENT (the hard part, tamed)

- **A\*** on the tile grid, 8-directional (diagonal cost 1.414, no cutting corners
  past blocked tiles). Blockers: `#`, `~`, buildings, walls.
- Units are **points with a radius**, not tile-occupiers — they follow their A\*
  waypoints and get a gentle **push-apart** from nearby friendlies. This one
  choice avoids the classic gridlock bugs entirely.
- If the next waypoint becomes blocked (new building), recalculate.
- **Budget:** max ~20 A\* calls per frame; extra requests wait in a queue one frame.
  Keeps 60 FPS with 150+ units.
- **Air units ignore all of it** — straight-line flight over everything. (This is
  why planes wait until Phase 6: they're *easy*; ground movement is the boss.)

---

## 11. THE ENEMY COMMANDER (AI)

A state machine, same pattern as the harvester but bigger:

```
OPENING  — scripted build order: Boiler → Refinery → Barracks → Boiler → Vehicle Works
ECONOMY  — keep ≥2 harvesters, power positive, rebuild losses
MUSTER   — train a mixed group until army strength ≥ threshold
ATTACK   — send the wave at the player's HQ (attack anything met on the way)
DEFEND   — interrupt: enemy inside base radius → recall army home
```

Difficulty knobs (just numbers): income multiplier, muster size, seconds between
waves. Easy = ×0.75 / 8 units / slow · Normal = ×1.0 / 12 · Hard = ×1.25 / 18 mixed.

**Win/lose:** destroy the enemy Command Post → victory screen; lose yours → defeat.

---

## 12. BUILD PLAN — 10 PHASES, APPROVAL GATE AFTER EACH

Same working style as your other projects: I build a phase, you play it, we tweak,
then we advance. Each phase produces something runnable.

| Phase | Deliverable | New Python you'll learn |
|---|---|---|
| **1. Foundation** | window, map loaded from text file, scrolling camera, minimap | 2D lists, surfaces, coordinate math |
| **2. Boots on ground** | units drawn, click + box select, right-click move, A\* pathfinding | classes, algorithms (A\*), vectors |
| **3. The economy** | ember fields, harvester FSM, refinery, credit counter | state machines |
| **4. Base building** | sidebar UI, build queue, placement ghost, power, walls, tech tree | UI state, data-driven design |
| **5. War** | weapons + armor table, projectiles, health bars, wrecks, turrets; Karvath & Ashfall rosters; a dummy enemy base that defends itself | collision, combat math |
| **6. The sky** | Airfield, planes, AA units/turrets; **Aurelia joins** | inheritance (air vs ground movement) |
| **7. The enemy** ★ | AI commander, win/lose screens, skirmish setup menu (pick faction/enemy) | big state machines · **← PLAYABLE GAME** |
| **8. The light** | shields, arc chaining, power-grid rules; **Luminar joins** — all 4 factions in | event-driven effects |
| **9. Signature tech** | salvage, transports/tunnels, superunits, superweapons | juggling many systems |
| **10. Polish** | shroud (fog of war), sounds, steam/smoke particles, control groups, attack-move, 2 more maps, balance pass | performance tuning |

★ = the "it's a real game" milestone. Everything after Phase 7 is expansion.

---

## 13. PLANNED FILE STRUCTURE

```
Emberfall/
├─ main.py           # entry point, game loop, screen switching
├─ settings.py       # every constant: sizes, colors, rates
├─ factions.py       # ALL stat tables from this doc — the balance file
├─ world.py          # Map: tiles, ember fields, loads maps/*.txt
├─ camera.py         # scroll + world↔screen conversion
├─ pathfinding.py    # A* and the request queue
├─ entities.py       # Unit, Building, Projectile, Wreck
├─ combat.py         # damage table application
├─ ai.py             # the enemy commander FSM
├─ ui.py             # sidebar, minimap, selection, placement ghost
├─ maps/
│  └─ cradle_gate.txt
├─ assets/           # sprites & sounds (later phases; shapes until then)
├─ LORE.md
└─ GAME_DESIGN.md    # this file
```

Art starts as **colored geometric shapes with faction palettes** (like your other
games) — a Bastion is a chunky dark-red rectangle with a turret line, a Conscript
is a small olive circle. Steam puffs and tracer lines do a lot of heavy lifting.
Real sprites can replace shapes any time later without touching game logic.

---

## 14. BALANCE PHILOSOPHY

- Numbers in this doc are **starting guesses**. The armor table and `factions.py`
  exist so tuning = editing one file.
- First balance target (Phase 5): **10 Ashfall Conscripts (700 cr) should slightly
  lose to 1 Bastion tank (805 cr)** — but 10 Conscripts + 2 Cinder Sappers should
  win. Cost-for-cost fights should feel close and flavorful.
- Second target (Phase 6): 2 Sparrowhawks kill a Bastion that has no AA escort;
  1 Sperrwagen deletes a lone Sparrowhawk. Escorts matter.

---

---

## 15. THE 3D PIVOT (v1.1 — added after Phase 1)

Commander's orders: full 3D, same pipeline as Faction Wars. The engine is now
**Godot 4.7.1** with **Blender** (via BlenderMCP) supplying `.glb` models.

**Everything above still stands** — lore, map text format, economy, power,
combat table, rosters, buildings, AI, and the 10 phases are engine-agnostic.
What changes is the renderer and the camera:

- **Scale:** 1 tile = 2 meters. The 64×48 map is a 128×96 m battlefield.
- **Camera:** RTS rig — pan (WASD/arrows/screen edge), rotate (Q/E),
  zoom (mouse wheel, 14–55 m). Survey/selection use a mouse ray onto the
  ground plane instead of pixel math.
- **Look:** AgX tonemap, glow (emberstone bloom), SSAO, ashen distance fog,
  FastNoiseLite triplanar terrain materials — no image assets needed.
- **Terrain build:** row-run merged slabs (the Faction Wars perf trick),
  sunken shader-water trench, raised rock/ruin blocks, MultiMesh ember
  crystals with per-instance pulse phase.
- **Models:** procedural placeholder buildings now; every structure has a
  `models/*.glb` hook — when a Blender-made model exists it's used
  automatically (drop-in, no code change). Blender bridge: Leon opens
  Blender → N-panel → BlenderMCP → Connect.
- **The pygame build** (main.py & friends in the project root) is retired but
  kept as the 2D reference prototype.

**New file layout (supersedes §13):**

```
Emberfall/
├─ godot/                  # THE GAME (Godot 4.7.1, Forward+)
│  ├─ project.godot
│  ├─ main.tscn / main.gd  # environment, lighting, selftest
│  ├─ world.gd             # map parse + 3D terrain + pads (EFWorld)
│  ├─ camera_rig.gd        # RTS camera (CameraRig)
│  ├─ ui.gd                # sidebar + minimap CanvasLayer (EFUI)
│  ├─ ember.gdshader / water.gdshader / flag.gdshader
│  ├─ maps/cradle_gate.txt # same text format as ever
│  └─ models/              # Blender .glb drop-ins (hq_karvath.glb, ...)
├─ Play Emberfall.bat      # double-click to play
├─ Import Assets.bat       # run once after new files/models appear
├─ main.py ...             # retired pygame prototype (reference)
└─ LORE.md / GAME_DESIGN.md
```

**Dev verification:** `Godot_..._console.exe --path godot -- --selftest out.png`
renders the scene, prints a timed average FPS, saves a screenshot, exits.
Phase 1 (3D) measured **165 FPS** on the RTX 4050 — plenty of headroom for
Phase 2's armies.

*v1.1 — Phase 1 rebuilt in 3D, awaiting Commander review. Phase 2 (units,*
*selection, pathfinding) builds on this scene; Blender model passes slot in*
*per phase, exactly like Faction Wars.*

---

## 16. PHASE 2 NOTES + THE CRADLE (v1.2)

**New default map: The Cradle — 96×64 (was 64×48), designed around choke
points** per Commander's orders:

- **Walled base compounds** in opposite corners — rock ramparts with exactly
  two 4-tile gates each (east + south). Defensible, but a determined push
  through a gate is always possible.
- **The scar:** a 4-row flooded trench across the whole map with only
  **three crossings** (west / center / east), squeezed further by rock teeth.
- **The ruined town:** twin districts of rock-block ruins north and south of
  the center crossing — street fighting between them.
- **Crater belts** (rough, unbuildable) on the approach lanes.
- Ember fields: home (inside your walls), expansion (past your south gate),
  flank (by the town), and the center prize between the twin districts.
- The generator PROVES the chokes: plugging the 3 crossings must disconnect
  the halves; plugging a base's gates must seal it. 72 ember tiles = 108k
  credits on the map. `cradle_gate.txt` (64×48) kept as the small map.
- Minimap now auto-scales (2 px/tile at 96 wide, 3 at 64).

**Phase 2 systems (army.gd + unit.gd):**

- **Pathfinding:** Godot's `AStarGrid2D` over the tile grid — octile
  heuristic, diagonal-only-if-no-obstacles (no corner cutting). Paths are
  then **string-pulled** (greedy farthest-visible-waypoint) so units walk
  smooth lines, not tile-center zigzags. Same algorithm as §10 promised,
  engine-accelerated.
- **Crowd handling:** push-apart pass exactly as §10 designed — units are
  points with radii; moving units shove at full strength, idle at 35%.
  Stuck units (blocked > 0.7 s) automatically repath.
- **Selection:** click, drag-box (rubber band), Shift-add; enemy units not
  selectable. FORCE panel lists the selection by type.
- **Orders:** RMB move with golden-spiral formation offsets + green order
  marker; **S stops** (contextual: S pans camera only when nothing is
  selected); ESC deselects.
- **Units in:** Iron Guard, Bastion, Outrider (Karvath) — procedural bodies
  with walk bob and slow tank turrets; Conscripts + Rat tankettes stand at
  the Ashfall base awaiting Phase 7's AI brain. Blender unit models slot in
  later exactly like the HQs did.
- Selftest grew `--start N` (aim at a base) and `--march` (order the army
  to mid-map, film the column, report path success). Phase 2 measured
  ~156–165 FPS with the doubled map plus units.

*v1.2 — Phase 2 complete, awaiting Commander review. Next: Phase 3, the*
*economy — emberstone harvesters, the Refinery, and credits that tick up.*

---

## 17. PHASE 3 NOTES: THE ECONOMY, GARRISONS, AND THE STANDARD MAP (v1.3)

**Standard map size is now 192×128** (Commander's orders — game length target
**30+ minutes**). Default map: **Ashfall Plain** — walled base compounds with
two 8-wide gates, a 5-row scar with 4 proven crossings, two ridge lines with
gapped passes, twin towns, flank villages, crater belts, 144 ember tiles
(216k credits), and **44 garrisonable structures**. Older maps remain playable.
Terrain now renders as merged MultiMeshes — the whole battlefield is ~8 draw
calls, so the 4× tile count still runs at ~165 FPS.

**Garrisons (new mechanic).** Map char `B` = ruined structure. Contiguous B
tiles group into one building: bunkers/watchtowers (1 tile, cap 2), farmhouses
(4 tiles, cap 6), village houses (6 tiles, cap 6).
- RMB a ruin with infantry selected → they walk to its door and occupy it.
- Occupied ruins glow the holder's faction color and fly their banner.
- One faction per building; full buildings turn newcomers away.
- Click a ruin your troops hold → the garrison is selected; RMB ground → they
  pour out the door and move there.
- **Phase 5 combat rule (reserved in code):** garrisoned units take
  `GARRISON_DAMAGE_MULT = 0.5` incoming damage and fire from the windows.
- Enemy AI can garrison too — the Ashfall Compact starts holding two ruins.

**The economy (live).** Start 3000 credits; each ember tile holds 1500.
Refineries are pre-placed beside each HQ (buildable in Phase 4). Harvesters
run the §5 FSM: seek → drive → mine (50/s, 400 capacity, glowing cargo pile
when loaded) → dock → unload (3 s). Depleted tiles lose their crystals, turn
to cratered rough, and grey out on the minimap. RMB a field to direct a
harvester; S holds it. Verified end-to-end: both factions' harvesters
delivered loads in an unattended run.

**Selftest lessons baked in:** waits are game-time (`_wait_seconds`), not
frame counts (frame counts lie at uncapped FPS); runners use
WaitForExit-with-kill so a compile error can't strand a window; `--econ` and
`--garrison` flags prove the new systems headlessly.

*v1.3 — Phase 3 complete, awaiting Commander review. Next: Phase 4 — the*
*sidebar build queue, power, walls, and base construction.*

---

## 18. PHASE 4 NOTES: RAISE THE BANNERS (v1.4)

**Base building is live** (`buildings.gd`), with unit training pulled forward
from Phase 5 so the whole "build an army" loop works now:

- **Three sidebar tabs** — BASE / INF / VEH — with RA-style queues: one item
  per tab builds at **100 credits/second** drained straight from the
  treasury (×0.5 when the power grid is overdrawn). Buildings finish as
  READY and flash **PLACE** — click, then aim the green/red ghost and click
  the map. Units walk out of their producer and rally a few tiles south.
- **Placement rules** as designed: buildable ground, nobody standing there,
  within 4 tiles of your base. RMB/ESC cancels the ghost (a READY building
  stays ready).
- **Walls** skip the queue: 50 credits each, place repeatedly until ESC —
  segments automatically link arms with neighboring walls. They block
  ground movement and pathfinding for real.
- **Power** is live: HQ +50, Boiler +100; consumers as §9. Deficit = halved
  build speed + a red LOW! warning (turrets go offline when combat arrives).
- **Tech tree enforced:** Boiler → Refinery/Barracks → Vehicle Works →
  AA Turret; Barracks → Gun Turret + Walls. Airfield arrives in Phase 6.
- **Turrets** build now (idle heads scanning) — their guns wake in Phase 5.
- Refineries migrated from pre-placed scenery into real, buildable
  structures (new ones spawn a free harvester, RA-style).
- UI rework to fit: combined CONTEXT panel (selection or survey), compact
  hints, and the full controls list moved to an **F1 overlay**.
- Selftest `--build` proves queue → power → placement → tech gate → training
  end-to-end; `--econ` re-verified the economy after the refinery refactor.

*v1.4 — Phase 4 complete, awaiting Commander review. Next: Phase 5 — WAR.*
*Weapons, the armor table, health bars, wrecks, turret fire, garrison cover*
*bonuses, and the Ashfall roster to shoot at.*

---

## 19. PHASE 5 NOTES: WAR (v1.5)

**Combat is live**, running the §7 armor table verbatim (BULLET / CANNON /
BLAST active; FLAK waits for aircraft):

- **Weapons & projectiles:** rifles fire instant tracers; cannons throw
  visible shells with muzzle flash + light pop; grenadier/sapper BLAST
  charges lob in an arc. Impacts bloom, infantry deaths puff, vehicle deaths
  leave burnt wrecks that linger ~30 s then sink into the ash.
- **Orders:** RMB an enemy unit, building, or enemy-held ruin to attack
  (units chase); with no orders units hold position and engage anything in
  range with line of sight (rocks, buildings, and walls block fire). Move/S
  orders clear attack targets.
- **Garrison combat, as designed:** occupants fire from the windows (+2 m
  range) and are hit *through* the building at ×0.5 damage
  (GARRISON_DAMAGE_MULT). Defenders die one at a time; the banner drops
  when the last one falls. The stone shells themselves are indestructible.
- **Turrets** fire CANNON 40 at 0.7/s over 12 m — with grid power. Low power
  = silent guns. Heads track targets and scan idly otherwise.
- **Buildings take damage** (BLDG armor column): smoke below 50%, and at 0
  they collapse into scorched rubble — footprint reopens to pathfinding,
  tech tree degrades if you lose a prerequisite, minimap updates. Sappers'
  BLAST hits structures at ×1.5: the Compact's demolition doctrine works.
- **The enemy fights back:** Ashfall pickets (now conscripts, sappers, Rat
  tankettes, and two Warpig tanks at their compound) defend their ground —
  anything of yours inside ~24 m gets charged — their two gun turrets fire,
  and their garrisoned conscripts shoot from the ruins they hold.
- **Rosters:** Grenadier joined the INF tab ($350). Health bars overlay on
  hurt/selected units and damaged buildings, color-coded by remainder.
- Verified headless (`--war`): staged skirmish resolved with casualties on
  both sides and a clean error log at ~165 FPS. Engine lesson recorded:
  never free a unit the moment it dies — in-flight shells hold references —
  corpses linger hidden for 3 s, then the effects sweeper frees them.

*v1.5 — Phase 5 complete, awaiting Commander review. The game is one phase*
*from the §12 milestone: Phase 6 (air) then Phase 7 (AI + victory) = a real,*
*winnable war. Recommend Phase 7 next if you'd rather fight a thinking enemy*
*sooner — planes can wait; the order is yours, Commander.*

---

## 20. PHASE 7 NOTES: A THINKING ENEMY — ★ THE MILESTONE (v1.7)

**Emberfall is now a complete, winnable RTS.** (Taken before Phase 6 on the
Commander's orders — the sky waits.)

- **Skirmish menu:** pick your banner (Karvath or Ashfall — yes, you can play
  the Compact now) and your battlefield (Ashfall Plain / The Cradle / Cradle
  Gate), then BEGIN THE WAR. All player-side systems — build tabs, credits,
  power, camera start — follow your chosen faction; the AI takes the other.
- **The AI commander (`ai.gd`)** runs the §11 state machine: OPENING build
  order (Boiler → Barracks → Vehicle Works) → ECONOMY (rebuild losses, keep
  power positive, run 2 harvesters) → MUSTER (train a mixed force to 10) →
  ATTACK (wave at your HQ, stragglers re-aimed, HQ targeted on arrival) →
  and a DEFEND interrupt that recalls the army when you push near its base.
  It pays real credits from its own treasury and obeys the real tech tree —
  its "queue" is just a timer instead of a sidebar. Difficulty knobs
  (MUSTER_SIZE, WAVE_COOLDOWN) sit at the top of ai.gd.
- **Victory & defeat:** a Command Post at 0 HP ends the war — gold VICTORY
  or red DEFEAT screen, the fallen HQ's pad vanishes under rubble, the game
  freezes, and **R** returns to the menu.
- Start forces now spawn relative to each side's compound (works on every
  map size); faction-specific unit costs and build tabs (Ashfall trains
  conscripts $70, sappers, Rats, Warpigs, Magpie).
- **Proofs:** `--ai` — in 100 s the enemy built 7 structures, mustered 12
  units, and launched its wave (state=WAVE, 0 errors). `--gameover` — six
  Warpigs razed the player HQ and the defeat pipeline fired. Build and war
  selftests regress clean under the faction refactor. ~165 FPS throughout.

*v1.7 — THE GAME IS PLAYABLE, awaiting Commander review. Remaining ladder:*
*Phase 6 (the sky: Airfield, planes, AA, Aurelia), Phase 8 (Luminar, shields,*
*arc), Phase 9 (salvage, superunits, superweapons), Phase 10 (polish).*

---

## 21. PHASE 6 NOTES: THE SKY OPENS (v1.8)

Taken after Phase 7 by Commander's order. The air war and the third faction:

- **The AIR tab.** The Airfield ($800, 3x3, -25 power, needs Vehicle Works)
  unlocks each faction's aircraft: Karvath **Kondor** gunship ($1050, CANNON —
  a flying tank-killer that cannot dogfight), Ashfall **Duster** ($630, ROCKET —
  cheap tank-hunter that can nip at planes), Aurelian **Sparrowhawk** ($720,
  FLAK guns — ruler of the sky, weak at strafing armor).
- **Flight model:** planes ignore terrain and never stop — straight lines to
  their orders, lazy orbit circles on arrival, banking into turns, spinning
  props, ground shadows. Cruise altitude 8 m. Shot-down planes tumble and
  crash. Stop (S) makes a plane orbit where it is.
- **The armor table grew:** AIR column (CANNON/BLAST hit 0.0 vs air — they
  literally cannot aim up) and the full ROCKET row. FLAK: 1.5x vs air, feeble
  vs ground. Every acquisition path (auto, aggro, turrets, RMB) respects
  "can this weapon hurt that target" — units that can't hurt a clicked plane
  escort to the spot instead.
- **AA:** the AA Turret is live (FLAK 14, air-ONLY — it never wastes its
  barrels on ground troops) and every faction fields an AA vehicle:
  Sperrwagen / Stovepipe Truck / Zephyr. The enemy base now pre-places one
  gun + one AA turret, and the AI builds airfields, planes, and up to two
  AA turrets of its own.
- **The Aurelian League is playable** (menu: pick banner AND enemy). Full
  ground roster: Sky Marine, Rocketeer (ROCKET — doubles as hand-held AA),
  Dart scout, Pavise light tank (fast, LIGHT armor), Zephyr AA, Dray
  harvester. Brass watchtower HQ with mooring mast.
- **Factions are decoupled from map slots** (world.slot_faction / faction_start):
  credits, tech, placement, win/lose all keyed by faction id. This was the
  Phase 8 groundwork — Luminar drops in as faction 4 data.
- **Verified by selftest:** `--air` (tech chain -> flight at 8.0 m -> live
  flak duel; Kondor beats a flak truck 26 hp to spare, a lone Sparrowhawk
  strafing a Sperrwagen dies — the table working as designed) and
  `--air --pfac 3 --efac 1` (Aurelia as player: faction-correct placement,
  training, and the duel from the other side). Regressions clean, 165 FPS.
- **Dev lesson that cost an hour:** Godot parse errors print to STDERR —
  never gate an import check on stdout. Per-file check:
  `godot --headless --check-only --script res://file.gd` (read stderr).

---

## 22. PHASE 8 NOTES: THE SECOND SUN + THE COMMANDER'S QUALITY-OF-LIFE (v1.9)

Two things landed together: Leon's playtest fixes and the fourth faction.

**Commander QoL (from field reports):**
- **Click a production building** and the sidebar jumps to its recruit tab;
  the CONTEXT panel names it, shows HP, and lists what it trains. No more
  guessing where soldiers come from.
- **Locked buttons explain themselves:** "needs Barracks" instead of a
  silent grey $-price.
- **DEMOLISH (+50%)** button on any selected building (or press DELETE) —
  the emergency lever for over-drawn power grids and dead economies.
  The Command Post refuses to demolish itself.
- **RMB a build button to cancel** — backlog items vanish free; an active
  build refunds every credit already paid.
- **NO FUNDS flashes** on the treasury when a build is stalled at zero credits.

**The Luminar Covenant (faction 4, playable + AI):**
- Roster: Arc Templar / Lance Warden (ARC), Glimmer scout, Faraday Walker
  (ARC cannon), Ion Carriage (FLAK), Collector, Seraph rocket-glider.
  Costs run ~1.5x — few, brilliant.
- **ARC weapons** joined the table (1.3 vs INF, 0.8 vs HEAVY, 0.5 vs AIR,
  0.7 vs BLDG) and **chain**: every primary hit leaps to up to 2 more
  enemies within 4 m for 50% / 25% damage, drawn as jittered violet bolts.
  Lightning loves a crowd — proven 6-conscript mob cut to 2 by three Templars.
- **Shields:** every Luminar unit carries a 40 hp shield that absorbs first,
  blips violet when struck, and regenerates 5/s near the faction's powered
  buildings (nothing regens during a power deficit). Violet shield bars
  draw above health bars. Proven: dented 40 -> 10 in the field, refilled
  to 40 after regrouping at base.
- White-spire Glass City HQ with arc-coil beacons; menu now seats all four
  banners (and their enemies) four across.
- Verified: `--arc --pfac 4 --efac 2` (chains + shield absorb + regen),
  `--sell` (demolish +150 on a $300 boiler; cancel refunded 199/200),
  `--build` regression clean. 165 FPS steady.

**Still open for Phase 9+:** faction signature tech (salvage, tunnels,
transports, superunits, superweapons), Lightning Spire faction turrets,
Blender model pass for units, shroud, sounds, balance campaign.

---

## 23. PHASE 9 NOTES: SIGNATURE TECH (v2.0)

Every banner got its identity piece, its titan, and its doomsday clock.

- **Signature units:** Karvath **Hammerfall Crawler** ($900, BLAST, range 16 —
  outranges every turret; the wall-cracker), Aurelia **Wasp Gyrocopter**
  ($450, cheap strafing air), Ashfall **Vulture Crew** ($200, unarmed — walks
  to any vehicle wreck, strips it for 3 s, banks **40% of the dead unit's
  cost**; idle crews find wrecks on their own; RMB a wreck to order it),
  Luminar **Dynamo Wagon** ($600, unarmed — a rolling piece of the power
  grid: friendly shields regenerate within 10 m of it, anywhere on the map).
- **Wrecks are real now:** vehicle kills leave a 30-second husk with a
  salvage value. Ashfall eats battlefields.
- **Superunits** (trained at the Doomworks): Karvath **Juggernaut** ($3200,
  2200 hp, twin cannon), Ashfall **Ashworm** war-train ($2100, 1500 hp,
  BLAST), Aurelia **Stratos Leviathan** ($2800, 1300 hp flying cannon
  platform — helpless vs fighters, bring escorts), Luminar **Cathedral**
  ($3800, 1100 hp + 80 shield, chaining ARC from the sky).
- **The superweapon:** one **Doomworks** per faction ($2500, −50 power,
  needs Vehicle Works) charges 180 s (stalls in a power deficit), then the
  sidebar button arms a target click: 4-second red warning ring (both sides
  see it, banner announcement + klaxon text), then a 9 m annihilation zone —
  ~320 falloff damage to units, 380 BLAST to every building touched, scorch
  crater, screen shake. Faction names: WORLDHAMMER / THE UNDERMINE /
  TEMPEST PROTOCOL / SECOND SUN. The AI builds one when rich and fires it
  at your Command Post the moment it charges — watch for the warning.
- Verified: `--super` (tech -> charge -> strike killed pickets -> Juggernaut
  trained), `--salvage --pfac 2` (bastion wreck worth 280 auto-stripped,
  credits 3000 -> 3280). 165 FPS.
- **Deferred to Phase 10 polish:** Pelican transports, Burrow tunnels,
  Pylon shield crawler, Leviathan fighter launching, faction turret skins,
  shroud, sounds, Blender unit models, balance campaign.

---

## 24. PHASE 10 NOTES: ASH AND THUNDER (v2.1) — THE PLAN IS COMPLETE

The last phase of the original ten. Two field bugs fixed, three senses added.

- **THE TURRET BUG (Leon's catch):** every turret since Phase 5 was blind —
  its line-of-sight ray started inside its own foundation tile, which the
  LOS code counted as a wall. sight_clear() now takes ignore_first (see past
  your own footprint) and over_walls (elevated shooters fire over wall
  segments); garrisons got the same cure (4.8 m self-clearance). Proven:
  a gun turret killed 2/2 intruders. The AI's repeated assaults were always
  by design — now your defenses answer them.
- **Sticky marches:** units that auto-engage mid-route resume their march
  when the shooting stops instead of loitering on the battlefield. Proven:
  a Bastion ordered past an enemy killed it and still arrived.
- **Control groups:** Ctrl+1..9 assigns, 1..9 recalls.
- **THE SHROUD:** the map starts 96.8% unknown. Your units burn away the
  veil (10-tile sight, 14 flying); buildings watch 9; the minimap reveals
  as you scout and enemy start dots appear only when found. You cannot
  build or survey in the dark. The AI is unaffected (classic RTS). One
  192x128 alpha texture on a quad at y=12 — costs ~15 fps, worth every one.
  Superweapon warning rings render ABOVE the shroud: you always see doom
  coming. F3 toggles the veil for debugging.
- **SOUND:** 14 procedurally synthesized WAVs (pure-python wave synth,
  scratchpad generator -> sounds/): per-class weapon fire, explosions
  small/big, the superweapon klaxon + apocalypse boom, placement thunk,
  ready chime, salvage coin, victory/defeat stings. EFAudio pools 12
  positional + 3 UI players. The war finally has a voice.
- Proven: --turret (2/2 kills + sticky arrival), --shroud (3.2% -> 8.4%
  scouting), --war regression clean. 145-165 FPS.

**The 10-phase campaign is COMPLETE.** Post-campaign wishlist: Blender
model pass for units, Pelican transports + Burrow tunnels + Pylon crawler,
faction-skinned turrets, music drop-in, multi-map balance campaign,
Leviathan fighter launching, save/load.

---

## 25. PHASE 11 NOTES: THE LONG WAR (v2.2) — LEON'S SECOND WISHLIST

Seven field requests, all shipped and selftest-proven:

- **PAUSE (P):** freezes the whole war under a dim overlay; P/ESC resumes.
  The sidebar sleeps while paused.
- **AA GUNS FIXED:** they were air-only purists standing idle through ground
  assaults. Now flak prefers wings — it re-checks the sky constantly — but
  strafes ground targets rather than sit useless. Proven: one turret downed
  a Duster AND chewed the conscript walking past.
- **DIFFICULTY:** menu row CHOOSE THE ODDS — EASY (waves of 8, 40 s
  breathers, 0.75x AI income, NO superweapon), STANDARD (as designed),
  BRUTAL (waves of 14, 15 s cooldown, 1.3x income, +1500 starting credits).
- **GREY FOG MEMORY:** the veil now has three states — unseen black,
  currently-visible clear, and previously-seen LIGHT GREY showing the land
  as last surveyed. Enemy units vanish into the fog (and can't be clicked);
  buildings you've discovered stay on the map. Your structures cast
  standing vision.
- **FIELD HEALING:** troops who go 8 s without a wound mend 2 hp/s while
  within 24 m of their own Command Post. Rotate your veterans home.
- **BUILDING REPAIR:** select a damaged building -> REPAIR button toggles
  20 hp/s at 1 credit per 2 hp. Proven: 450 -> 770 hp for 160 credits.
- **THE EMBER RETURNS:** harvested-out fields lie fallow ~75 s, then regrow
  at 6 cr/s back to a full 1500 — crystals rise again from the same seed,
  the minimap re-lights, harvesters return on their own. Partially-mined
  fields also slowly refill. The long war can be fought forever.
- Regression --war clean, 165 FPS.

---

## 26. PHASE 12 NOTES: THE CRADLE WAR — ACT I (v2.3) — CAMPAIGN & NEW MAPS

The game now has a story front. The main menu became three rooms:
CAMPAIGN / SKIRMISH / CONTINUE LAST WAR, with a war-chronicle screen
showing three missions, briefing papers, and objective lists. Progression
is saved to campaign.cfg — later missions show as SEALED ORDERS until
the one before them falls.

**ACT I — THE IRON CONCORD (playing Karvath, fighting Ashfall):**

- **MISSION 1 · OPERATION LANDFALL** (new map: Cradle Landing, 64x48).
  The expedition lands below a shattered ridge; the Ashfall forward camp
  holds the far side. Enemy is capped to infantry-only (tech_limit) —
  no vehicle works, no armor. Objectives tick live in the top-left:
  raise a Boiler House + Barracks, muster 8 Iron Guard, burn the camp.
- **MISSION 2 · THE GREY TIDE** (new map: Greyfen Redoubt, 96x64). A
  survival mission — the first of its kind here. The player holds a rock
  ring in the open ash with two gates, prebuilt turrets/walls/garrison
  and +2000 credits. The enemy commander is switched OFF; instead five
  scripted waves roll in from N/E/W on a timer, each announced with the
  klaxon and a compass call. Stragglers re-aim at the Command Post every
  3 s so the tide never stalls. Survive 6:00 and the mission is won —
  the objective line counts down live.
- **MISSION 3 · THE CRADLE GATE** (existing map The Cradle, BRUTAL AI).
  No more holding: kill their command post. The player starts with five
  veterans at their back (2 Bastions, 1 Hammerfall, 2 Grenadiers).

**Wiring:** campaign.gd (EFCampaign) owns briefings, objectives,
wave scripting, and unlock state; ui.set_objectives draws the [X]/[ ]
tracker; show_game_over grew MISSION COMPLETE / MISSION FAILED faces;
main routes campaign_requested from the menu and asks campaign.tick()
for timed wins. Skirmish gains both campaign maps (5 total).

**Proof:** --mission2 selftest (compressed tide: waves at 4 s/12 s,
survive 25 s) → game_over=true victory=true, 165 FPS, zero script
errors; --gameover skirmish regression clean; all six touched scripts
parse-clean; menu rooms and Missions 1/3 boot-checked with screenshots.

---

## 27. PHASE 13 NOTES: ASH AND ANTHEM (v2.4) — SCORE, SKY, ACT II

Four things, all selftest-proven.

**1. THE SCORE.** The game has music. Three tracks were synthesised from
scratch (numpy, 22050 Hz mono) and are deliberately band-limited so the
whole score sounds like a wartime shellac broadcast — which suits an
alternate 1940 better than a clean modern mix would.

  mus_menu  "THE CRADLE WAR"  D minor, 54 BPM, 16 bars. Drone, slow pad,
            forge strikes, and a lone horn melody that states at bar 8
            and answers at bar 12.
  mus_bed   "FORGE AND ASH"   96 BPM, 28 bars. The machine working:
            piston pulse, bass ostinato, distant anvil, steam.
  mus_war   "IRON WEATHER"    the SAME 96 BPM / 28-bar grid. War drums,
            driving eighths, tremolo, brass stabs, crescendo rolls.

The two in-game stems are layers, not a playlist: both start in the same
frame and are never stopped, so they stay sample-locked forever (measured
drift: 0.0000 s). "Combat intensity" is then just a volume ride on the war
layer — every wound anywhere calls music.bump(), which decays on its own.
No crossfade, no tempo clash, no re-sync logic. The score keeps playing
(ducked) over the pause overlay, because EFMusic is deliberately left OUT
of main's PROCESS_MODE_PAUSABLE list.

Two things had to be got right and would not have been audible in a
screenshot: the mix was originally 95% sub+bass energy, which buried every
melodic voice, so mastering now applies a +12 dB tilt shelf above 420 Hz;
and the loops clicked, so each track renders 1.2 s of music PAST its loop
point and folds that overhang back over the head — which makes the seam
sample-continuous by construction instead of by luck. Godot's WAV importer
also had to be forced off its default lossy QOA compression, which would
have damaged those seams (compress/mode=0, edit/loop_mode=2).

**2. THE SKY.** ProceduralSkyMaterial's four-colour gradient is replaced by
a real sky shader: two scrolling ash cloud decks, a sun that never quite
burns through, and emberstone glow banked along the horizon. The important
discovery is that at the RTS camera pitch (-52 degrees, 55 degree fov) the
top of frame sits 24.5 degrees BELOW horizontal at every zoom — the player
can never see overhead sky. So the detail that actually matters went below
the horizon, where the map edge dissolves into a drifting dust sea instead
of the flat wall it used to be. The fill light is now SKY_MODE_LIGHT_ONLY
(it was painting a second, cool sun into the sky) and fog_sky_affect came
down from 0.25 to 0.12 (it was washing out 25% of the sky's own contrast).

**3. FACTION PLATE.** Poly Haven metal scans now clad the buildings, one
per banner: Karvath in riveted rust, the Compact in salvaged corrugated
sheet, the League and Covenant in cleaner works-metal. Only the RELIEF is
taken (normal + roughness) — cladding walls in the diffuse scan crushed
both the brightness and the faction hue, and in an RTS ownership has to
read at a glance. Mapping is LOCAL triplanar, not world: the gun and AA
turret .glbs have a rotating "Head", and world-space mapping would make
the plate slide across it as it tracks. An A/B at full zoom is the honest
test — with relief the tanks and panels read as weathered metal, without
it they read as smooth plastic. At normal zoom the difference is invisible;
it costs no measurable frames, so it stays.

**4. THE CRADLE WAR, ACT II — THE THOUSAND SAILS.** The campaign is now
two acts of three missions. Missions became pure data: a briefing, a list
of objectives, a parallel list of machine-checkable goals (own / muster /
kill_hq / razed_all / hold_hq / survive) and optional setup hooks
(ai_tech_limit / ai_off / grant / prebuild / veterans / drive_tide /
waves). Adding a mission is now a dictionary entry, not engine code.

  MISSION 4 · THE THOUSAND SAILS (new map: Sailwright Reach, 96x64)
    Playing AURELIA against Karvath for the first time in the campaign.
    A canal with three crossings and open sky. Raise an airfield, muster
    four Sparrowhawks, break the bridgehead.
  MISSION 5 · THE FLAK COAST (new map: The Flak Coast, 96x64)
    An escarpment with two covered gaps. Silence every Karvath AA
    emplacement, then finish the works behind it. Opens with a prebuilt
    airfield and a veteran flight.
  MISSION 6 · THE SECOND SKY (The Cradle, BRUTAL)
    The last flight of the war.

Act II stays sealed until Act I is finished; progress is one ConfigFile
section per act. The menu grew act tabs, numbers missions 1-3 within each
act, and the skirmish map grid went four-wide because a seventh map in the
old three-wide grid collided with BEGIN THE WAR.

**MAP VALIDATOR.** The two new maps were generated against a validator
encoding every hard requirement of the format — including reachability,
which nothing in the engine checks and which silently makes a mission
unwinnable (harvesters deadlock on an unreachable field; the AI path-fails
forever on an unreachable enemy start). Run as a regression over all seven
maps it found a real flaw in a shipped one: greyfen_redoubt's enemy corner
had no ember within reach, so in Skirmish that AI simply starved. Fixed.

**Proof:** all six missions boot with correct grants/prebuilds/veterans;
the survival mission still wins after the refactor; music verified inside
the exported .exe (16-bit PCM, LOOP_FORWARD, war layer -46 -> -14 dB under
fire, 0.0000 s stem drift, loop wrap confirmed); eight regression flags
(--war --build --gameover --air --shroud --econ --regrow --autobldg) clean
at 164.8-165.1 FPS; ten scripts parse-clean; the exported build loads the
new Act II map end to end.

### 27b. THE PELICAN, AND WHAT THE REVIEW FOUND

**THE PELICAN.** The Aurelian League gets an air transport ($900 from the
Airfield, 5 slots, AIR armour so cannon and shells cannot touch it and flak
shreds it). Select infantry, right-click the Pelican and they walk out and
board; select the loaded Pelican and right-click a tile and it flies there,
settles, and puts them down — over walls, over water, behind a flak line.
Shoot it down loaded and the platoon dies with it.

Implementation rests on one idea: a stowed unit is REMOVED from army.units
(the node lives on as a child of EFArmy). Every system in the game reaches
units by iterating that list, so removal buys exclusion from movement,
combat, auto-acquire, separation, fog write-back, vision, health bars and
selection for free — no scattered guard flags. The one thing that had to be
right was hovering: a transport at cruise speed outruns infantry, so it
bleeds to a stop and drops to 3 m to load, or nothing could ever board it.

**THE REVIEW.** Everything above was then reviewed adversarially — findings
were raised on four independent lenses and each one had to survive a
separate agent trying to refute it. 13 raised, 3 refuted, 10 confirmed and
fixed. The ones worth recording:

- *Mission 2's objectives could never tick.* The goals were judged before
  the survival timer was decremented, and the same tick that expired the
  clock returned "win" — so a goal gated on the clock never latched and the
  mission ended showing 0/2 complete. The timer now runs first.
- *Every "destroy the command post" objective was dead code.* main's frame
  loop checked HQ deaths before ticking the campaign, in an elif chain, so
  the instant the enemy HQ fell the game ended and the campaign was never
  ticked again. Five of six missions ended with their main objective
  unticked. The campaign now ticks first.
- *Prebuilt structures validated only their origin tile.* A size-3 airfield
  was therefore planted half inside the start refinery on The Flak Coast
  (with the two shared tiles reassigned in cell_map, so destroying the
  airfield would have punched permanent holes in the refinery), and on The
  Cradle it covered two emberstone tiles, converting them to structure
  tiles and orphaning 1500 credits each where no harvester could ever reach
  them. Prebuilds now validate the whole footprint and search outward.
- *Mission 5's flak line did not exist.* "Destroy every Karvath AA
  emplacement" resolved to the single auto-placed turret beside the enemy
  command post — reachable only from inside their base, the opposite of the
  briefing. Missions can now fortify the ENEMY, and the escarpment has a
  real four-gun flak line with a boiler to power it.
- *The building relief was doing nothing.* Local triplanar was chosen to
  protect the turrets' rotating heads, but every mesh in these .glb models
  is a unit-sized primitive scaled by its node transform, so local mapping
  gave each surface a fraction of one texture tile — a smooth smear, not
  grain. Now world-mapped like the terrain, with rotating heads excluded.
- *Combat intensity decayed while paused,* so the score came back from a
  long pause silent instead of ducked.

Two were NOT mine — long-standing bugs the sweep happened to surface:

- **LUMINAR mustered no army at all.** spawn_start_forces matched factions
  1, 2 and 3 with no case for 4 and no default, so ever since the Covenant
  became playable in Phase 8, choosing it (or facing it) meant starting
  with a command post, a refinery and one harvester against eleven units.
  It now fields six Arc Templars, two Lance Wardens, a Faraday, an Ion
  Carriage and a Glimmer like everyone else.
- **The enemy's own first soldier could be entombed.** _place_enemy_turrets
  tested is_buildable, which ignores units standing on the tile, and start
  forces spawn first — so on four maps the gun turret was raised on top of
  an Iron Guard and blocked the cell it stood in, stranding it until the
  turret died. It now tests occupancy too.
- A crash in army._path_unit's from==to early-out (a ternary over two array
  literals assigned to Array[Vector3], which is statically plain Array) was
  also fixed — the transport's disgorge is the first caller that ever lands
  a unit in its own target cell, so it fired three times per drop.

**Proof after fixes:** mission 2 finishes with objectives [true, true] and
mission 3 with [true]; all six missions boot with correct setup; the Flak
Coast shows five enemy AA emplacements; Luminar fields a full army; nine
selftest flags (--pelican --war --air --build --dock --gameover --shroud
--turret --closeup) clean at 164.8-165.4 FPS; eight scripts parse clean;
the exported .exe loads the new map with the flak line intact.

---

## 28. PHASE 14 NOTES: POSTURE AND THE BATTLE LINE (v2.5)

Five mechanics, all from Leon's field notes after playing v2.4.

**STANCES.** Every unit now has a posture, cycled with **Z** or from a new
sidebar row. Index 0 is always the old behaviour, so nothing rebalances
until the player deliberately changes something.

  AIRCRAFT   LOITER (6.5 m circle, as before)
             PATROL (26 m circle; fires only on what wanders into range as
             it sweeps past, and never breaks its circuit to chase). The
             point is early warning — a patrolling plane is a moving eye.
  VEHICLES   MOBILE
             ARTILLERY — rooted, hull swivels to track, x2 range and x1.6
             damage, 1.6 s to set up and 1.2 s to pack away, and no gun at
             all mid-transition. Ordering a deployed gun to move packs it
             up and marches rather than refusing.
  INFANTRY   STEADY / LIGHT FEET (x1.28 speed, takes x1.15 damage) /
             DIG IN — throws up a sandbag ring: x1.35 range, incoming cut
             to x0.45, and the ring itself soaks 75% of every hit against
             its own 420 hp. When the ring collapses the soldier is back in
             the open whether he likes it or not, and walking away loses it.

**DOUBLE-CLICK** selects every unit of that kind currently on screen —
fog-hidden and off-screen units are excluded, so you can never grab troops
you cannot see.

**FORMATIONS.** A quick right-click marches the selection as a battle line;
holding right-click for 220 ms raises faint silhouettes showing exactly
where each unit will stand, with the wheel cycling LINE / WEDGE / COLUMN /
BOX and dragging aiming the line. Release commits. Heavy armour takes the
front rank, then light tanks, scouts, riflemen, long-range infantry, and
deployed artillery and harvesters at the back.

Two things had to be solved before formations could work at all:

- Every slot inside one 2 m tile used to collapse onto the same point,
  because the last waypoint a path produced was the tile CENTRE. Paths now
  finish on the exact requested spot when it is clear and visible from the
  previous waypoint.
- The crowd push-apart pass fought the formation and scrambled it on
  arrival. Slot pitch is now derived from the largest selected unit's
  radius so that a settled formation generates zero push by construction.

**Proof:** a --stance selftest shows artillery pinned at 0.00 m drift with
range 11 -> 22 and damage x1.6, a move order packing it back to MOBILE,
LIGHT FEET at 3.70 -> 4.74 m/s taking x1.15, a dug-in soldier taking 72 hp
of 240 raw and his ring collapsing him back to STEADY under sustained fire,
PATROL widening 6.5 -> 26 m, all four shapes producing no overlapping slots
(closest pair 2.03-2.20 m, above the push-apart threshold), correct
front-to-back role ordering, and double-click selecting 5 of 5 on screen
with zero wrong kinds. Seven existing regressions clean.

A note on measuring performance here: a mid-round FPS "regression" turned
out to be GPU contention from a second game instance and Blender being
open. The pre-change exported build measured LOWER (40.9) than the new code
(69.7) under the same load. Always compare against a baseline measured at
the same moment, never against a number from a quiet machine.
