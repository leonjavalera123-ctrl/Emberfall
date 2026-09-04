# UE5 for a Solo Godot Dev + the MCP Landscape (Aug 2026)

## 1. Licensing

- **Free until $1M lifetime gross revenue per game**, then **5% royalty** above that. Terms stable through 2026 ([Epic license page](https://www.unrealengine.com/license)).
- Since Jan 1, 2025, the **"Launch Everywhere with Epic"** program drops it to **3.5%** if you ship day-and-date on the Epic Games Store; EGS-native sales are royalty-free entirely ([CG Channel](https://www.cgchannel.com/2024/10/epic-games-to-cut-royalty-rate-on-unreal-engine-games/), [PocketGamer.biz](https://www.pocketgamer.biz/unreal-engine-royalty-fee-reducing-to-35-for-games-landing-on-epic-games-store-on-launch-day/)).
- The $1,850/seat "Creators" license only applies to non-game companies over $1M. For Leon: **effectively free forever** unless a game makes seven figures.

## 2. Hardware: RTX 4050 6GB laptop

Better than the horror stories suggest — **for low-poly with the showcase features off**:

- A dev on the Epic forums ran a static-lit UE5 project (no Lumen/Nanite/RT) at **120-200 fps on an RTX 4050 laptop** — faster than their RTX 3090 tower, because the heavyweight features were the whole cost ([forum thread](https://forums.unrealengine.com/t/my-laptop-rtx-4050-outperforms-my-rtx-3090-how-is-this-possible/1241441)).
- From the first research pass, two specifics worth keeping: **UE 5.8 (June 2026) is the final UE5 release before UE6**, so 5.7/5.8 is a stable long-term target; and this laptop's RAM is **16 GB mismatched (8+8 @ 4800)** — the editor runs, but shader compiles + editor + browser want 32 GB, so close everything else during UE sessions.
- Standard moves: Engine Scalability to Medium/Low, disable Lumen (use cheap static/unlit lighting), skip Nanite, disable realtime viewport features. A stylized RTS is exactly the workload that survives this.
- **The real constraints are RAM, CPU, and disk, not the GPU.** 16GB RAM is the documented floor and cramped with a browser + Claude Code open; 32GB is the practical minimum. Shader compilation hammers laptop CPUs for minutes-to-hours ([hardware guide](https://www.fantech.eu.org/2026/07/best-budget-laptop-for-unreal-engine-5.html)). UE + one project + derived-data cache eats 60-100GB — relevant given the C: drive history (the E: junction trick applies).

## 3. Learning curve from Godot

- Steepest first month of the big three — more terminology (GameMode/PlayerController/Pawn vs. Godot's node tree), more boilerplate ([engine comparison](https://nilo.io/articles/3d-game-engine-comparison-2026)).
- **Blueprints are not GDScript.** Visual graphs; fine for an entire small RTS, but they get unwieldy at scale, and Claude edits text vastly better than node graphs — this matters a lot for the workflow. C++ is not required for a modest-unit-count RTS.
- Community RTS resources: an 11-hour free Blueprint-only RTS tutorial ([80.lv/UNF Games](https://80.lv/articles/an-11-hours-long-tutorial-on-creating-an-rts-game-in-ue5)); 500+ unit counts push into Mass Entity/ECS, advanced territory ([250 units @ 60fps showcase](https://forums.unrealengine.com/t/rts-unit-template-a-multiplayer-rts-framework-for-ue5-mass-entity-gas-250-units-60fps/2735388)).

## 4. UE5 MCP servers

A UE5 MCP does exist — several — but the famous one is stale:

| Repo | Stars | State | Notes |
|---|---|---|---|
| [chongdashu/unreal-mcp](https://github.com/chongdashu/unreal-mcp) | 2.1k | **Last commit Apr 2025 — abandoned** | The one Leon has heard of. ~70 tools, UE 5.5, "EXPERIMENTAL". No screenshots/Python exec. |
| [flopperam/unreal-engine-mcp](https://www.flopperam.com/mcp) | — | Commercialized | Freemium: 64 tools, 46 free. Actively maintained, UE 5.5-5.7, but a product. |
| [runreal/unreal-mcp](https://github.com/runreal/unreal-mcp) | 114 | Last commit Jun 2025 | Simplest: pure Python remote execution, **no plugin install**, 15+ tools incl. Python exec + screenshots. UE 5.4+. |
| [remiphilippe/mcp-unreal](https://github.com/remiphilippe/mcp-unreal) | 68 | **Recent, UE 5.7** | **Best fit for the loop**: 49 tools — headless builds, automated tests with pass/fail, PIE screenshots, Blueprint node editing, actor spawn, Python exec. Single Go binary, Apache-2.0. |
| [sam-david/unreal-mcp](https://github.com/sam-david/unreal-mcp) | 5 | New beta | Broadest (127 tools incl. packaging), no mandatory C++ plugin, UE 5.3+ — unproven. |

**Is the Godot loop (run headless, screenshot, judge, fix) reproducible?** Yes, genuinely — UE has editor Python ([official docs](https://dev.epicgames.com/documentation/en-us/unreal-engine/scripting-the-unreal-editor-using-python)), UnrealEditor-Cmd -RenderOffscreen -unattended headless runs, and an automation test framework; remiphilippe/mcp-unreal wraps exactly that. But it is slower per iteration (editor startup + shader compiles vs Godot's near-instant headless runs) and the ecosystem churns — the most-starred repo died within a year.

## 5. RTS first project + migration

An RTS is a *reasonable* but not gentle first UE5 project. Migration is, honestly, a **near-total rewrite**: GDScript, scenes, signals and the test harness do not port. What survives: Blender/glTF assets (the Blender MCP pipeline is engine-agnostic), lore/GDD, design knowledge. Budget "restart Phase 1," not "port."

## Recommendation: wait, with a one-weekend side experiment later

Emberfall is built and the Claude-driven pipeline is proven in Godot — switching now trades that for a heavier editor, a RAM-constrained laptop, and a less mature MCP ecosystem. Nothing about UE5 licensing or hardware blocks a later move; UE6 was announced at State of Unreal 2026 and UE is not going anywhere.

**When curiosity wins (after an Emberfall milestone), the exact experiment:**
1. Free ~80GB (E: drive), install Epic Games Launcher, then **UE 5.7**.
2. New Blueprint **Top Down template**; Engine Scalability Medium; disable Lumen; enable **Python Editor Script** + **Remote Control API** plugins.
3. Add **remiphilippe/mcp-unreal** to Claude Code (fallback: runreal/unreal-mcp, zero-plugin).
4. Smoke test the loop, not a game: spawn 10 cubes, move one on click, screenshot, judge, fix. If the loop feels as tight as Godot's, try a one-map toy RTS. If not, the experiment cost one weekend.
