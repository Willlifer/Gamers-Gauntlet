# Handoff — 2026-10-16 (evening)

**Where:** `C:\Users\ferth\Documents\Gamers Gauntlet`; game in `game/` (Godot 4.7). Gamers Gauntlet: a party tournament of short plug-in games. The author verifies by playing and by looking at frames.

**Git:** branch `main`, pushed at `59e5f90` with a fresh web build (G50–G65), on the author's word. Build web from a clean worktree of HEAD, never the shared tree. Commit with `-c user.name=ferth -c user.email=consumerot@gmail.com` and the session trailers; `git add` explicit paths only.

## The verdicts (G60, `history/2026-10-16_session.md` "Evening")
- **OSRS Warden's Trial** Easy / Hard (G57): 9/10, "genuinely fun". **Frozen.**
- **Raids** (Raid night Easy / Hard G59, Planet of Tanks): 10/10. **Frozen.**
- **Twins:** 9/10. **Frozen.**
- **FPS:** 7/10, "super fun"; polish the maps and the gun models (open).
- **MOBA:** 3/10; **pulled from the pool** (`TourneyModules.SHELVED`; code, tools and `--module aram` / `pit` stay). Back only on a new combat pitch from the author (L-6).

## Three agents in this tree tonight
- **This one:** G57 committed (`2ead7c2`; the probe hang fixed), the MOBA pulled (`8232709`), the docs (this commit).
- **Gun models** (G61, `3495bce` `d24bb75` `6dfadda`): kit shader relief/checker/speckle, a see-through variant (the carbine's mag), the muzzle-flash flipbook, three glb rebuilds. Blind scores 28 → 29/50; the rest is sculpt/painted art (L-18, the author decides from `design/shots/kit/final_<id>_before_after.png`).
- **FPS polish** (G62, `17ebb66`): `FpsNav` + a bot that paths, peeks and retreats; `FpsAudio` (36 synthesized sounds + B/W's pool); `FpsMapPolish` (spawn screens, a Dust stack, campus walls). L-12 settled. Sheets `design/shots/fps/polish/<map>_before_after.png`.
- **FPS: Extraction** (session ferth-7c, G63–G64, `2553a2c`): the forest extraction run, 14 gun variants, scarce ammo. L-20 awaiting play; L-21 (the campus quad, the brick scale) waits for the author.

## Do this first
1. **The author playtests** everything since `05e8497` (`design/PLAYTEST.md`): the FPS polish, Extraction (`--module fps_extract`), and the gun sheets (`design/shots/kit/final_<id>_before_after.png`).
2. **Then push, on the author's word:** build web from a clean worktree of HEAD (`git worktree add --detach <scratch> HEAD`, copy `game/.godot`, `--import`, `--export-release "Web"`), copy `web/` back, commit, push. Never export from the shared tree.

## Run
- Quick play from the lobby, or `--path . res://scenes/module.tscn -- --module osrs_easy` (bw_twins, fps_roof, fps_mid, fps_campus, fps_extract, mmo_raid_easy, mmo_raid, mmo_tanks, osrs_easy, osrs_raid; shelved: aram, pit). `-- --fresh` shows the first-time cards again.

**Green on clean HEAD after Extraction (ferth-af):** import with 0 script errors, fps_probe, tourney_probe. ferth-7c: extract_probe 78/0, extract_map_probe, kit_probe 4227/0. **Earlier this evening:** osrs_probe (102 ok, 4 s), tourney_probe (twice, ~5 min), tourney_shots (twice), moba_probe, aram_shots; kit_probe (G61), fps_probe (G61 in a scratch copy; G62 in the tree with ferth-7c's hunks present), fps_audio_check, fps_shots on all three maps.
**Not rerun:** mmo_probe, mmo_tanks_probe, the input checks, twins_probe, osrs_input, osrs_shots, the B/W self-test (none of their code changed from here).
