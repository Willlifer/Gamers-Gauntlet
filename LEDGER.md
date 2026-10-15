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

Last reviewed: 2026-10-15 (playtest rulings, the tournament look, FPS bullets and the Dust map).

## Live

| ID | Item | State | Unblocked by / note |
|---|---|---|---|
| L-1 | Rename the folder `Documents\Black White Arena` → `Documents\Gamers Gauntlet` (G26). Failed twice on a file lock (Godot open; a Claude session started inside it). | OWED | Close Godot and any session in the folder, then `Rename-Item`, re-import in the Project Manager, and update memory paths. |
| L-2 | The Twins module should be decided by a room vote (G4); today the fewest turns wins. | OWED | Needs online play or a local vote screen. |
| L-3 | Raid fight: Cinderbrand (G30) and the grade (G33) need play: is the burn too much, are the weights and letters right? | AWAITING PLAY | The author plays the raid (F1: `brand_*`, Verdict). Re-measure PAR with `mmo_probe` after any balance change. |
| L-6 | MOBA polish (the numbers marked OPEN in `moba_champs.gd`, feel). The pit's fantasy: a fed unit dropped in that can change the game, and so can the opponent (G31). | AWAITING PLAY | The author is adjusting it on F1 (G19). |
| L-8 | Online: lockstep over WebRTC for the MOBA and raid, then the shooter net model (G7, G8). The sims are deterministic and replay-checked for it. | DEFERRED | Online goes last (G32); new modules keep the pure-sim rule so it still fits. |
| L-10 | MMO art gaps after gauntlet r4: gryphon end caps, bag and micro-menu icons, the minimap rim and buttons, thicker Giant arms, outfit exaggeration (pauldrons, capes, chunky weapons), a cooler palette and a water channel. | WATCH | The author thinks the game looks great (10-15): these were gaps against the reference photos, not problems. Only if the author points at one. |
| L-11 | Kit texture art: the kit's assets plateaued at ~30/50 against the photos with procedural surfaces. | WATCH | As L-10: only if the author points at one. |
| L-12 | The FPS bot has no pathfinding (stays on its roof / its half of the hallway); FPS has no sounds yet. | WATCH | The author plays the FPS more (they liked it, G31): footsteps, shots, bullet whizz, navigation. |
| L-14 | The tournament look (G27): tiles, reels, backdrop, two-sided bracket. | AWAITING PLAY | The author judges it ("I'll judge it"); frames in `design/shots/tourney_*.png`. |
| L-15 | OSRS: Warden's Trial (G34): difficulty, the tick feel, the camera, the Sun Sigil twist, and the UI against the OSRS look. | AWAITING PLAY | The author plays it (Quick play or `--module osrs_raid`); all numbers on F1. |
| L-13 | Black \| White's own code was touched three times for modules: `cosmetics.hair_hex`, `BWCharacterPose.override` + `override_w`, `BWAnimator.reverse`. | WATCH | Any further change under `src/game` or `src/core`: rerun the B/W self-test (~8 min). |

## Settled

| ID | Item | Closed | How |
|---|---|---|---|
| S-1 | Live feel numbers for playtests. | 2026-10-14 | MobaTune, FpsTune and MmoTune: one cfg each plus an F1 panel (G19). |
| S-2 | Chris recordings: trim and loop. | 2026-10-14 | `tools/audio/trim_chris.py`; originals in `game/audio/source/chris` (G24). |
| L-4 | FPS feel. | 2026-10-15 | The author: "feels great, super fun"; polish later (G31). |
| L-5 | Temu's stealth: move-only. | 2026-10-15 | The author confirmed the literal reading (G5, G31). |
| L-7 | The Chris loops' roles. | 2026-10-15 | Fine as they are; more audio later (G31). |
| L-9 | G10 build order. | 2026-10-15 | More modules first, online last (G32). |
