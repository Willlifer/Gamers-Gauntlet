# Handoff — 2026-10-15

**Where:** `C:\Users\ferth\Documents\Black White Arena` → still to be renamed `Documents\Gamers Gauntlet` (L-1); game in `game/` (Godot 4.7). Gamers Gauntlet: a party tournament of short plug-in games. The author verifies by playing and by looking at frames.

**Git:** branch `main`, internal only. Commit with `-c user.name=ferth -c user.email=consumerot@gmail.com` and the session trailers.

## This session (G27–G32, `history/2026-10-15_session.md`)
- **Playtest rulings (G31):** the FPS feels great; Temu's stealth stays; the Chris loops are fine; MOBA polish is the author's; the raid's verdict is shelved.
- **Build order (G32):** more modules first, online last.
- **The tournament look (G27):** Smash-style lobby tiles with **Quick play** for every game (F10 leaves). The creator is a card on the right. The bracket rolls are slot reels and has two sides with portraits. There's no vote: the top ready match plays next. A game's map circles behind every screen.
- **FPS:** bullets travel at 5× the slingshot ball with a trail and damage what they hit, both ways (G28). New module **FPS: Mid duel** on the Dust hallway (G29).
- **Raid: Cinderbrand (G30):** an unavoidable burn worth 25% HP over 30 s; run it off, get cleansed or be healed through it.
- **New module: OSRS: Warden's Trial (G34).** Game squares and 0.6 s ticks. You pray against projectiles and dodge lightning, boulders, slams and the row tear-out. The twist is the Sun Sigil. The fastest kill wins.
- **Raid verdict: a grade (G33):** output, mechanics, AoEs avoided, survival and activity, weighted into S-F. The higher grade wins. There is a report card at the end.

## Do this first
1. **The author plays:** the look (L-14), the raid with Cinderbrand and the grade (L-3), and the OSRS Warden's Trial (L-15). Act on their notes.
2. **Rename the folder (L-1).** On 10-15 the lock was two hung headless `tourney_probe` runs from 10-14, 21:36 (not the editor). The auto-mode permission check blocked killing them. The author ends them in Task Manager, then `Rename-Item` and update the memory paths. The probe itself passes in ~46 s; the hang didn't reproduce.
3. **Next module:** the author picks (G32).

## Run
- Quick play from the lobby, or `--path . res://scenes/module.tscn -- --module fps_mid` (aram, pit, fps_roof, fps_mid, mmo_raid, bw_twins).
- The whole tournament: `--path .`. Full command list in CLAUDE.md.

**Green (2026-10-15):**
- tourney_probe OK; tourney_shots OK (10 screens).
- fps_probe 17/17 (new); osrs_probe OK (new); kit_probe 601/601.
- mmo_probe OK (Cinderbrand checks, 20/20 bot kills, replay); mmo_input OK; mmo_audio OK.
- moba_probe and the B/W self-test were not rerun: their code wasn't touched.
