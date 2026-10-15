# The games: current rules

**Current truth** for what each module is and how it plays. The numbers live
in code tables and tune stores (named per game); the rows in `DECISIONS.md`
say why. When this doc and a decision row disagree, this doc wins unless the
row is newer; then fix this doc.

## The tournament (shell)
- 4–8 players, double elimination; each match's game is rolled from the
  enabled modules (`TourneyModules.POOL`), with a 10 s vote on which match goes first.
- Bets: the house stakes 5 a side; players bet 5–25 and winners split the pot
  by stake. Results get comments; the champion screen ends the night.
- Offline now: you plus bots. A bot-vs-bot match is rolled by the module's `simulate()`.
- Music: the Chris loops (`TourneyMusic`): Repeat Chris (lobby, range,
  bracket, results), Repeat Chris 2 (matchup, loading, champion, bosses),
  Full Chris (every game).

## bw_twins: the Black | White Twins fight
Black | White's own combat (thunder, fire, wind vs Noon and Dusk). Fewest
turns to win takes it (G4).

## aram: MOBA ARAM duel
Merr (fire mage), Temu (the kit slingshot, poison, stealth when still),
Braves (shotgun pistols). One lane with minion waves; first to 3 kills; HP
returns only on death. League's camera, controls and HUD (G3, G14, G15).
Numbers: `MobaChamps.CHAMPS`, live in `MobaTune` (F1).

## pit: MOBA Objective take
Each player leads three (themself + the two champions they didn't pick)
around the Giant (27,000 HP) in its pit. Slam every 8 s, nova every 12 s.
Smite: 600 true damage, the boss only. The last hit wins (G12).

## fps_roof: FPS Rooftop duel (prototype)
First person on the kit rooftops against a bot, first to 5. Sniper (4x
scope), shotgun, slingshot. Shift tap crouch, hold prone; RMB aims; a
CS:GO-style reticle drawn from the real spread (G20). Numbers: `FpsTune` (F1).

## mmo_raid: MMO Raid night
A WoW Classic raid of six against the Giant in a round courtyard (G22).
- **Seats:** both contestants on different classes; the other four seats are bots.
- **Classes:** warrior (tank, rage), paladin (hammer + heals), priest (healer),
  mage, hunter (Auto Shot), rogue (energy + combo points). 16 abilities each on
  1–8 and Shift+1–8: `MmoClasses.CLASSES`.
- **Rules:** WoW Classic's global cooldown, cast bars broken by moving, the
  180° facing rule, threat and taunts, auras, resurrection.
- **The Giant:** 300,000 HP; 360 a swing every 2.2 s; enrage at 300 s. One spell
  at a time, at least 5 s after the last ended:
  - Upheaval: three cracks toward players
  - Meteor Rain: 14 marked impacts
  - Giant's Bombs: a 6 m bomb on everyone; spread
  - Earthshatter: a 5 m ring; group in
- **Controls:** WoW Classic's; the camera starts behind you.
- **The verdict:** rating, your score per second against a same-class bot
  (`MmoClasses.PAR`), with -400 per mechanic failed and -1000 per death (G23).
- **Numbers:** `MmoTune` (F1).

## The Gauntlet Kit (assets for modules)
Parametric, deterministic assets in `game/src/kit/` (G17): sniper, pump
shotgun, slingshot, Dust2-mid hallway, apartment rooftops (with the G18
bridge). Build any with `GKRegistry.build(id, params).instantiate()`; shape
them in `scenes/kit_bench.tscn`.
