# Emberfall: 1940 ⚙️

A real-time strategy game in the spirit of *Command & Conquer: Red Alert*, built
in **Godot 4.7**. An alternative Earth, an alternative 1940 — steam, iron, and
stolen starfire.

> In 1861 the sky fell and seeded the world with **emberstone** — a mineral that
> made steam engines mighty and lightning tameable. The old nations starved,
> broke, and reformed into four new powers. Now, in 1940, the largest untouched
> emberstone field ever charted has been found beneath a dead kingdom, and all
> four powers have sent their armies.
>
> You are a **Commander**. Gather emberstone, raise your base, fortify it, and
> erase the enemy from the map.

---

## ▶️ How to run it

You need [Godot 4.7](https://godotengine.org/) or newer.

**Windows:** double-click `Play Emberfall.bat`.

**Any platform:** open `godot/project.godot` in the Godot editor and press F5.

If textures or models look wrong on a fresh clone, run `Import Assets.bat` once
— Godot needs to build its import cache the first time.

---

## 🎮 What's in it

The game is playable end to end: harvest emberstone, build a base, train an
army, and fight an AI commander who builds and attacks back.

- **Base building** — power, refineries, barracks, vehicle works, defences
- **Economy** — emberstone harvesting with haulers that path back to a refinery
- **Combat** — infantry, vehicles, and turrets, with line-of-sight rules that
  let elevated shooters fire over wall segments
- **An AI opponent** that expands, masses units, and launches repeated assaults
- **Campaign and skirmish modes**, a settings screen, and an intro sequence

---

## ⚔️ The four powers

| Power | Byname | Character |
|---|---|---|
| **Karvath Iron Concord** | The Anvil of the World | Heavy armour, slow, punishing |
| **Aurelian League** | The Thousand Sails | Mobile, naval-minded, opportunistic |
| **Ashfall Compact** | The Meek Who Refused | Cheap swarms, guerrilla tactics |
| **Luminar Covenant** | The Second Sun | Emberstone-fired energy weapons |

Each faction shares one baseline unit roster and skews it with multipliers and a
signature mechanic, so a new faction is a data change rather than a new codebase.

---

## 📂 Repository map

```
godot/            the game itself (Godot 4.7 project)
  main.gd         match loop and the top-level state machine
  world.gd        terrain, map generation, line of sight
  unit.gd         movement, combat, squad behaviour
  buildings.gd    construction, placement, power
  ai.gd           the enemy commander
  economy.gd      emberstone, harvesting, refineries
  campaign.gd     mission flow layered on skirmish
  models/         unit and structure meshes (.glb)
  sounds/         announcer lines and effects
blender/          the .blend sources those meshes are exported from
concepts/         concept art the models were built from
tools/            asset generators - terrain carving, flags, announcer, SFX
```

## 📖 Design documents

The design is written down before it is built, and the documents are kept in
the repo rather than in someone's head:

- **[LORE.md](LORE.md)** — the world bible: how this Earth diverged, what
  emberstone is, and who the four powers are
- **[GAME_DESIGN.md](GAME_DESIGN.md)** — the buildable spec: economy, combat
  model, pathfinding, AI, and the ten-phase build plan
- **[VERTICAL_SLICE.md](VERTICAL_SLICE.md)** — what is in scope for the slice,
  and the acceptance criteria it has to meet

---

## 🛠️ How this was built

A personal project, built to learn Godot and GDScript. Written with heavy help
from Claude Code, following the phase plan in `GAME_DESIGN.md` — each of the ten
phases was specified, built, and reviewed before the next one started. The 3D
assets come from a concept-art → Hyper3D → Blender pipeline; `tools/` holds the
scripts that generate terrain, flags, and audio.

The two Blender sources over GitHub's 100 MB per-file limit are not in the repo;
the `.glb` exports built from them are, so the game runs from a clone.
