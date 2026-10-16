# Handoff — 2026-10-16

**Where:** `C:\Users\ferth\Documents\Gamers Gauntlet` (renamed 10-16); game in `game/` (Godot 4.7). Gamers Gauntlet: a party tournament of short plug-in games. The author verifies by playing and by looking at frames.

**Git:** branch `main`, ~30 local commits since `1f1a933` (origin/main), **not pushed**: the author says when. Commit with `-c user.name=ferth -c user.email=consumerot@gmail.com` and the session trailers. The web build (`web/`) predates this batch.

## This session (G50–G56, `history/2026-10-16_session.md`)
The author's notes doc `“The Gamer”.docx` (text: `design/requests/2026-10-16_the_gamer.md`), worked by six parallel agents, then the author's follow-ups:
- **Lobby/Twins (G50):** every tile shows, Randomize, ranges gone; your three Twins fighters get two elements + two weapons, fire first.
- **FPS (G51, G51c):** recoil, scopes, reticle, sway, optics, trail, muzzle flash; Dust spawns; rooftop rebuilt (shots now cross the court, walkable bridge, the floor below). Author: "guns look great, physics feel good".
- **Raids (G52):** consumables bar, faster spins, combo at 75%, burning Cinderbrand; tanks without the announcer, parked light tanks, x1.5 at 15%; first-time cards; callouts as visuals.
- **OSRS (G53 a–d):** phantoms (mage/ranger) fire, shields, the lightning dagger and the skate, skull phases after the author's video, pose-read middle-column slam.
- **MOBA (G54):** left move / right attack, cast modes, tooltips, +25% reaches, 0.3 s cast root, lower camera, pit pings and rocks.
- **Look (G55):** skipping, godly float, cool walk, cast gestures; champions dressed.
- **Settings (G56):** one tabbed panel opened from every game.

## Do this first
1. **The author plays** with `design/PLAYTEST.md` (look-outs, nothing owed) and sends notes.
2. **Push when the author says:** `sh build_web.sh`, commit `web/`, push (Vercel redeploys). Check the PiP scopes, the transparency and the flash in the browser.

## Run
- Quick play from the lobby, or `--path . res://scenes/module.tscn -- --module osrs_raid` (aram, pit, fps_roof, fps_mid, fps_campus, mmo_raid, mmo_tanks, osrs_raid, bw_twins). `-- --fresh` shows the first-time cards again.

**Green (2026-10-16):** tourney_probe (needs a >600 s timeout now), tourney_shots, moba_probe, moba_input, fps_probe, kit_probe 1210/1210, mmo_probe RUNS=20, mmo_tanks_probe, mmo_input, mmo_audio_check, osrs_probe, osrs_input (windowed), twins_probe.
**Not green:** mmo_probe at its default 6 raids: bot grade spread 9.9 vs the 8 limit (was 15.3 before this batch; passes at RUNS=20).
**Not rerun:** the B/W self-test (no `src/game`/`src/core` edits), moba_ref_shots.
