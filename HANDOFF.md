# Handoff — 2026-10-16 (evening)

**Where:** `C:\Users\ferth\Documents\Gamers Gauntlet`; game in `game/` (Godot 4.7). Gamers Gauntlet: a party tournament of short plug-in games. The author verifies by playing and by looking at frames.

**Git:** branch `main`, ~37 local commits since `1f1a933` (origin/main), **not pushed**: the author says when. Commit with `-c user.name=ferth -c user.email=consumerot@gmail.com` and the session trailers; `git add` explicit paths only (other agents share the tree). The web build (`web/`) predates all of this.

## The verdicts (G60, `history/2026-10-16_session.md` "Evening")
- **OSRS Warden's Trial** Easy / Hard (G57): 9/10, "genuinely fun". **Frozen.**
- **Raids** (Raid night Easy / Hard G59, Planet of Tanks): 10/10. **Frozen.**
- **Twins:** 9/10. **Frozen.**
- **FPS:** 7/10, "super fun"; polish the maps and the gun models (open).
- **MOBA:** 3/10; **pulled from the pool** (`TourneyModules.SHELVED`; code, tools and `--module aram` / `pit` stay). Back only on a new combat pitch from the author (L-6).

## Three agents in this tree tonight
- **This one:** G57 committed (`2ead7c2`; the probe hang fixed), the MOBA pulled (`8232709`), the docs (this commit).
- **Gun models** (`tools/blender/gauntlet/*`, `art/gauntlet/*.glb`, `src/kit/*` materials): **in flight**, results unknown here (L-18).
- **FPS polish** (`src/tourney/fps/*`, `fps_probe`, `fps_shots`, audio): **in flight**, results unknown here (L-12).
- Elsewhere, the author's own agent builds a **procedural forest / Tarkov-style extraction** (`src/tourney/extract/`, `design/extract/`, untracked here): not ours; register it when its commits land (L-20).

## Do this first
1. **Look at what the other agents committed** (`git log`, `git status`): register the FPS polish and the gun models in LEDGER (L-12, L-18), GAMES.md and the history; then the forest (L-20) if it landed.
2. **The author plays the FPS** when the polish is in (`design/PLAYTEST.md`); nothing else is owed on the frozen games.
3. **Push when the author says:** `sh build_web.sh`, commit `web/`, push (Vercel redeploys).

## Run
- Quick play from the lobby, or `--path . res://scenes/module.tscn -- --module osrs_easy` (bw_twins, fps_roof, fps_mid, fps_campus, mmo_raid_easy, mmo_raid, mmo_tanks, osrs_easy, osrs_raid; shelved: aram, pit). `-- --fresh` shows the first-time cards again.

**Green (this evening, after G57 and the pull):** osrs_probe (102 ok, 4 s), tourney_probe (twice, ~5 min), tourney_shots (twice), moba_probe, aram_shots.
**Not rerun:** fps_probe, kit_probe, mmo_probe, mmo_tanks_probe, the input checks, twins_probe, osrs_input, osrs_shots, the B/W self-test (none of their code changed from here; the FPS and kit files are mid-edit by the other agents).
