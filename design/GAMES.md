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
- Lobby: Smash-style tiles. Tournament and **Quick play**: any game at once
  against a bot, nothing counts, back to the lobby at the end or on F10; the
  grid sizes its rows so every game in the pool shows (G50). The creator is a
  card on the right (under a quarter of the screen) with **Randomize** (name
  from the bot pool, title, hair, outfit, armour) and a settings gear. In a
  tournament match, F10 forfeits (G27). The testing ranges are gone (G50).
- **Settings** (G56, `TourneySettings`): one panel, tabs MOBA / Shooter /
  Raid / OSRS / General, opened from the lobby gear (General), the MOBA
  champion select (MOBA), O in the FPS buy phase (Shooter), the raid class
  pick (Raid) and the OSRS weapon pick (OSRS); pick clocks wait while it is
  open. Stores unchanged: `user://tourney.cfg` (`[binds]`, `[moba]`,
  `[fps_binds]`, `[audio]`, `[seen]`) and the tune cfgs. Raid and OSRS keys
  are listed read-only (hardcoded in their views).
- **First-time cards** (G52b, G53c): the first time a profile plays a raid or
  the OSRS trial, a ~10 s skippable card explains the bar/inventory and the
  key mechanics (it explains; the fight gives no extra help). `[seen]` flags;
  `--fresh`, the "every time" toggles, or General → "Show first-time cards again".
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
turns to win takes it (G4). Your three carry two elements (equal rank; every
element skill offers both) and two weapons ("Swap weapon" under Attack, free):
thunder + dark with bow / staff; fire + dark with lance / staff; wind +
thunder with bow / daggers (G50, `BWFightModule.KITS`). Fire is the fastest
unit on the court, so it opens every cycle. Noon and Dusk move with the godly
float (G55). Check: `tools/twins_probe.gd`.

## aram: MOBA ARAM duel
Merr (fire mage), Temu (the kit slingshot, poison, stealth when still),
Braves (shotgun pistols). One lane with minion waves; first to 3 kills; HP
returns only on death. League's camera and HUD (G3, G14, G15).
Numbers: `MobaChamps.CHAMPS` and `MobaChamps.SHAPES` (every reach, speed and
shape, read by casts, the indicator, tooltips and bots), live in `MobaTune` (F1).
- **Controls (G54):** left click moves only; right click attacks the enemy
  under / nearest the cursor (on empty ground it moves). Cast mode in
  settings: Quick (press casts), Slow (press shows range + shape, press or
  left click casts, right click / Esc cancels), Release (hold shows, release
  casts). Flash and ignite/smite always cast on press. Hover any ability for
  a tooltip. Flash is yellow, smite teal, each labelled.
- **Numbers (G54):** every reach +25% (autos Merr 687, Temu 625, Braves 531;
  areas unchanged); champions 1400 HP; Q/W/E/R root the caster 0.3 s, then
  fire (`cast_until`); flash 525; Braves' E 106; Merr's Q 30% slower, W
  erupts 30% slower, R at half speed. Camera pitch 47.6°; the auto-attack
  ring hides after 30 s.
- **Look (G55, `MobaDress`, `GGAnim`):** Merr floats (godly float) in mage
  gear (hat, robe, scarf); Temu skips in ranger gear (feathered cap, quiver
  strap); Braves cool-walks in pauldron, plated legs and a shell bandolier,
  gun steel grey along his leg. Every Q/W/E/R plays a cast gesture timed to
  the stop. Hidden Temu: invisible to the opponent, 75% transparent to his own side.

## pit: MOBA Objective take
Each player leads three (themself + the two champions they didn't pick)
around the Giant (27,000 HP) in its pit. Slam every 8 s, nova every 12 s.
Smite: 600 true damage, the boss only. The last hit wins (G12).
- **G54:** the Giant stands at (5.5, 0), the east half by the wall, among
  seven mirrored rocks that block walking, skillshots and sight; its damage
  is down 75% (auto 32.5, slam 55, nova 40). Each player's own champion has
  2x health and damage; only the players carry smite. **Pings:** V = go in,
  C = hold, at the cursor (12 s, own team only); bot allies answer. The tick
  order alternates sides, so a same-tick smite race is even.

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
- **Feel (G51, G51c; author: "guns look great, physics feel good"):**
  - Recoil: the Desert Eagle's punch carried to the sniper, marksman and
    shotgun; the carbine about doubled. F1 "Recoil per gun": a preset per
    gun (Desert Eagle, Rifle, Sniper, Shotgun, Pistol, Carbine, Baked) plus a 0–3x trim.
  - Reticle: `cross_gap` 0, tighter standing still (`rest_spread` 0.45),
    looser running (`move_spread` 4.5). Sway 2.3 with sideways drift, doubled
    scoped; per gun 0.7 (pistols, automatic rifle, carbine), 1.0 (snipers).
  - Pistols aimed at 0.66 m from the eye; scopes 0.11 m off the eye. A
    picture-in-picture lens on the sniper, marksman and scoped rifles.
  - **Optics** (automatic rifle, carbine; `FpsOptic`): red dot (12%
    parallax), scope (PiP), or irons; picked on the radial, V cycles;
    defaults red dot / irons.
  - Trail 30 m, fading in over 1.1 m from the barrel. `FpsMuzzleFlash`: a
    white core, tongues, orange glow, per gun; no black box.
  - Run speed 6.6; the floaty 12 m/s is `campus_speed`, campus only.
  - Settings (sensitivity, FOV, `FpsBinds` keys): O in the buy phase.
- **Rooftop map (G51c):** mirrored roofs (same cover and spawns), more cover
  (ducts, a water tank, skylights, HVAC); each block's top storey is open
  below, by a ramped stairwell; the bridge is walkable (ramps). The parapet
  fences only stop bodies now (`GKAsset.BARRIER_LAYER`), so shots and sight
  cross the court. The bot follows you downstairs; it does not use the bridge.

## fps_mid: FPS Mid duel (prototype)
The same duel on the kit's Dust2-mid hallway (G29). Same guns, bullets, bot
and `FpsTune`. **G51:** each end has a crate-and-wall T screen with two
hidden spawn pockets; the match seed picks the pocket for each life. Crate
stacks break the long sight lines into lanes. The bot walks only where a
straight line is clear (`FpsWorld.walk_clear`) and hunts you.

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
- **Two builds, two modules** (G59): `mmo_raid` "MMO: Raid night (Hard)",
  the fight below with every G52 change, and `mmo_raid_easy` "MMO: Raid
  night (Easy)" (`MmoRaidEasyModule`), the Giant as pushed before G52
  (1f1a933). Both in Quick play and the bracket. The player's side is the
  same in both: classes, the 1–8 action bar, the consumables bar, keys, HUD,
  first-time card, grade and PAR. Only the Giant differs (`MmoSim.easy`,
  `MmoSim.EASY`, `MmoSim.tune()` / `spin_warn()`):
  | | Easy | Hard |
  |---|---|---|
  | Floor first turns | 1:30 | 1:10 |
  | Rest between bursts | 30 s | 12 s |
  | Chevrons flash before a turn | 10 s before the first, 2 s before each burst | 1 s (`scorch_spin_warn`) |
  | Ring + bombs back to back below 75% | never | yes (`combo_at`, `combo_fuse`) |
  | Cinderbrand look | smoulders (licks of fire) | the player on fire |
  Kept in easy though newer than 1f1a933: the consumables bar, the lone-arrow
  chevrons, the 25%/enrage edge pulse and glowing Giant (G52b), the
  first-time card. F1 changes to the easy-only numbers above don't reach easy.
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
- **Consumables (G52, both raids, `MmoItems`):** a second bar on Shift+1–8:
  healing and mana potions, healthstone, Elixir of Giants' Might, Restorative
  (cleanses, Cinderbrand too), Swiftness, Stoneshield, Dense Dynamite; each
  on its own cooldown, off the GCD. A use counts toward activity; potion
  heals aren't healing done. Bots use them. PAR re-measured.
- **G52 changes (hard only for the floor, the pairs and the flames; G59):** the floor turns from 70 s, resting 12 s, with 1 s of
  warning (`scorch_spin_warn`); chevrons are lone arrows (no backward W).
  After 75%, Earthshatter and the bombs come back to back (4 s,
  `combo_fuse`). Cinderbrand sets the player visibly on fire. The 25%
  speed-up and the timer enrage show as a screen-edge pulse and a glowing,
  ember-throwing Giant (G52b).
- **Numbers:** `MmoTune` (F1).

## mmo_tanks: Planet of Tanks (raid night 2, G46)
The same raid of eight, classes, controls, HUD and grade as Raid night,
against the kit tank parked in a round clearing cut out of the forest
campus (`MmoTankArena`). The boss's brain is `MmoTankFight`; its view
`MmoTankView`; numbers on F1 (`MmoTune`, section "Planet of Tanks"); the
logo `art/ui/planet_of_tanks_logo*.png` (made by `tools/logo/planet_of_tanks_logo.py`)
on the lobby tile, the load-in and the class pick. Every attack is
telegraphed on the ground only: no announcer text since G52/G52b except the
pull line. (The text lines described below were removed; the visuals stay.)
- **Main cycle, the cannon blast:** every `cannon_every` s a 120° wedge from
  the tank to the edge (`cannon_warn` s of telegraph) at the closest warrior
  or paladin (else the closest anyone). Each extra body caught raises
  everyone's damage by `cannon_stack` (x1.75, x2.5…); a stack of red
  chevrons (one per body) and the multiplier pop over each player caught
  (G52b; the banner and voice are gone). A warrior or
  paladin drags it away from the raid. Paused during barrage, Loose Cannon
  and the ram.
- **Specials** (one at a time, `spell_gap` between, like the Giant):
  - *Barrage:* the gun climbs; 10 rounds land at random (every third on
    someone), each leaving a burning crater (a red disc with a bright rim,
    drawn over the smoke, G52) until 1 s after the next special is announced.
  - *Smokescreen:* a smoke grenade, ground-targeted: the gun lobs a canister
    at the spot under a random raider (marked grey while it flies), and from
    there it spreads (`smoke_speed`) over
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
  `flank_mult` (x1.5) damage for the rest of the fight (shown by pulsing
  flank plates, orange rings and a "Soft Flanks" icon, G52b).
- **50%: the ram**, twice: it turns, rocks fore and aft (`ram_rock`), charges
  to the edge (flattening anyone in its path), then fires a huge 110° arc back
  across the clearing (hug the wall beside it). Then it drives home.
- **25%:** two light tanks roll out (dust, a camera nudge) and park back to
  back 13 m out on the raid's side; they take turns firing into a red 70°,
  17 m wedge each (700 every 1.6 s each; 32,000 HP for six). Beside them is
  safe; a dead tank's wedge goes. Optional, but killing them buys room (G52).
  All specials (Loose Cannon and the ram included) in the mix.
- **15%:** everything `tank_rush_rate` (x1.5) faster (`tank_rush_at`; G52),
  shown by a red-orange screen-edge pulse, hot treads and exhaust flames.
- **Bots:** the first warrior (else paladin) holds the gun north, close in;
  the other warriors and paladins stand farther out; the raid south;
  telegraphs: the nearest safe spot (`MmoTankFight.safe_spots`).

## osrs_raid: OSRS Warden's Trial
After Tombs of Amascut's Wardens, on game squares and 0.6 s ticks (G34).
Two modes, two games in the pool (G57): **Easy** (`osrs_easy`, "OSRS:
Warden's Trial (Easy)") and **Hard** (`osrs_raid`, "(Hard)"). Both share
`OsrsTune` (F1; a label says when a number is one mode's only), the
settings' OSRS tab and the first-time card (each mode its own lines and
`[seen]` key).

### Easy (`osrs_easy`, G57): the trial before G53
A frozen copy of the trial as pushed at 1f1a933 (`src/tourney/osrs/easy/`,
`OsrsEasySim/View/Bot/Hud`); keep its rules as they were.
- **You:** as Hard, but the inventory is the other weapon, sharks and prayer
  potions only (no dagger, no damage potion).
- **The Warden (1,200 HP):** fires the prayable projectiles itself, every 5
  ticks (4 in phase 3, plus a 35% twin volley of the other style a tick
  behind), 3 s flight, judged on impact. Specials every 11 ticks (10 in
  phase 3): lightning, boulders, slam.
- **Slam:** the floor glows, then lands: east (columns 8-14), then west (0-6),
  then both sides (0-5 and 9-14), 4 ticks apart; the centre is always safe.
- **Rows:** in phase 3 the far row is torn out every 18 ticks (`rip_every`),
  down to 5 rows.
- No skulls, shields, phantoms' shots or pose-read slams. Sun Sigil and the
  verdict as Hard.

### Hard (`osrs_raid`): G53 with G57's changes
- **You:** 99 HP, 99 prayer; protect from magic / missiles / melee (1 2 3 or
  the buttons beside the inventory) drain a point every 3 ticks. 12 sharks and
  4 prayer potions, 25% each; eating delays your next attack 3 ticks.
- **Weapons:** bow 10-45 every 4 ticks, staff 15-55 every 5; 85% to land;
  range 10 squares. Pick one first; the other sits in the inventory to swap.
- **Inventory (G53):** also a 4-dose damage potion (bow/staff x1.2 for 40
  ticks) and the **lightning dagger**: 1 damage every tick, melee (straight
  next to the target, not diagonal). Clicking a target walks to a square
  beside it and strikes on the tick you arrive (one command), so a chain of
  clicks **skates** up a line of targets, one per tick at most. Swapping
  weapons caps the wait at the new weapon's speed (min 1 tick).
- **The Warden (1,200 HP):** prayable projectiles every 5 ticks, landing 3 s (5 ticks) after launch; the prayer is judged on impact;
  they keep coming through the slams (G45). **No enrage (G57):** the same
  rate in every phase, no twin volleys, no faster specials. On screen, magic is cast by the
  **mage** phantom (west; robes, staff, the orb leaves the staff tip) and
  arrows loosed by the **ranger** phantom (east, bow), each winding up the
  tick before (G53d; visual only). The Warden does the specials and a melee
  smack next to it. Specials every 11 ticks: lightning; boulders (no shadow,
  only the landing marker); slam.
- **Slam (G57, after G53d's poses):** three hits 4 ticks apart at any HP.
  A raised fist slams its own half: west fist columns 0-7, east fist 7-14
  (the centre with either), so the other half is safe. The first two hits
  are one fist each (seeded order), the third both fists: everything but the
  centre column (7). Each pose shows 4 ticks before its hit; a marker along
  the top row lights gold over the columns it spares, red over the rest.
- **Rows:** the farthest row is torn out per 8% HP lost (`rip_pct`), down to 5 rows.
- **Shields (G53b):** from tick 30, every 35 ticks, it shields against magic,
  then bowfire, by turns; that style does 0 (a blue or green bubble and an icon).
- **Skull phases (G53b-d):** at 75 / 50 / 25% its HP holds and it is
  shielded; 5–10 skulls rise in two rows either side of a lane near you. One
  hit breaks a skull; they charge 2 + 1.67 ticks per skull (swell, shake,
  ring pink to white-hot), and each one left bursts for 15. Skate them with
  the dagger. A click on or near a skull always targets it. Skulls never
  rise during a slam (they wait), and no slam starts during skulls. Shown by
  purple screen edges, a skull burst over the Warden and "Rise, and burn!".
- **Sun Sigil** (the twist): stand on it as it ignites → next 3 attacks x2.
- **Verdict:** the same seeded fight for both; a kill beats a death, then
  the faster kill, then more damage, then less taken. Numbers: `OsrsTune` (F1).

## The Gauntlet Kit (assets for modules)
Parametric, deterministic assets in `game/src/kit/` (G17): sniper, pump
shotgun, slingshot, Dust2-mid hallway, apartment rooftops (with the G18
bridge). Build any with `GKRegistry.build(id, params).instantiate()`; shape
them in `scenes/kit_bench.tscn`.
