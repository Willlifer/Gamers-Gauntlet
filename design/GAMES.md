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
First person on the kit rooftops against a bot, first to 5. Shift tap crouch,
hold prone; RMB aims; a CS:GO-style reticle drawn from the real spread (G20).
Numbers: `FpsTune` (F1); the guns: `FpsWeapons.SPECS`.
- **Loadout** (G43): before every life, the radial (`FpsLoadoutMenu`, after
  CS's buy wheel): pick a primary (bolt rifle, marksman rifle 2.5x, pump
  shotgun, personal carbine, automatic rifle, Dual Berettas, or Random);
  10 s, Esc keeps the last pick; you can't be hurt while picking. Price tags
  are for show (the Berettas cost $1 for no reason). The sidearm is rolled:
  the 92FS pistol, or 50% of the time the Desert Eagle (bigger boom: flash,
  kick). The pistol replaces the slingshot. 1 primary, 2 sidearm.
- **Triggers:** carbine and automatic rifle are full auto; pistols semi-auto
  (one shot per pull). **Dual Berettas:** LMB fires the left gun, RMB the
  right (no aiming in), 15 rounds each; R or an empty gun does the trick
  reload: the mags drop, both guns backflip up, two fresh mags rise and the
  guns land on them.
- **The bot** picks a random primary each life and fires it the gun's way
  (bursts, pellets, singles).
- **Bullets fly** (G28): rifle and shotgun rounds (one per pellet), and the
  bot's, travel straight at 5x the slingshot ball's full-draw speed (375 m/s;
  `bullet_speed`) with a trail (`bullet_trail`, 8 m), and hurt whoever they
  meet: rifle 85 (head x2.5), pellet 13 (x1.5); the bot's 34, a head 100.
  The bot's accuracy roll now picks where it aims; the bullet still has to land.

## fps_mid: FPS Mid duel (prototype)
The same duel on the kit's Dust2-mid hallway (G29): you at the T end, the bot
in the tower half of the lane. Same guns, bullets, bot and `FpsTune`.

## fps_campus: FPS Campus paintball (G43)
The same duel on the Blender-built autumn campus (`campus.glb`): a stone
chapel with its tower in the middle, brick halls on the flanks, a curving
road as the open lane, inflatable bunkers, 86 bushes. Spawns at the west
(you) and east ends. **Paint:** every miss leaves a splat in the shooter's
colour (you blue, the bot pink). **Bushes:** walk through them; past 3 m,
more than a metre of leaves between hides you from the bot (and the bot
likes to wait in them).

## mmo_raid: MMO Raid night
A WoW Classic raid against the Giant in a round courtyard (G22).
- **Hidden class: the Tank** (G44). A small, faint tank in the pick screen's
  bottom-right corner ("???"); click it to drive. Plays exactly like the
  hunter (same numbers, eight slots and PAR, renamed: Coax Burst, HEAT Round,
  Autoloader, Overwatch, Field Repair, Pop Smoke, Main Gun, Full Reverse);
  the kit tank at 0.42 scale with the crewman in the hatch. Never a bot:
  bots and bot seats only draw from `MmoClasses.ORDER`; hidden classes are
  `MmoClasses.HIDDEN`.
- **Seats:** a raid of eight. Both contestants (any classes, the same one allowed)
  and one bot of each class; the Giant scales with the raid's size (G39).
- **Classes:** warrior (tank, rage), paladin (hammer + heals), priest (healer),
  mage, hunter, rogue (energy). **Eight abilities each on 1–8** (G39), in the
  same order for every class: spammable, strong, self steroid, team steroid,
  self heal, self cleanse, super, the class's pick. `MmoClasses.CLASSES`
  (the old sixteen on `shelf`). Each class leans into its theme (G41):
  the warrior charges (Shield Charge, Colossus Smash, Taunt close 25-30 m);
  the paladin's light spills onto the raid (Crusader Strike, Word of Glory,
  Hammer of Wrath and Flash of Light heal everyone near); the priest works
  over time (Renew on an ally heals, on the Giant is Shadow Word: Pain;
  Vampiric Embrace DoTs the Giant; Penance, Desperate Prayer and Divine Hymn
  leave HoTs); the mage's fire and frost keep burning (Frostbite, Ignite,
  Pyroblast's long burn); the hunter and rogue move on their spells (Chimera
  Shot rolls back, Master's Call bounds in, Disengage leaps out and crits
  the next shot; Ambush shadowsteps in, Cloak flickers out, Sprint dashes).
  Bots never dash into a hazard.
- **Rules:** WoW Classic's global cooldown, cast bars broken by moving, the
  180° facing rule, threat and taunts, auras, resurrection.
- **The Giant:** 300,000 HP; 360 a swing every 2.2 s; enrage at 300 s. One spell
  at a time, at least 5 s after the last ended:
  - Upheaval: three cracks toward players
  - Meteor Rain: 14 marked impacts
  - Giant's Bombs: a 6 m bomb on everyone; spread. Half of them leave burning
    ground (4 m, 15 s, 350 a second; G40)
  - Earthshatter: a 5 m ring; group in
  - **Cinderbrand** (its own clock: 20 s, then every 45 s; G30): an
    unavoidable burn on everyone, 25% of max HP over 30 s. Run it off (each
    metre walked takes 0.5 s off), get cleansed (paladin Cleanse, priest
    Dispel Magic) or be healed through it.
- **Scorched Earth** (G37): an 8 s warning, then at 45 s the half of the
  courtyard behind the Giant (from the tank) burns, 25% of max HP a second;
  from 1:30 it turns about the Giant at 9 deg/s in bursts: 15 s turning, 30 s
  resting; the first burst counter-clockwise, then a random way each time (G40). Red chevrons
  out of the fire mark the advancing edge, gold chevrons into it the retreating one (G38).
- **Below 50%:** no more text warnings, only "You're on your own now." **Below 25%:**
  the spell rotation runs twice as fast (G35). Timer enrage at 300 s: 5x damage.
- **Controls:** WoW Classic's; the camera starts behind you.
- **The verdict: a grade** (G33, `MmoGrade`): output against a same-class
  bot (`MmoClasses.PAR`) 35, mechanics done 30, AoEs avoided 15, survival
  12, activity 8 → 0-100 → S 96 / A 88 / B 76 / C 64 / D 50 / F. The higher
  letter wins, then the higher score. The report card shows the parts.
- **Numbers:** `MmoTune` (F1).

## mmo_tanks: Planet of Tanks (raid night 2, G46)
The same raid of eight, classes, controls, HUD and grade as Raid night,
against the kit tank parked in a round clearing cut out of the forest
campus (`MmoTankArena`). The boss's brain is `MmoTankFight`; its view
`MmoTankView`; numbers on F1 (`MmoTune`, section "Planet of Tanks"); the
logo `art/ui/planet_of_tanks_logo*.png` (made by `tools/logo/planet_of_tanks_logo.py`)
on the lobby tile, the load-in and the class pick. Every attack is
telegraphed on the ground with a vague line of text ("The turret climbs
skyward…").
- **Main cycle, the cannon blast:** every `cannon_every` s a 120° wedge from
  the tank to the edge (`cannon_warn` s of telegraph) at the closest warrior
  or paladin (else the closest anyone). Each extra body caught raises
  everyone's damage by `cannon_stack` (x1.75, x2.5…); the announcer calls
  DOUBLE / TRIPLE / QUAD / MEGA HIT in big gold letters (and out loud when the
  OS has a voice and `audio/general/text_to_speech` is on). A warrior or
  paladin drags it away from the raid. Paused during barrage, Loose Cannon
  and the ram.
- **Specials** (one at a time, `spell_gap` between, like the Giant):
  - *Barrage:* the gun climbs; 10 rounds land at random (every third on
    someone), each leaving a burning crater until 1 s after the next special
    is announced.
  - *Smokescreen:* fired ahead of the tank, it spreads (`smoke_speed`) over
    the whole map, thick at its front (`smoke_band`), thin behind it
    (`smoke_core`); it poisons, slows and cuts damage; then thins out as
    slowly. Keep away, then rush through the front.
  - *Treadburn* (from 75%): one tread or both rev red to bright red, dust
    fills that side (all but 10° fore and aft) over `tread_warn` s, then
    explodes. Both at once (`tread_both` chance): only the 20° wedges fore
    and aft are safe.
- **75%:** the treads glow red; **Loose Cannon:** bright red treads, a 3 s
  side-to-side wobble, then it spins and sprays the middle 75% of the
  clearing for 4 s. Then the treads cool to orange and its **flanks** take
  `flank_mult` (x1.5) damage for the rest of the fight.
- **50%: the ram**, twice: it turns, rocks fore and aft (`ram_rock`), charges
  to the edge (flattening anyone in its path), then fires a huge 110° arc back
  across the clearing (hug the wall beside it). Then it drives home.
- **25%:** two light tanks roll out and chase people (`add_*`); bots focus
  them. All specials (Loose Cannon and the ram included) in the mix.
- **10%:** everything `tank_rush_rate` (x2) faster.
- **Bots:** the first warrior (else paladin) holds the gun north, close in;
  the other warriors and paladins stand farther out; the raid south;
  telegraphs: the nearest safe spot (`MmoTankFight.safe_spots`).

## osrs_raid: OSRS Warden's Trial
After Tombs of Amascut's Wardens, on game squares and 0.6 s ticks (G34).
- **You:** 99 HP, 99 prayer; protect from magic / missiles / melee (1 2 3 or
  the buttons beside the inventory) drain a point every 3 ticks. 12 sharks and
  4 prayer potions, 25% each; eating delays your next attack 3 ticks.
- **Weapons:** bow 10-45 every 4 ticks, staff 15-55 every 5; 85% to land;
  range 10 squares. Pick one first; the other sits in the inventory to swap.
- **The Warden (1,200 HP):** projectiles every 5 ticks (4 in phase 3), magic
  or ranged, landing 3 s (5 ticks) after launch from any distance, so a near
  one is visibly slow; the prayer is judged on impact. They never pause for a
  special: they keep coming through the slams and the tear-out (G45). A melee
  smack next to it. Specials every
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
