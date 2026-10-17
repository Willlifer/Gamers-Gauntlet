# Gamers Gauntlet

A party tournament of short games for 4–8 friends, built in Godot 4.7
(GDScript) on top of a copy of Black | White's project, for its characters,
animations, weapons and element VFX only. None of Black | White's rules,
palette or hex-tactics mechanics carry over: this is a different game.
The author's plan and rulings: the Claude Doc "Tournament Plan"
(https://claude.ai/code/artifact/fe47289b-de23-4688-8000-7b7df9058a51).

## Start here

1. `HANDOFF.md`: the state right now, and what to do first.
2. `LEDGER.md`: what is owed, blocked, waiting on play, or settled.
3. Open only the docs your task needs (table below).

## Which doc answers what (and which wins)

| Doc | Answers | Lifespan |
|---|---|---|
| `design/GAMES.md` | **What each game is now**: rules, and which code table or tune store holds its numbers. **Current truth.** | Edited in place |
| `DECISIONS.md` | **Why and when** a rule became what it is, and who ruled (Author vs Claude). Append-only; superseded rows are marked in Status. | Permanent |
| `LEDGER.md` | What's owed, blocked, awaiting play, watched or deferred. One row per item, under the four-test rule. | Weeks |
| `HANDOFF.md` | State now and what to do first. Rewritten each session, ≤ 40 lines. | One session |
| `PLAN.md` | The finish line, the stages and their status, how a module is built. | Project |
| `history/` | Session summaries, for orientation only. | Permanent |

If GAMES.md and DECISIONS disagree, GAMES.md is current, unless the DECISIONS
row is newer and the doc wasn't updated. Then fix the doc.

**End of every session:** rewrite HANDOFF, update LEDGER (close, add,
re-state), append DECISIONS rows, update GAMES.md for rule changes, and add
a `history/` summary when the session was long.

## Shape

- **The shell** (`game/src/tourney/`): lobby with join code and the character
  creator (hair style + colour, name, title, experience, Randomize), one
  settings panel for every game (`TourneySettings`, G56; `user://tourney.cfg`),
  first-time cards (`[seen]`, `-- --fresh`), Quick play (any game vs a
  bot, F10 leaves), the double-elimination bracket with slot-reel rolls (the
  top ready match plays next), the
  matchup with bets (house 5 a side, bets 5–25, winners split by stake), the
  load-in (`VersusScreen`, G42: black, both players and the challenge slam in), the
  result with comments, the champion. Offline with bots for now; online is
  stage 3 (deterministic lockstep over WebRTC, see the plan).
- **Modules** (`game/src/tourney/modules/`): one game each, behind
  `TourneyModule` (`setup(match)`, `finished(result)`, `info()`, `simulate()`).
  Register with a row in `TourneyModules.POOL` (G66): id, name, players and
  blurb as the module's `info()` says (`tourney_probe` checks they agree), the
  lobby tile's `look`, the module's `script` path, `warm` if it draws Black |
  White's VFX. The module is `load()`ed only when its game starts: never name a
  module class (or anything a game pulls in) from the shell's startup path
  (`tourney.gd`, the screens, `TourneyUI`/`Backdrop`/`Portraits`/`Settings`),
  or the whole game compiles before the lobby shows; use a path and `load()`.
  The main scene is `scenes/boot.tscn` ("Starting…", then the shell compiled a
  step per frame); `-- --boot-time` prints the steps, `tools/load_time.gd`
  times a script's compile. A game's sim should be pure state on a
  fixed tick with a seeded rng, so lockstep works later.
  - `bw_twins`: the Black | White Twins fight (thunder, fire, wind vs Noon and
    Dusk). Fewest turns to win takes it (author 10-13); wanted later: the room
    votes the winner.
  - `aram` (**out of the pool**, G60; `TourneyModules.SHELVED`, still
    `--module aram`): MOBA, the ARAM duel (`src/tourney/moba/`). Merr, Temu,
    Braves; first to 3 kills; HP back only on death; minion waves that fight
    each other, then you. League's locked camera, click to move/attack, QWER,
    flash + ignite. 1 world unit = 100 League units. Unset numbers are
    League-ish defaults marked OPEN in `moba_champs.gd`.
  - `fps_roof`: FPS: Rooftop duel (`src/tourney/fps/`, G20), first person vs a bot on the kit rooftops; bullets fly (G28).
  - `fps_mid`: FPS: Mid duel (`FpsMidModule`, G29), the same duel on the kit's Dust2-mid hallway.
  - `fps_campus`: FPS: Campus paintball (`FpsCampusModule`, G43), the duel on the Blender-built campus; paint, walk-through bushes. Every FPS life starts on the radial loadout (G43).
  - `fps_extract`: FPS: Extraction (`FpsExtractModule`, `src/tourney/extract/`, G63-G64): a Tarkov-style extract run on a forest campus generated from the seed (`GKExtractForest`); chests, green guards, scarce mags, a flare marks the extract; 14 gun variants as loot (`FpsVariants`). Plan: `design/extract/PLAN.md`.
  - `mmo_raid_easy`: MMO: Raid night (Easy) (`MmoRaidEasyModule`, G59): the Giant as pushed before G52 (`MmoSim.easy`); the player's side shared with Hard.
  - `mmo_raid`: MMO: Raid night (Hard) (`src/tourney/mmo/`, G22-G23, G52): a WoW Classic raid of eight on the Giant, WoW controls and HUD; contestants compared by grade (G33).
  - `mmo_tanks`: Planet of Tanks (`MmoTanksModule`, G46): raid night 2, the same raid against the kit tank in a campus clearing (`MmoTankFight`, `MmoTankView`, `MmoTankArena`).
  - `osrs_easy`: OSRS: Warden's Trial (Easy) (`OsrsEasyModule`, `src/tourney/osrs/easy/`, G57): the trial as pushed before G53, a frozen copy under `OsrsEasySim/View/Bot/Hud`.
  - `osrs_raid`: OSRS: Warden's Trial (Hard) (`src/tourney/osrs/`, G34, G53, G57): an OSRS raid boss on game squares and 0.6 s ticks; skulls, shields, the dagger skate, half-field fist slams; fastest kill wins.
  - `pit` (**out of the pool**, G60; still `--module pit`): MOBA, Objective take (`PitModule`, sim mode "pit"). 3v3 (each player
    plus 2 bot allies) around the Giant; smite (spell2 bind) for the last hit.
- **Scope:** more modules first, online last (G32). Verdicts (G60): OSRS, the raids and the Twins are **frozen** (9/10/9); the FPS (7) gets map and gun-model polish; the MOBA (3) is shelved.
- **The look** (G27, `src/tourney/ui/`): `TourneyTile` (menu tiles), `SlotReel` (the rolls), `TourneyBackdrop` (a game's map circling behind every screen), `TourneyPortraits` (plate portraits); palette and builders in `TourneyUI`.
- **The range** (`RangeScreen`): no longer in the lobby (G50); kept for `aram_shots`.
- **Local only (gitignored, on disk):** reference images `design/ref/`, art sources `game/art/source/` and every `.blend`, the untrimmed takes `game/audio/source/`, the author's `.docx`/`.mp4` requests. Nothing the export ships; a fresh clone lacks them, so ask the author for refs before a reference review.
- **Play look-outs:** `design/PLAYTEST.md` (a checklist per batch; nothing owed). The author's request docs: `design/requests/`.
- Black | White's own code stays under `src/core` and `src/game`; edit it only
  to expose what a module needs (e.g. `cosmetics.hair_hex`).

## Run and check

Console binary: `C:\Users\ferth\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe`, from `game/`:

- `--path .` plays (`-- --bots 3 --autostart` seats bots and starts).
- `--headless --path . --script res://tools/tourney_probe.gd`: bracket, bets and coin maths for 4, 5 and 8 players; exit 0 (give it a timeout over 600 s: the MMO sims take 10–40 s each).
- `--headless --path . --script res://tools/moba_input.gd`: the MOBA controls through real input events (G54); `tools/twins_probe.gd`: the Twins kits, fire first, the swap (G50); `--path . --script res://tools/osrs_input.gd` (**windowed**): skull-first clicks (G53d).
- `tourney_shots` puts `user://tourney.cfg` back when it ends; it also shoots the settings tabs to `design/shots/g56/`.
- `--path . --script res://tools/tourney_shots.gd`: walks every screen windowed and saves frames to `design/shots/`; exit 0.
- `--headless --path . --script res://tools/moba_probe.gd`: bot vs bot over every champion pairing; matches end, replays match; exit 0.
- `[MODULE=pit] --path . --script res://tools/aram_shots.gd`: ARAM (or the pit) on autopilot plus the range, frames to `design/shots/`; exit 0.
- `[TAG=r6] --path . --script res://tools/moba_ref_shots.gd`: the reference-review frames (duel wave, duel fight, red side, pit) at fixed seeded moments, to `design/shots/ref/<tag>_*.png`; compare against `design/ref/league_aram_hud.jpg` (G15).
  The review loop itself is the `reference-gauntlet` skill (G16): shoot, score, fix, repeat.
- Touch (G67): `--headless --path . --script res://tools/fps_touch_probe.gd` (the shooters' touch controls through real ScreenTouch/Drag events; exit 0); frames `--path . --script res://tools/fps_touch_shots.gd` then `python tools/fps_touch_sheet.py` to `design/shots/fps/touch/`; play with them on a desktop: add `--touch` after `--`.
- `--headless --path . --script res://tools/fps_probe.gd`: FPS bullets (speed, flight, hits both ways, walls) on both maps; exit 0.
- Extraction (G63): `--headless --path . --script res://tools/extract_map_probe.gd` (6 seeds: budgets, lots, chests where they claim, guard legs clear, spawns hidden, landmark coverage, hills, determinism); `tools/extract_probe.gd` (the run: chests, mags, guards, medkit, armour, the flare, the pad, the verdict); frames `[SEED=7] [TAG=r5] --path . --script res://tools/extract_map_shots.gd` to `design/shots/extract/map/` and `tools/extract_shots.gd` to `design/shots/extract/`; the gun variants `VARIANTS=1 ... tools/fps_shots.gd` to `design/shots/fps/variants/`.
- `--headless --path . --script res://tools/osrs_probe.gd`: the OSRS raid, Hard then Easy (squares, run/walk, prayer, every hazard, the half-field slams, the dagger, skulls, shields, the sigil, good and careless bot runs, replay); 102 checks, ~4 s; exit 0. Frames: `[TAG=r1] --path . --script res://tools/osrs_shots.gd` to `design/shots/osrs/`.
- `--headless --path . --script res://tools/kit_probe.gd`: the Gauntlet kit (G17): every asset at defaults, presets and parameter extremes; inverted/inward faces; determinism; export round trip; the bench's undo/redo; exit 0.
- `[ASSETS=sniper,rooftop] [TAG=r5] [FULL=1] --path . --script res://tools/kit_ref_shots.gd`: kit review sheets beside `design/ref/kit/*` to `design/shots/kit/`.
- `--path . res://scenes/kit_bench.tscn`: the kit bench (shape assets, presets, export .glb).
- Blender kit assets (G43): `"C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python game/tools/blender/gauntlet/gg_<id>.py -- --views --tag r1` rebuilds `game/art/gauntlet/<id>.glb` (pistol, deagle, marksman, carbine, auto_rifle, tank, campus); `python game/tools/blender/gauntlet/sheet.py <id> r1` makes the review sheet beside `design/ref/kit/<id>.jpg`. The contract is the docstring of `gg_common.py`; then `--headless --path . --import` and the kit probe.
- `--path . res://scenes/fps_proto.tscn`: the FPS prototype alone (G20); `[MAP=campus] --path . --script res://tools/fps_shots.gd` shoots its frames (the radial and the Dual Berettas' trick reload included) to `design/shots/fps/[map]/`.
- `--path . res://scenes/module.tscn -- --module osrs_easy` (or bw_twins, fps_roof, fps_mid, fps_campus, mmo_raid_easy, mmo_raid, mmo_tanks, osrs_raid; shelved: aram, pit): any tournament game alone vs a bot. Music everywhere in the tournament is the author's Chris loops (`TourneyMusic`, G25).
- Planet of Tanks (G46): `[RUNS=6] --headless --path . --script res://tools/mmo_tanks_probe.gd` (the cannon's stacking and the announcer, both treads' safe wedges, the smoke's profile, Loose Cannon, the flanks, bot raids, replay); frames `[TAG=r2] [CLASS=mage] --path . --script res://tools/mmo_tanks_shots.gd` to `design/shots/mmo/<tag>_tanks_*.png`; the arena alone `tools/mmo_tank_arena_shots.gd`.
- `--path . res://scenes/mmo_proto.tscn`: the MMO raid alone (class pick, then the fight). Checks: `[MODE=easy] --headless --path . --script res://tools/mmo_probe.gd` (all 96 abilities, the mechanics, the 5 s spell gap, bot raids, replay; G59's easy rules), `--headless ... tools/mmo_input.gd` (the WoW controls through real input events); frames: `[TAG=r4] [CLASS=priest] --path . --script res://tools/mmo_shots.gd` and `tools/mmo_moves_sheet.gd` (the Giant's poses) to `design/shots/mmo/`. Audio: `--headless ... tools/mmo_audio_check.gd`; re-trim the author's takes with `python tools/audio/trim_chris.py` (G24).
- F1 in a MOBA match / the range / the FPS / the raid: the live feel-number panels (G19), saved to `user://moba_tune.cfg` / `user://fps_tune.cfg` / `user://mmo_tune.cfg`.
- Black | White's self-test still runs and must stay green: `--headless --path . res://scenes/main.tscn -- --self-test` (the main scene is the tournament now, so name Black | White's; ~8 min).

## Author preferences

- Desktop first for testing; the web build later for phones.
- The author verifies by playing and by looking at frames: show them.
- Keep the module interface small; every new game is a plug-in.
- Git: commit with `-c user.name=ferth -c user.email=consumerot@gmail.com`; remote: https://github.com/Willlifer/Gamers-Gauntlet (main). Web build: `sh build_web.sh` -> `web/`, commit, push; Vercel (team bandito2) serves `web/` at https://gamers-gauntlet-wheat.vercel.app/ on every push to main (`vercel.json`, single-threaded, no special headers). Web-only: the loading screen `game/tools/web/shell.html`; Ogg twins of sfx/barks from `python game/tools/audio/web_ogg.py` (re-run after new sounds, G49).
