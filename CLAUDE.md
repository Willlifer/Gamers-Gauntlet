# Tournament (working name)

A party tournament of short games for 4–8 friends, built in Godot 4.7
(GDScript) on top of a copy of Black | White's project, for its characters,
animations, weapons and element VFX only. None of Black | White's rules,
palette or hex-tactics mechanics carry over: this is a different game.
The author's plan and rulings: the Claude Doc "Tournament Plan"
(https://claude.ai/code/artifact/fe47289b-de23-4688-8000-7b7df9058a51).

## Shape

- **The shell** (`game/src/tourney/`): lobby with join code and the character
  creator (hair style + colour, name, title, experience), the testing ranges
  (keybinds, sensitivity; `user://tourney.cfg`), the double-elimination
  bracket with visible rolls and a 10 s vote on which match goes first, the
  matchup with bets (house 5 a side, bets 5–25, winners split by stake), the
  result with comments, the champion. Offline with bots for now; online is
  stage 3 (deterministic lockstep over WebRTC, see the plan).
- **Modules** (`game/src/tourney/modules/`): one game each, behind
  `TourneyModule` (`setup(match)`, `finished(result)`, `info()`, `simulate()`).
  Register in `TourneyModules.POOL`. A game's sim should be pure state on a
  fixed tick with a seeded rng, so lockstep works later.
  - `bw_twins`: the Black | White Twins fight (thunder, fire, wind vs Noon and Dusk).
  - next: ARAM 1v1 with the author's three champions (Merr, Temu, Braves):
    click to move and attack, QWER, flash + ignite, minions. 60 auto damage,
    700 HP, one auto a second. Coloured champions on a coloured world.
- Black | White's own code stays under `src/core` and `src/game`; edit it only
  to expose what a module needs (e.g. `cosmetics.hair_hex`).

## Run and check

Console binary: `C:\Users\ferth\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe`, from `game/`:

- `--path .` plays (`-- --bots 3 --autostart` seats bots and starts).
- `--headless --path . --script res://tools/tourney_probe.gd`: bracket, bets and coin maths for 4, 5 and 8 players; exit 0.
- `--path . --script res://tools/tourney_shots.gd`: walks every screen windowed and saves frames to `design/shots/`; exit 0.
- Black | White's `--self-test` still runs and must stay green.

## Author preferences

- Desktop first for testing; the web build later for phones.
- The author verifies by playing and by looking at frames: show them.
- Keep the module interface small; every new game is a plug-in.
- Git: commit with `-c user.name=ferth -c user.email=consumerot@gmail.com`; no GitHub remote yet.
