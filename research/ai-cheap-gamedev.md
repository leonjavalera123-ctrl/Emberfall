# Cheap AI Game Dev for Solo Devs — 2025/26 Practices vs. Leon's Stack

## 1. What people actually run, and what it costs

The consensus workflow ([Summer Engine's 2026 stack guide](https://www.summerengine.com/blog/ai-tools-for-indie-game-developers)) is: one coding agent + 1-2 metered asset generators + free tiers for everything else. A fully-paid version of that stack runs **$50-90/mo**:

| Job | Paid norm | Free/local norm |
|---|---|---|
| Code | Copilot $10, Cursor/Claude $20+ | — (nobody serious codes AI-free locally on 6 GB) |
| 2D art | Midjourney $10-30 | SDXL local; Flux GGUF Q4 is the 6 GB floor — below Q4 hands/text degrade, ~2 min/image ([Local AI Master](https://localaimaster.com/blog/run-flux-on-low-vram-gpu)) |
| 3D | Meshy Pro $20/200cr, Tripo $24/200cr, Rodin $29-149, CSM $30-119 ([StraySpark studio test](https://www.strayspark.studio/blog/generative-3d-tools-comparison-meshy-rodin-tripo-csm-2026)) | Hunyuan3D, TRELLIS |
| Music | Suno Pro $10 (commercial rights start here; free tier is non-commercial and losing downloads) ([terms.law](https://terms.law/ai-output-rights/suno/), [pricing](https://techjacksolutions.com/ai-tools/suno/suno-pricing/)) | **ACE-Step 1.5 — benchmarks between Suno v4.5 and v5, <4 GB VRAM** ([GitHub](https://github.com/ace-step/ACE-Step-1.5)) |
| SFX | ElevenLabs (10k free credits/mo but **no commercial use on free**; Starter $6/mo unlocks it) ([BIGVU](https://bigvu.tv/blog/elevenlabs-pricing-2026-plans-credits-commercial-rights-api-costs/)) | Stable Audio Open 1.5 — built for SFX/textures, ~5.9 GB VRAM ([paper](https://arxiv.org/html/2407.14358v1)); Freesound CC0 |
| Voice | ElevenLabs Starter $6 / Creator $22 | Kokoro-82M (Apache-2.0, runs on **CPU**) ([setup](https://localaimaster.com/blog/kokoro-tts-local-setup)) |

StraySpark's real-world estimate: a 300-asset indie game for **under $100 total over two months** by mixing tools' cheap tiers — the common pattern is subscribe-one-month, batch-generate, cancel.

## 2. Local on 6 GB: competitive vs. not

**Genuinely competitive (Leon already has all of these):** music (ACE-Step ≈ Suno-paid quality, $0), SDXL images, image→3D meshes (Hunyuan3D), and — additions he lacks — SFX (Stable Audio Open, barely fits) and TTS (Kokoro on CPU, zero VRAM contention).

**Where paid wins:** (a) **topology and rigging** — every local image→3D output needs retopo/UVs/rigging by hand; Meshy 6's quad remesh + A/T-pose control and Tripo's auto-rig are exactly what the $20-24/mo buys ([comparison](https://ideate.xyz/blogs/posts/ai-3d-model-comparison-trellis-tripo-meshy-rodin-hunyuan)); (b) **Flux-class image quality** — 6 GB Q4 is painful, which is what Leon's Artlist/Nano-Banana already covers; (c) **cloned/emotional voice** — no commercially-safe local equivalent.

## 3. Pitfalls

- **License traps in "free":** Meshy and Tripo free tiers are CC BY 4.0 — commercial OK **with attribution**; paid = full ownership ([Meshy help](https://help.meshy.ai/en/articles/16102098-can-i-use-meshy-assets-commercially), [Tripo](https://costbench.com/software/ai-3d-generation/tripo-ai/free-plan/)). ElevenLabs free and Suno free are flat-out non-commercial. **XTTS-v2 (CPML) and F5-TTS (CC-BY-NC) are non-commercial despite being "open source"** ([license guide](https://www.promptquorum.com/power-local-llm/local-tts-voice-cloning-piper-coqui-xtts)) — Kokoro and Chatterbox (Apache/MIT) are the safe local voices. Also skim the Tencent Hunyuan community license before a commercial ship (it has territory/MAU clauses).
- **Steam:** disclosure required since Jan 2024; the **Jan 2026 rewrite exempts dev tools like code assistants** — Claude Code needs no disclosure, but shipped AI art/audio/text does; live-generated content needs written guardrails ([AI Trace](https://www.aitrace.org/company/valve/practice/e62f0dfa-ea81-47ca-98d5-ffbab5fd6814)). Real cost is stigma: disclosed games average **~53% fewer reviews** ([Tildee](https://www.tildee.com/steam-ai-disclosure-may-hurt-game-sales-and-player-engagement/)), and obvious AI art has tanked launches with 100k wishlists ([PC Gamer](https://www.pcgamer.com/gaming-industry/steam-week-in-review-a-touch-of-ai-is-all-it-takes-to-trigger-backlash-as-a-promising-new-indie-falls-afoul-of-slop-skeptics/)).
- **Style drift:** mixing generators per-asset yields a mismatched game. Standard fix is a style LoRA from 15-30 curated, consistent images; classic failure modes are watermark bleed and character over-representation ([Civitai guide](https://civitai.com/articles/26044/considerations-for-style-lora-creation)).
- **Quality ceilings:** AI music is "appropriate but not memorable"; AI meshes always need cleanup — plan hand-finishing for hero assets.

## 4. Ranked recommendations for Leon

1. **Change nothing in the core** — Godot+Claude Code, ACE-Step, Fooocus/SDXL, Hunyuan3D is already the $0 version of a stack others pay $50-90/mo for. His only real spends (Claude sub, Artlist) are the two categories where 6 GB local genuinely can't compete.
2. **Add voice + SFX for $0:** Kokoro-82M (Apache, CPU — no GPU fight with ComfyUI) for NPC lines; Stable Audio Open 1.5 in ComfyUI for SFX. Never ship XTTS/F5-TTS output commercially. If he later wants cloned voices: ElevenLabs Starter, $6/mo ($5 annual), is the single most defensible paid add.
3. **Train a per-game SDXL style LoRA** from his best Artlist concepts (Civitai's on-site trainer costs pennies if 6 GB local training is too tight) — this fixes style drift *and* lets locked-style SDXL replace most Nano-Banana concept spend, stretching the 130-credit Artlist budget to hero shots only.
4. **Use Tripo's free 300 credits/mo (CC BY, credit "Tripo" in your credits screen) + free Mixamo auto-rig for characters** — the one asset class where Hunyuan3D's lack of rigging hurts; a single $20 Meshy Pro month only when batch-producing a full character roster.
5. **Steam hygiene:** write the disclosure (art/music/3D yes, Claude Code no), keep AI output for props/background, hand-finish capsule art and hero characters — that's what separates the disclosed games that survive review-bombing from the ones that don't.
