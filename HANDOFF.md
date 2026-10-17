# Handoff — 2026-10-16 (evening)

**Where:** `C:\Users\ferth\Documents\Gamers Gauntlet`; game in `game/` (Godot 4.7). Gamers Gauntlet: a party tournament of short plug-in games. The author verifies by playing and by looking at frames.

**Git:** branch `main`, pushed at `05e8497` (G50–G60 with a fresh web build, 10-16 evening) on the author's word; later local commits (gun models, FPS polish, the forest) wait for the next "push". Commit with `-c user.name=ferth -c user.email=consumerot@gmail.com` and the session trailers; `git add` explicit paths only (other agents share the tree). The forest agent's `FpsExtractModule` sits in the working-tree `POOL` uncommitted: it goes in with `game/src/tourney/extract/`, never alone (main failed to compile once that way).

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
- The author's session **ferth-7c** builds **FPS: Extraction** (G63–G64, `src/tourney/extract/`, `FpsVariants`, uncommitted as of this commit; its rows in DECISIONS/LEDGER/GAMES/PLAYTEST/CLAUDE.md are in the working tree, unstaged). It commits after G62; it also owns the unstaged spec()/variants hunks in `fps_bot.gd`, `fps_probe.gd`, `fps_player.gd`, `fps_tune.gd`, `fps_shots.gd` and all of `fps_weapons.gd`, `fps_viewmodel.gd`, `gk_asset.gd`, `gk_registry.gd`. Session **ferth-af** does the one push after the author plays.

## Do this first
1. **The author plays the FPS** (`design/PLAYTEST.md`: the bot's push, the sounds, the three spawn fixes, the guns) and looks at the gun sheets; nothing is owed on the frozen games.
2. **Register the extraction** (L-20) once ferth-7c commits: run `fps_probe` again (shared files), `tourney_probe`, `tourney_shots`.
3. **Next push, when the author says:** `sh build_web.sh`, commit `web/`, push (Vercel redeploys). Check the build compiles headless first (the POOL names only committed modules).

## Run
- Quick play from the lobby, or `--path . res://scenes/module.tscn -- --module osrs_easy` (bw_twins, fps_roof, fps_mid, fps_campus, mmo_raid_easy, mmo_raid, mmo_tanks, osrs_easy, osrs_raid; shelved: aram, pit). `-- --fresh` shows the first-time cards again.

**Green (this evening):** osrs_probe (102 ok, 4 s), tourney_probe (twice, ~5 min), tourney_shots (twice), moba_probe, aram_shots; kit_probe (G61), fps_probe (G61 in a scratch copy; G62 in the tree with ferth-7c's hunks present), fps_audio_check, fps_shots on all three maps.
**Not rerun:** mmo_probe, mmo_tanks_probe, the input checks, twins_probe, osrs_input, osrs_shots, the B/W self-test (none of their code changed from here). `game/tools/_tmp/p.gd` is a stray nobody claims.
