# Emberfall: 1940 — Vertical Slice

**Locked 2026-08-01.** One mission, finished to the standard a stranger would
judge the whole game by. Nothing outside this document gets worked on until a
stranger has played it to a win screen.

The test this slice must pass:

> A person who has never played an RTS downloads the build, opens it, and
> reaches the victory screen without asking anyone a question.

---

## In scope

**The mission: M1 OPERATION LANDFALL** (Act I, `cradle_landing.txt`, Karvath vs
Ashfall, `ai_tech_limit: infantry`). Its three existing goals stay exactly as
they are — they already form a teaching curriculum:

1. `own` boiler + barracks → teaches building and the power system
2. `muster` 8 iron_guard → teaches production and economy
3. `kill_hq` → teaches combat and gives the win

**Guided onboarding.** Contextual prompts fired by game state during M1 only.

**Settings screen.** Volume, fullscreen, resolution — reachable from the main
menu *and* mid-match.

### One necessary consequence

Settings must be reachable while playing, so the pause overlay gains a
`SETTINGS` entry and a `QUIT TO MENU` entry. That is the minimum required to
make the chosen scope usable — not an invitation to build the full pause menu.
`RESTART MISSION` is **out**.

---

## Out of scope — parked until the slice ships

Everything below works today and stays untouched. This list exists so that
"just one more thing" has to be a deliberate decision, not a drift.

| Parked | Note |
|---|---|
| Missions 2–12, Acts II–IV | Stay playable; receive zero polish |
| Skirmish / FFA / 2v2 modes | Stay playable; not part of the slice |
| MCV crawler landing mode | M1 uses an established base |
| Pelican air transport | Shipped, untouched |
| Ashfall burrow tunnels | Designed, not built — stays not built |
| Bug-report hotkey | Deliberately deferred |
| Win/lose screen polish | Current VICTORY/DEFEAT + R stays |
| Restart Mission in pause | Out |
| Mipmaps + anisotropic filtering | Real improvement, but not slice-blocking |
| Group pathfinding / flow fields | The RTS scaling wall. Not triggered at M1's unit counts |
| Colorblind faction identifiers | M1 is 2 factions; matters at 4. Park it |
| Localization | Park, but do not hardcode new strings carelessly |

---

## Acceptance criteria

EARS form, because each maps 1:1 onto a selftest assertion.

### Onboarding

- **AC-1** WHEN M1 begins, THE SYSTEM SHALL display a prompt naming the first
  objective and the control needed to act on it.
- **AC-2** WHEN the player has not issued a move order within 20s of M1
  starting, THE SYSTEM SHALL prompt that right-click moves selected units.
- **AC-3** WHEN the player selects a building tab item they cannot afford or
  lack the prerequisite for, THE SYSTEM SHALL state the specific reason.
- **AC-4** WHEN a goal completes, THE SYSTEM SHALL acknowledge it and name the
  next objective.
- **AC-5** WHILE power generated is below power drawn, THE SYSTEM SHALL warn
  that low power makes turrets hold fire.
- **AC-6** Prompts SHALL fire only in M1, and each SHALL appear at most once
  per mission.

### Settings

- **AC-7** THE SYSTEM SHALL provide Master, Music and SFX volume sliders that
  take effect immediately without restart.
- **AC-8** THE SYSTEM SHALL provide a fullscreen toggle and a resolution
  selector.
- **AC-9** WHEN settings change, THE SYSTEM SHALL persist them to `user://` and
  reapply them on next launch.
- **AC-10** THE SYSTEM SHALL make settings reachable from the main menu and
  from the pause overlay.
- **AC-11** WHEN the player sets a volume to zero, the corresponding audio
  SHALL be silent — verified by bus volume, not by a UI value.

### Regression

- **AC-12** All existing selftest flags SHALL remain green.
- **AC-13** Framerate SHALL stay within 3% of the 164.8–165.1 baseline.
- **AC-14** Missions 2–12 SHALL remain completable; onboarding SHALL NOT fire
  in them.

---

## Implementation notes

**Audio buses do not exist yet.** `audio.gd` uses an `AudioStreamPlayer3D` pool
plus a UI `AudioStreamPlayer` pool, and `music.gd` its own players — all setting
`volume_db` per player. There is no `default_bus_layout.tres`.

Volume sliders therefore require, in order:
1. Create Master / Music / SFX buses.
2. Route `music.gd` players to Music and both `audio.gd` pools to SFX.
3. Have settings drive `AudioServer.set_bus_volume_db`, converting with
   `linear_to_db` so the slider is perceptually linear.

Per-player `volume_db` stays as-is — it is per-sound mixing and is orthogonal
to bus level.

**Onboarding should be data, not engine.** `campaign.gd` already evaluates
goals in `tick()` with a hooks system, and missions are pure data. Add a
`hints` array to the M1 entry with `{trigger, text, once}` records evaluated in
the same tick. New hints then cost zero engine code, matching how
`prebuild`/`grant`/`veterans` already work.

**Menu screens follow an established shape.** `menu.gd` is a `CanvasLayer` with
`_show_root` / `_show_campaign` / `_show_skirmish` / `_show_lore` and a
`_clear()`. `_show_settings()` fits that pattern directly.

**The music must keep playing over the settings screen.** `music.gd` is
deliberately excluded from the PAUSABLE list so the score plays ducked over
pause. Do not change that.

---

## Verification

Each AC gets a selftest flag, following the existing convention:

| Flag | Proves |
|---|---|
| `--onboard` | AC-1..AC-6: run M1 headless, assert hint fire order and once-only |
| `--onboard-off N` | AC-14: no hints fire in mission N |
| `--settings` | AC-7..AC-9: set each value, save, reload, assert round-trip |
| `--busvol` | AC-11: set SFX to zero, assert bus volume is -inf, not just UI |
| `--settingsshot` | Screenshot of the settings screen for visual review |

Existing regression flags that must stay green: `--selftest`, `--ai`,
`--gameover`, `--mission2`, `--missioncheck`, `--killhq`, `--ffa`, `--allied`,
`--mcv`, `--choke`, `--jam`, `--musiccheck`, `--unlockcheck`.

---

## Definition of done

1. All 14 acceptance criteria pass their selftest flags.
2. All existing regression flags green, FPS within 3% of baseline.
3. Exported build runs from a clean folder on a machine that has never had
   Godot installed.
4. Pushed to a restricted itch.io page with `butler`.
5. **Five strangers** have played it. At least three reached the win screen.

Item 5 is the one that counts. The rest is preparation for it.
