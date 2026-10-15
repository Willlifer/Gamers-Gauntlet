# The games: current rules

**Current truth** for what each module is and how it plays. The numbers live
in code tables and tune stores (named per game); the rows in `DECISIONS.md`
say why. When this doc and a decision row disagree, this doc wins unless the
row is newer; then fix this doc.

## The tournament (shell)
- 4–8 players, double elimination; each match's game is rolled from the
  enabled modules (`TourneyModules.POOL`). The rolls are slot reels: games,
  then first-round players, stopping in a cascade, the last pick rolling in
  over 0.5 s. The top ready match (layout order) plays next: no vote (G27).
- Lobby: Smash-style tiles. Tournament, the two ranges, and **Quick play**:
  any game at once against a bot, nothing counts, back to the lobby at the
  end or on F10. The creator is a card on the right (under a quarter of the
  screen). In a tournament match, F10 forfeits (G27).
- Look: ink panels over a game's map circling slowly behind every screen
  (`TourneyBackdrop`; the matchup shows that match's map when it has one),
  one warm accent, gold for winners, blue and red for the two sides. The
  bracket has two sides (winners from the left, losers from the right, the
  grand final under the trophy), with name plates and portraits (G27).
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
- **Bullets fly** (G28): rifle and shotgun rounds (one per pellet), and the
  bot's, travel straight at 5x the slingshot ball's full-draw speed (375 m/s;
  `bullet_speed`) with a trail (`bullet_trail`, 8 m), and hurt whoever they
  meet: rifle 85 (head x2.5), pellet 13 (x1.5); the bot's 34, a head 100.
  The bot's accuracy roll now picks where it aims; the bullet still has to land.

## fps_mid: FPS Mid duel (prototype)
The same duel on the kit's Dust2-mid hallway (G29): you at the T end, the bot
in the tower half of the lane. Same guns, bullets, bot and `FpsTune`.

## mmo_raid: MMO Raid night
A WoW Classic raid of six against the Giant in a round courtyard (G22).
- **Seats:** a raid of eight. Both contestants (any classes, the same one allowed)
  and one bot of each class; the Giant scales with the raid's size (G39).
- **Classes:** warrior (tank, rage), paladin (hammer + heals), priest (healer),
  mage, hunter, rogue (energy). **Eight abilities each on 1–8** (G39), in the
  same order for every class: spammable, strong, self steroid, team steroid,
  self heal, self cleanse, super, the class's pick. `MmoClasses.CLASSES`
  (the old sixteen on `shelf`).
- **Rules:** WoW Classic's global cooldown, cast bars broken by moving, the
  180° facing rule, threat and taunts, auras, resurrection.
- **The Giant:** 300,000 HP; 360 a swing every 2.2 s; enrage at 300 s. One spell
  at a time, at least 5 s after the last ended:
  - Upheaval: three cracks toward players
  - Meteor Rain: 14 marked impacts
  - Giant's Bombs: a 6 m bomb on everyone; spread
  - Earthshatter: a 5 m ring; group in
  - **Cinderbrand** (its own clock: 20 s, then every 45 s; G30): an
    unavoidable burn on everyone, 25% of max HP over 30 s. Run it off (each
    metre walked takes 0.5 s off), get cleansed (paladin Cleanse, priest
    Dispel Magic) or be healed through it.
- **Scorched Earth** (G37): an 8 s warning, then at 45 s the half of the
  courtyard behind the Giant (from the tank) burns, 25% of max HP a second;
  from 1:30 it turns counter-clockwise about the Giant, 9 deg/s. Red chevrons
  out of the fire mark the advancing edge, gold chevrons into it the retreating one (G38).
- **Below 50%:** no more text warnings, only "You're on your own now." **Below 25%:**
  the spell rotation runs twice as fast (G35). Timer enrage at 300 s: 5x damage.
- **Controls:** WoW Classic's; the camera starts behind you.
- **The verdict: a grade** (G33, `MmoGrade`): output against a same-class
  bot (`MmoClasses.PAR`) 35, mechanics done 30, AoEs avoided 15, survival
  12, activity 8 → 0-100 → S 96 / A 88 / B 76 / C 64 / D 50 / F. The higher
  letter wins, then the higher score. The report card shows the parts.
- **Numbers:** `MmoTune` (F1).

## osrs_raid: OSRS Warden's Trial
After Tombs of Amascut's Wardens, on game squares and 0.6 s ticks (G34).
- **You:** 99 HP, 99 prayer; protect from magic / missiles / melee (1 2 3 or
  the buttons beside the inventory) drain a point every 3 ticks. 12 sharks and
  4 prayer potions, 25% each; eating delays your next attack 3 ticks.
- **Weapons:** bow 10-45 every 4 ticks, staff 15-55 every 5; 85% to land;
  range 10 squares. Pick one first; the other sits in the inventory to swap.
- **The Warden (1,200 HP):** projectiles every 5 ticks (4 in phase 3), magic
  or ranged, landing 3 ticks later; a melee smack next to it. Specials every
  11 ticks: lightning (phase 1); boulders, slam, lightning (phase 2); and in
  phase 3 lightning, boulders, slam, twin volleys, and the far row torn out
  every 18 ticks down to 5 rows.
- **Sun Sigil** (the twist): stand on it as it ignites → next 3 attacks x2.
- **Verdict:** the same seeded fight for both; a kill beats a death, then
  the faster kill, then more damage, then less taken. Numbers: `OsrsTune` (F1).

## The Gauntlet Kit (assets for modules)
Parametric, deterministic assets in `game/src/kit/` (G17): sniper, pump
shotgun, slingshot, Dust2-mid hallway, apartment rooftops (with the G18
bridge). Build any with `GKRegistry.build(id, params).instantiate()`; shape
them in `scenes/kit_bench.tscn`.
