# Ledger

One row per tracked item. An item belongs here only if it passes all four tests:
1. It's discrete.
2. It has a state that can change.
3. Forgetting it costs something.
4. No test already guards it.

Bugs fixed in the same session never land here. A closed item moves to
**Settled** with its date; IDs never change.

**States:**

| State | Meaning |
|---|---|
| BLOCKED | Needs a decision; the decider is named. |
| OWED | Agreed work, not yet done. |
| AWAITING PLAY | A tuning question only play can answer. |
| WATCH | No work now; a named trigger turns it into work. |
| DEFERRED | Deliberately not now, with the reason. |

Last reviewed: 2026-10-16 evening (the author's verdicts, G60). Play look-outs live in `design/PLAYTEST.md`, not here.

## Live

| ID | Item | State | Unblocked by / note |
|---|---|---|---|
| L-2 | The Twins module should be decided by a room vote (G4); today the fewest turns wins. | OWED | Needs online play or a local vote screen. The Twins are frozen at 9/10 (G60): only the vote is still open. |
| L-6 | MOBA polish (the numbers marked OPEN in `moba_champs.gd`, feel, the pit's fantasy). | DEFERRED | Pulled from the pool at 3/10 (G60: "a bottomless hole of effort"); the code, tools and `--module aram` / `pit` stay. Back only when **the author asks for a new combat pitch**. |
| L-8 | Online: lockstep over WebRTC for the raids and Twins, then the shooter net model (G7, G8). The sims are deterministic and replay-checked for it. | DEFERRED | Online goes last (G32); new modules keep the pure-sim rule so it still fits. |
| L-10 | MMO art gaps after gauntlet r4: gryphon end caps, bag and micro-menu icons, the minimap rim and buttons, thicker Giant arms, outfit exaggeration, a cooler palette and a water channel. | WATCH | The raids are frozen at 10/10 (G60); these were gaps against the reference photos, not problems. Only if the author points at one. |
| L-11 | Kit texture art: the kit's assets plateaued at ~30/50 against the photos with procedural surfaces. | WATCH | As L-10: only if the author points at one (the guns: see L-18, which they did). |
| L-16 | FPS G43: the radial loadout, the new guns' feel and numbers (Claude's), the Dual Berettas' triggers and trick reload, the Desert Eagle's boom, Campus paintball (layout, bushes, paint). | AWAITING PLAY | 7/10, "super fun" (G60); the author wants polish on the maps and the gun models, not a rules change. Replay after L-12 / L-18 land. |
| L-18 | Kit gun art past the procedural/Blender pass. Done 10-16 (G61): checkering and speckle (shader relief), the carbine's see-through mag, the muzzle flash flipbook. Still open: roll marks/engravings, track tread, and the sculpt list (stock risers and wrists, ejection ports and bolt shrouds, bevelled edges, a reflex-sight housing, hands in the view model). | AWAITING PLAY | The author looks at `design/shots/kit/final_<id>_before_after.png` (G61, mean 28 → 29/50) and says whether the sculpt/painted-art round is worth it. Campus bunkers and the chapel's stone stay WATCH under L-11. |
| L-20 | The procedural forest / Tarkov-style extraction sim, in progress by the author's other agent (`src/tourney/extract/`, `design/extract/`, untracked as of this review). | WATCH | That agent's commits land: register it (POOL, `module.tscn` id, GAMES.md, CLAUDE.md Shape, a probe line) and document it. Nothing of it is touched from here. |
| L-13 | Black \| White's own code was touched three times for modules: `cosmetics.hair_hex`, `BWCharacterPose.override` + `override_w`, `BWAnimator.reverse`. | WATCH | Any further change under `src/game` or `src/core`: rerun the B/W self-test (~8 min). |

## Settled

| ID | Item | Closed | How |
|---|---|---|---|
| L-1 | Rename the folder to `Documents\Gamers Gauntlet` (G26). | 2026-10-16 | The author renamed it. |
| S-1 | Live feel numbers for playtests. | 2026-10-14 | MobaTune, FpsTune and MmoTune: one cfg each plus an F1 panel (G19). |
| S-2 | Chris recordings: trim and loop. | 2026-10-14 | `tools/audio/trim_chris.py`; originals in `game/audio/source/chris` (G24). |
| L-4 | FPS feel. | 2026-10-15 | The author: "feels great, super fun"; polish later (G31). |
| L-5 | Temu's stealth: move-only. | 2026-10-15 | The author confirmed the literal reading (G5, G31). |
| L-7 | The Chris loops' roles. | 2026-10-15 | Fine as they are; more audio later (G31). |
| L-9 | G10 build order. | 2026-10-15 | More modules first, online last (G32). |
| L-3 | Raid night: Cinderbrand, Scorched Earth and the grade in play. | 2026-10-16 | Played: 10/10, "I made it too hard so I made an easy mode" (G59 Easy/Hard), okay stopping. Frozen (G60). |
| L-14 | The tournament look (G27) and the load-in (G42). | 2026-10-16 | The author played the whole night through and scored the games without a note on the shell; taken as judged (G60). Re-open only if the author points at a screen. |
| L-15 | OSRS: Warden's Trial: difficulty, tick feel, camera, the Sun Sigil, the UI. | 2026-10-16 | Played: 9/10, "genuinely fun"; Easy and Hard (G57); "okay stopping changes at this point". Frozen (G60). |
| L-17 | The hidden MMO Tank class (G44). | 2026-10-16 | The raids scored 10/10 with no note on the Tank; closed with them (G60). |
| L-19 | Planet of Tanks (G46, G52): the tank's numbers, telegraphs, smoke, ram, light tanks, the logo. | 2026-10-16 | Played with the raids: 10/10, okay stopping. Frozen (G60). |
| L-12 | The FPS bot had no pathfinding and the FPS no sounds. | 2026-10-16 | G62: `FpsNav` bakes a mesh per map, the bot uses the bridge, stairwells, both Dust lanes and campus cover; `FpsAudio` gives every duel its sounds. Watch in play: does the bot's push feel fair (`bot_push` on F1)? |
