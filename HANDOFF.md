# Handoff — 2026-10-17

**Where:** `C:\Users\ferth\Documents\Gamers Gauntlet`; game in `game/` (Godot 4.7). Gamers Gauntlet: short plug-in games in a party shell. The author verifies by playing and by looking at frames.

**Git:** branch `main`, pushed with a fresh web build through G67, on the author's word. Build web from a clean worktree of HEAD, never the shared tree (`git worktree add --detach <scratch> HEAD`, copy `game/.godot`, `--headless --import`, `--export-release "Web" ../web/index.html`, copy `web/index.*` back, commit, push). Commit with `-c user.name=ferth -c user.email=consumerot@gmail.com` and the session trailers; `git add` explicit paths only.

## Where it stands
- **Paused.** The author: "proof of concept is there". New direction G68: **a party game, not a tournament**; everyone plays at once. The shape is the author's call (online per L-8, phones as controllers, or drop-in rounds). Don't start it unasked.
- **Frozen:** OSRS Easy/Hard (9/10), the raids and Planet of Tanks (10/10), the Twins (9/10). **MOBA** shelved (G60, L-6).
- **FPS** (7/10, "super fun"): G61 gun polish, G62 nav and sounds, G63-G65 Extraction (dusk, calm guards, the frame-rate fix).

## Today (2026-10-17)
- **G66 light startup:** a friend's browser froze on load (a ~7 s script compile on the main thread). Now `scenes/boot.tscn` shows "Starting… n/12" and compiles in 12 per-frame steps; each game's code loads only when picked (`TourneyModules` is a static table). Exported first lobby frame 3.7 s → 2.0 s; 291 → 130 scripts at launch. Live since `a3b4b04`.
- **G67 touch controls** for the four shooters (`src/tourney/fps/fps_touch.gd`): a floating stick, look by drag, FIRE / AIM / RELOAD / SWAP / JUMP / CROUCH, USE + MED in Extraction, II for pause. On for coarse-pointer web and native mobile; `-- --touch` or `?touch=1` force it. Probe `tools/fps_touch_probe.gd` 38/0. **Not tried on a real phone (L-22).** Frames in `design/shots/fps/touch/` (local, gitignored).

## Do this first
1. If the author returns with phone notes: L-22 and the PLAYTEST batch for G67.
2. If they pick a party-game shape: G68 is the starting point; the sims are deterministic and lockstep-ready (G7, G8).

## Run
- Quick play from the lobby, or `--path . res://scenes/module.tscn -- --module osrs_easy` (bw_twins, fps_roof, fps_mid, fps_campus, fps_extract, mmo_raid_easy, mmo_raid, mmo_tanks, osrs_easy, osrs_raid; shelved: aram, pit). `-- --fresh` shows the first-time cards; `-- --boot-time` prints the startup steps; `-- --touch` shows the phone overlay.

**Green at G67:** import 0 errors (clean worktree), fps_probe, extract_probe, tourney_probe, fps_touch_probe 38/0. At G66: tourney_shots, all 10 games via quick play, twins_probe, the B/W self-test 865/865.

## Open author questions
- G68: the party-game shape.
- OSRS hard: the centre column in both fist halves? Extraction: 50 ft at the 1.25× scale (~19 m, set 15.24 m)? L-18 the gun-art round; L-21 the campus quad and the brick scale.
