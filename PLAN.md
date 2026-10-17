# Gamers Gauntlet — build plan

The finish line: **a game night.** 4–8 friends join by link, a double-
elimination bracket rolls short games (1–3 minutes each), they bet coins on
every match, and one of them is the champion (G1, G6).

The author's full plan and rulings live in the Claude Doc "Tournament Plan"
(https://claude.ai/code/artifact/fe47289b-de23-4688-8000-7b7df9058a51); this
file is the working summary and the status. The quality bar is "the spirit,
not the letter" (G9): fun and polished enough to enjoy, with commercial polish
later on the games that prove fun. Decisions go in `DECISIONS.md`.

## Status (2026-10-16, evening)

| Stage | State |
|---|---|
| 1 The shell (offline, bots) | done: lobby (tiles, Quick play, Randomize), creator, slot-reel bracket, bets, load-in, results, champion; the map backdrop (G27); one settings panel (G56) |
| 2 Modules | eleven built, **nine in the pool** (G60): Twins 9/10 (frozen); FPS Rooftop, Mid, Campus 7/10; Raid night Easy + Hard and Planet of Tanks 10/10 (frozen); OSRS Easy + Hard 9/10 (frozen). ARAM and Objective take 3/10, **out of the pool** (code kept, `--module aram` / `pit`). |
| 2a FPS polish + forest | **now:** map polish, bot pathing and sounds (L-12), gun models (L-18), both by their own agents; the procedural forest / Tarkov-style extraction by the author's other agent (L-20) |
| 2b The Gauntlet Kit | assets on demand per module (G17, G43) |
| 2c Feel and sound | live F1 tuning everywhere (G19); the Chris loops (G25); raid SFX; FPS sounds owed (L-12) |
| 3 Online | last (G32): lockstep over WebRTC for the raids, OSRS and Twins, then the shooter model (G7, G8; L-8) |
| 4 Character package, map maker | not started (G10's items 2 and 3; nothing owed until the author asks) |
| 5 Art | parked lists in LEDGER L-10, L-11; gun art moved to L-18 (owed) |

## How a module is built

1. **A pure sim** on a fixed tick with a seeded rng (determinism is
   replay-checked, ready for lockstep).
2. **Bots** that play it, so `simulate()` can roll a bot-vs-bot match and a
   probe can play hundreds.
3. **A view and HUD** on Black | White's characters and the Gauntlet Kit.
4. **A tune store and F1 panel** for every feel number.
5. **A probe** (rules, mechanics, replay), **an input check** where controls
   matter, and **a frame tool** at fixed seeded moments.
6. **A reference gauntlet** when the author gives a look to match
   (`reference-gauntlet` skill): shoot, blind-review, fix, repeat; finish
   with before/after composites.
7. Register in `TourneyModules.POOL`; log the rulings; update `design/GAMES.md`.
   A game the author pulls goes to `TourneyModules.SHELVED` (G60): playable by
   id, never rolled.

## Gates

The author plays, then says go, change or stop. Each module stays a
plug-in: `setup(match)`, `finished(result)`, `info()`, `simulate()`.
Frozen games (G60) take no changes until the author asks.

## Waiting on the author
- The FPS after the polish lands (maps, bot, sounds, gun models): a replay (L-16).
- The forest / extraction sim: when and how it joins the pool (L-20).
- A new combat pitch, if the MOBA is ever to come back (L-6).
