# Gamers Gauntlet — build plan

The finish line: **a game night.** 4–8 friends join by link, a double-
elimination bracket rolls short games (1–3 minutes each), they bet coins on
every match, and one of them is the champion (G1, G6).

The author's full plan and rulings live in the Claude Doc "Tournament Plan"
(https://claude.ai/code/artifact/fe47289b-de23-4688-8000-7b7df9058a51); this
file is the working summary and the status. The quality bar is "the spirit,
not the letter" (G9): fun and polished enough to enjoy, with commercial polish
later on the games that prove fun. Decisions go in `DECISIONS.md`.

## Status (2026-10-15)

| Stage | State |
|---|---|
| 1 The shell (offline, bots) | done: lobby (Smash-style tiles, Quick play), creator, ranges, slot-reel bracket, bets, results, champion; the map backdrop (G27) |
| 2 Modules | six playable offline: Twins, ARAM, Objective take, FPS Rooftop duel and Mid duel (bullets fly, G28-G29), MMO Raid night. **More modules come next (G32).** |
| 2b The Gauntlet Kit | first five assets done (G17); more on demand per module |
| 2c Feel and sound | live F1 tuning everywhere real-time (G19); the Chris loops as the music (G25); raid SFX |
| 3 Online | last (G32): lockstep over WebRTC for the MOBA and raid games, then the shooter model (G7, G8; L-8) |
| 4 Character package, map maker | not started (G10; L-9) |
| 5 Art | parked lists in LEDGER L-10, L-11 |

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

## Gates

The author plays, then says go, change or stop. Each module stays a
plug-in: `setup(match)`, `finished(result)`, `info()`, `simulate()`.

## Waiting on the author
- Which module next (G32: modules before online).
- The raid's burn in play, then its verdict (L-3); MOBA polish (L-6).
- A verdict on the new tournament look (L-14).
