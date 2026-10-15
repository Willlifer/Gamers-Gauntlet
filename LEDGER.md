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

Last reviewed: 2026-10-14 (the MMO raid, audio and rename).

## Live

| ID | Item | State | Unblocked by / note |
|---|---|---|---|
| L-1 | Rename the folder `Documents\Black White Arena` → `Documents\Gamers Gauntlet` (G26). Failed twice on a file lock (Godot open; a Claude session started inside it). | OWED | Close Godot and any session in the folder, then `Rename-Item`, re-import in the Project Manager, and update memory paths. |
| L-2 | The Twins module should be decided by a room vote (G4); today the fewest turns wins. | OWED | Needs online play or a local vote screen. |
| L-3 | Raid difficulty and the tournament rule. Bots kill the Giant in ~150 s with no deaths and 1–2 mechanic fails each. A contestant is judged by rating against a same-class bot (G23, `MmoClasses.PAR`). | AWAITING PLAY | The author's raid: too easy or too hard (F1: boss HP, spell damage, `spell_gap`), and whether rating feels fair or the room wants top-of-meter. Re-measure PAR with `mmo_probe` after any balance change. |
| L-4 | FPS feel: run speed, ADS, the CS:GO reticle snap, recoil, bot reaction (G20). | AWAITING PLAY | The author's playtest; all on F1. |
| L-5 | Temu's stealth breaks only on movement, the literal reading (G5); League breaks it on attack too. | AWAITING PLAY | The author's feel in ARAM. |
| L-6 | The MOBA numbers marked OPEN in `moba_champs.gd` (League-ish defaults). | AWAITING PLAY | Live on F1 (G19). |
| L-7 | The Chris loops' roles (G24–G25): judged by measurement, not by ear. Repeat 1 = lobby / pre-pull, Repeat 2 = hype and boss, Full = games. | AWAITING PLAY | The author listens; swap `TourneyMusic.CUES` if a take was meant for something else. |
| L-8 | Online: lockstep over WebRTC for the MOBA and raid, then the shooter net model (G7, G8). The sims are deterministic and replay-checked for it. | BLOCKED | The author's go on the G10 order. |
| L-9 | G10 build order: online proof, a clean character package, a map maker, more modules (OSRS…). | BLOCKED | The author. |
| L-10 | MMO art gaps after gauntlet r4: gryphon end caps, bag and micro-menu icons, the minimap rim and buttons, thicker Giant arms, outfit exaggeration (pauldrons, capes, chunky weapons), a cooler palette and a water channel. | DEFERRED | Needs hand-made art or the author's go. Reviews: HUD 7/10, telegraphs 8, Giant animation 6, scene 6. |
| L-11 | Kit texture art: the kit's assets plateaued at ~30/50 against the photos with procedural surfaces. | DEFERRED | Hand-made textures, the author's go. |
| L-12 | The FPS bot stays on its roof (no pathfinding); FPS has no sounds yet. | WATCH | If the author plays FPS more, add footsteps, shots and navigation. |
| L-13 | Black \| White's own code was touched three times for modules: `cosmetics.hair_hex`, `BWCharacterPose.override` + `override_w`, `BWAnimator.reverse`. | WATCH | Any further change under `src/game` or `src/core`: rerun the B/W self-test (~8 min). |

## Settled

| ID | Item | Closed | How |
|---|---|---|---|
| S-1 | Live feel numbers for playtests. | 2026-10-14 | MobaTune, FpsTune and MmoTune: one cfg each plus an F1 panel (G19). |
| S-2 | Chris recordings: trim and loop. | 2026-10-14 | `tools/audio/trim_chris.py`; originals in `game/audio/source/chris` (G24). |
