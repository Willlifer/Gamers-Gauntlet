# Handoff — 2026-10-14 (end of the 10-13 → 10-14 sessions)

**Where:** `C:\Users\ferth\Documents\Black White Arena` → to be renamed `Documents\Gamers Gauntlet` (L-1); game in `game/` (Godot 4.7, GDScript). Gamers Gauntlet (was The Gamer, G26): a party tournament of short plug-in games. The author verifies by playing and by looking at frames; their feel is the goal, not the sim.

**Git:** branch `main`, internal only, no remote. Commit with `-c user.name=ferth -c user.email=consumerot@gmail.com` and the session trailers. Last commit: the rename, `d649402`, then the docs pass.

## What these sessions built (details: DECISIONS G1–G26, `history/2026-10-13_14-sessions.md`)
- **The shell:** lobby, creator, ranges, double-elimination bracket with rolls and votes, bets, results, champion.
- **Five modules:**
  - `bw_twins`: the Black | White Twins fight
  - `aram`: MOBA duel (Merr, Temu with the kit slingshot, Braves)
  - `pit`: Objective take, 3v3 on the Giant
  - `fps_roof`: FPS Rooftop duel
  - `mmo_raid`: MMO Raid night, six WoW classes on the Giant
- **The Gauntlet Kit** (`game/src/kit/`, GK): procedural sniper, shotgun, slingshot, Dust2-mid hallway, apartment rooftops; bench, .glb export.
- **Feel numbers live on F1** in every real-time game (MobaTune / FpsTune / MmoTune, `user://*_tune.cfg`).
- **Music:** the author's three Chris loops everywhere in the tournament (`TourneyMusic`, G25); combat sounds from the B/W sfx and barks in the raid.
- **The reference-gauntlet skill** (`~/.claude/skills/reference-gauntlet/`) polished the MOBA look, the kit and the MMO HUD.

## Run
- **Open any game alone:** `--path . res://scenes/module.tscn -- --module pit` (or `aram`, `fps_roof`, `mmo_raid`, `bw_twins`).
- **The raid with its class pick:** `res://scenes/mmo_proto.tscn`.
- **The whole tournament:** `--path .`.
- Full command list in CLAUDE.md.

## Do this first
1. **Wait for the author's playtest notes** on the MMO raid, the FPS and the music, then act on them. Don't stress-test unasked.
2. If the folder is still `Black White Arena`, finish the rename (L-1) once Godot is closed.
3. **Waiting on play:** L-3 (raid difficulty and the rating rule), L-4 (FPS feel), L-5 (Temu's stealth), L-7 (Chris loop roles).
4. **Waiting on the author:** G10 build order (online proof, character package, map maker); hand-made art for the parked lists (L-10, L-11).

**Green (2026-10-14):** B/W self-test 865/865; mmo_probe (96/96 abilities, mechanics, 5 s spell gap, raids, replay), mmo_input 13/13, mmo_audio OK, tourney_probe OK, moba_probe OK, kit_probe 601/601.
