class_name MobaChamps
extends RefCounted
## The author's three ARAM champions. Base: 1400 HP (G54; was 700), 60 per auto, one auto a
## second. Ranges in world units (1 = 100 League units). Numbers the author
## left open are League-ish defaults, marked OPEN.

const BASE_AD := 60.0
const TEMU_STILL := 1.0          # seconds still before Temu vanishes
const TEMU_POISON := 60.0        # 1x AA over 3 s (E, and Q's poison)
const BLAZE_PCT := 0.05          # Merr: spell contact burns 5% max HP over 5 s
const HP := 1400.0               # author 10-16: every champion's health doubled (was 700)
const RANGE_UP := 1.25           # author 10-16: every range +25% (autos above, spells in SHAPES)

## Each spell's reach and footprint (G54): cast() reads its numbers here and
## the aim indicator (moba_aim.gd), the tooltips and the bots read the same.
## shape: line (a skillshot, width = half-width) | circle (lands at the cursor,
## r = radius) | cone (deg wide) | target (the enemy nearest the cursor;
## r = the burst round it) | dash | self | none. Ranges are the old ones x1.25.
const SHAPES := {
	"merr": {
		"q": { "shape": "line", "range": 10.5 * RANGE_UP, "width": 0.5, "speed": 16.0 * 0.7 },   # Brand-like Q: 30% slower (author 10-16)
		"w": { "shape": "circle", "range": 9.0 * RANGE_UP, "r": 2.5, "delay": 0.625 / 0.7 },    # the pillar grows 30% slower
		"e": { "shape": "target", "range": 6.75 * RANGE_UP, "r": 3.0 },
		"r": { "shape": "target", "range": 7.5 * RANGE_UP, "r": 0.9, "bounce": 6.0 * RANGE_UP, "speed": 14.0 * 0.5 } },  # 100% slower: half speed
	"temu": {
		"q": { "shape": "target", "range": 6.8 * RANGE_UP, "r": 0.9 },
		"w": { "shape": "self", "range": 0.0 },
		"e": { "shape": "none", "range": 0.0 },
		"r": { "shape": "circle", "range": 4.0 * RANGE_UP, "r": 2.5 } },
	"braves": {
		"q": { "shape": "cone", "range": 8.0 * RANGE_UP, "deg": 60.0 },
		"w": { "shape": "circle", "range": 9.0 * RANGE_UP, "r": 2.5 },
		"e": { "shape": "dash", "range": 4.25 * 0.25 },           # author 10-16: 25% of the old 4.25
		"r": { "shape": "line", "range": 10.0 * RANGE_UP, "width": 0.6 } },
}
## The cast stop (author 10-16): Q W E R root the caster this long, then
## the spell goes off. Summoner spells stay instant.
const CAST_TIME := 0.3

const CHAMPS := {
	"merr": { "name": "Merr", "title": "the Shambling Flame", "weapon": "staff", "weapon_model": "orb_scepter",
		"hair_style": "mullet", "hair_hex": "#7ed957", "tint": "#7ed957", "gender": "m", "top": "tank_top", "bottom": "ripped_tight_pants",
		"range": 6.875, "ms": 3.35, "ad": 60.0, "proj_speed": 18.0, "windup": 0.3, "role": "Mage · long range",
		"cd": { "q": 8.0, "w": 10.0, "e": 9.0, "r": 50.0 },
		"spells": {
			"passive": ["Blaze", "Any spell that touches someone burns 5% of their max HP over 5 s."],
			"q": ["Spit", "A line of flame: 3x auto damage to the first thing it hits."],
			"w": ["Pyre", "Fire erupts under the cursor after a moment: 3x auto damage."],
			"e": ["Spread", "Ignite a target; it bursts onto everything near it: 1.5x auto damage."],
			"r": ["Phlegm", "A gob that bounces between enemies 3 times: 3x auto damage a hit."] } },
	"temu": { "name": "Temu", "title": "the Welder", "weapon": "bow", "weapon_model": "shortbow",
		"kit_weapon": "slingshot", "kit_params": { "scale": 2.6 },   # the author: Temu uses the slingshot (bow clips drive the draw)
		"hair_style": "short_mohawk", "hair_hex": "#a259ff", "tint": "#a259ff", "gender": "m", "top": "hoodie", "bottom": "tight_shorts",
		"range": 6.25, "ms": 3.45, "ad": 60.0, "proj_speed": 16.0, "windup": 0.28, "role": "Marksman · long range",
		"cd": { "q": 5.0, "w": 15.0, "e": 0.0, "r": 12.0 },
		"spells": {
			"passive": ["Lurk", "Stand still for 1 s: invisible and untargetable until you move."],
			"q": ["Toxic Shot", "A target takes 1x auto damage and is poisoned."],
			"w": ["Scurry", "50% more move speed for 5 s."],
			"e": ["Toxin", "No active. Your autos poison for 1x auto damage over 3 s."],
			"r": ["Pocket Nuke", "Drop a mine. It arms in 1 s; an enemy near it sets it off: 2x auto poison over 5 s."] } },
	"braves": { "name": "Braves", "title": "the Buckshot", "weapon": "pistols", "weapon_model": "flintlock",
		"hair_style": "buzzed", "hair_hex": "#8b5a2b", "tint": "#a8743a", "gender": "m", "top": "sweater", "bottom": "baggy_sweatpants",
		"range": 5.3125, "ms": 3.4, "ad": 90.0, "proj_speed": 30.0, "windup": 0.25, "role": "Fighter · medium range",
		"cd": { "q": 7.0, "w": 12.0, "e": 9.0, "r": 50.0 },
		"spells": {
			"passive": ["Heavy Shells", "Autos deal 1.5x auto damage."],
			"q": ["Buckshot", "3 pellets in a 60° cone: 3x auto damage point blank, 1x at the edge."],
			"w": ["Smoke Bomb", "1x auto damage; anyone in the smoke can barely see."],
			"e": ["Skip", "Dash toward the cursor."],
			"r": ["Superblast", "One big shell that explodes on the first thing it hits: 3x auto damage."] } },
}
const ORDER := ["merr", "temu", "braves"]


static func make(id: String) -> MobaUnit:
	var c: Dictionary = CHAMPS[id]
	var u := MobaUnit.new()
	u.kind = "champ"
	u.champ = id
	u.max_hp = HP
	u.hp = u.max_hp
	u.ad = float(c.ad)
	u.range = float(c.range)
	u.ms = MobaTune.value(id + ".ms")                  # the feel numbers (MobaTune; defaults = the table above)
	u.proj_speed = MobaTune.value(id + ".proj_speed")
	u.windup = MobaTune.value(id + ".windup")
	return u


## Merr's passive: every spell that touches someone burns them.
static func on_spell_hit(s: MobaSim, src: MobaUnit, t: MobaUnit) -> void:
	if src and src.champ == "merr" and t.alive:
		s.dot(t, "blaze", t.max_hp * BLAZE_PCT, 5.0, src)


## The targeted spells find their target from the cursor: the enemy nearest it.
static func pick_target(s: MobaSim, u: MobaUnit, aim: Vector2, tgt: MobaUnit, max_r: float) -> MobaUnit:
	if tgt and tgt.team != u.team and tgt.targetable() and tgt.pos.distance_to(u.pos) <= max_r + tgt.radius:
		return tgt
	var best: MobaUnit = null
	var bd := 1.6
	for o in s.units:
		if o.team != u.team and o.targetable() and o.pos.distance_to(u.pos) <= max_r + o.radius:
			var d: float = o.pos.distance_to(aim)
			if d < bd:
				best = o
				bd = d
	return best


static func cast(s: MobaSim, u: MobaUnit, slot: String, aim: Vector2, tgt: MobaUnit) -> bool:
	var dir: Vector2 = (aim - u.pos).normalized() if aim.distance_to(u.pos) > 0.05 else u.facing
	u.facing = dir
	var sp: Dictionary = shape(u.champ, slot)
	var rng := float(sp.get("range", 0.0))
	match u.champ + ":" + slot:
		# ---------------------------------------------------------------- Merr
		"merr:q":
			s.shoot({ "owner": u.id, "team": u.team, "pos": u.pos + dir * 0.6, "dir": dir, "speed": float(sp.speed),
				"range": rng, "width": float(sp.width), "look": "merr_spit",
				"on_hit": func(o: MobaUnit, _p: Vector2) -> void:
					s.damage(o, BASE_AD * 3.0, u, "spit")
					on_spell_hit(s, u, o) })
			return true
		"merr:w":
			var at := u.pos + (aim - u.pos).limit_length(rng)
			s.add_area({ "kind": "blast", "pos": at, "r": 2.5, "delay": float(sp.delay), "team": u.team, "owner": u.id, "look": "merr_pyre",
				"on_fire": func() -> void: s.area_hit(at, 2.5, u, BASE_AD * 3.0, "pyre") })
			return true
		"merr:e":
			var t := pick_target(s, u, aim, tgt, rng)
			if t == null:
				return false
			s.damage(t, BASE_AD * 1.5, u, "spread")
			on_spell_hit(s, u, t)
			for o in s.units.duplicate():
				if o != t and o.team != u.team and o.alive and o.pos.distance_to(t.pos) <= 3.0 + o.radius:
					s.damage(o, BASE_AD * 1.5, u, "spread")
					on_spell_hit(s, u, o)
			s._emit({ "type": "burst", "look": "merr_spread", "pos": t.pos })
			return true
		"merr:r":
			var t := pick_target(s, u, aim, tgt, rng)
			if t == null:
				return false
			_phlegm(s, u, u.pos, t, 3, "")
			return true
		# ---------------------------------------------------------------- Temu
		"temu:q":
			var t := pick_target(s, u, aim, tgt, rng)
			if t == null:
				return false
			s.shoot({ "owner": u.id, "team": u.team, "pos": u.pos + dir * 0.5, "target": t.id, "speed": 20.0, "look": "temu_dart",
				"on_hit": func(o: MobaUnit, _p: Vector2) -> void:
					s.damage(o, BASE_AD, u, "toxic_shot")
					s.dot(o, "poison", TEMU_POISON, 3.0, u) })
			return true
		"temu:w":
			u.buffs.append({ "kind": "ms", "mult": 1.5, "t": 5.0 })
			return true
		"temu:e":
			return false             # passive
		"temu:r":
			var at := u.pos + (aim - u.pos).limit_length(rng)       # OPEN: throw range 400 (x1.25)
			s.add_area({ "kind": "mine", "pos": at, "r": 2.5, "trigger": 1.6, "arm": 1.0, "t": 60.0, "team": u.team,
				"owner": u.id, "look": "temu_nuke",
				"on_fire": func() -> void:
					for o in s.units:
						if o.team != u.team and o.alive and o.pos.distance_to(at) <= 2.5 + o.radius:
							s.dot(o, "nuke", BASE_AD * 2.0, 5.0, u)
					s._emit({ "type": "burst", "look": "temu_nuke", "pos": at }) })
			return true
		# -------------------------------------------------------------- Braves
		"braves:q":
			for a in [-0.5236, 0.0, 0.5236]:        # 60° cone, edge to edge
				var d: Vector2 = dir.rotated(float(a) * 0.5)
				var start := u.pos
				s.shoot({ "owner": u.id, "team": u.team, "pos": u.pos + d * 0.5, "dir": d, "speed": 24.0, "range": rng,
					"width": 0.35, "look": "braves_pellet",
					"on_hit": func(o: MobaUnit, p: Vector2) -> void:
						var f: float = clampf(start.distance_to(p) / rng, 0.0, 1.0)
						s.damage(o, BASE_AD * lerpf(1.0, 1.0 / 3.0, f), u, "buckshot") })
			return true
		"braves:w":
			var at := u.pos + (aim - u.pos).limit_length(rng)
			# the bomb is lobbed: it flies over units and rocks and bursts where it lands
			var lob := maxf(at.distance_to(u.pos), 0.01)
			s.shoot({ "owner": u.id, "team": u.team, "pos": u.pos, "dir": (at - u.pos) / lob if lob > 0.01 else dir, "speed": 16.0,
				"range": lob, "lob": true, "look": "braves_bomb",
				"on_end": func(p: Vector2) -> void:
					s.area_hit(p, 2.5, u, BASE_AD, "smoke", false)
					s.add_area({ "kind": "smoke", "pos": p, "r": 2.5, "t": 4.0, "team": u.team, "owner": u.id, "look": "braves_smoke" }) })
			return true
		"braves:e":
			s.dash(u, dir, rng, 0.1)
			return true
		"braves:r":
			s.shoot({ "owner": u.id, "team": u.team, "pos": u.pos + dir * 0.6, "dir": dir, "speed": 20.0, "range": rng,
				"width": 0.6, "look": "braves_shell",
				"on_hit": func(_o: MobaUnit, p: Vector2) -> void:
					s.area_hit(p, 2.5, u, BASE_AD * 3.0, "superblast", false)
					s._emit({ "type": "burst", "look": "braves_shell", "pos": p }),
				"on_end": func(p: Vector2) -> void:
					s.area_hit(p, 2.5, u, BASE_AD * 3.0, "superblast", false)
					s._emit({ "type": "burst", "look": "braves_shell", "pos": p }) })
			return true
	return false


## Merr's R: hit `t`, then bounce to the nearest other enemy within 6, `left` more times.
static func _phlegm(s: MobaSim, u: MobaUnit, from: Vector2, t: MobaUnit, left: int, prev: String) -> void:
	s.shoot({ "owner": u.id, "team": u.team, "pos": from, "target": t.id, "speed": float(SHAPES.merr.r.speed), "look": "merr_phlegm",
		"on_hit": func(o: MobaUnit, p: Vector2) -> void:
			s.damage(o, BASE_AD * 3.0, u, "phlegm")
			on_spell_hit(s, u, o)
			if left <= 0:
				return
			var best: MobaUnit = null
			var bd := float(SHAPES.merr.r.bounce)
			for x in s.units:
				if x.team != u.team and x.alive and x.id != o.id and x.targetable():
					var d: float = x.pos.distance_to(p)
					if d <= bd and (best == null or (x.kind == "champ" and best.kind != "champ") or d < best.pos.distance_to(p)):
						best = x
						bd = d if best.kind != "champ" else bd
			if best:
				_phlegm(s, u, p, best, left - 1, o.id) })


## A spell's footprint and reach (SHAPES); {} for the summoner spells.
static func shape(id: String, slot: String) -> Dictionary:
	return SHAPES.get(id, {}).get(slot, {})


## A spell's reach in world units (summoner spells included).
static func spell_range(id: String, slot: String) -> float:
	match slot:
		"flash": return MobaTune.value("flash_range")
		"ignite": return MobaSim.IGNITE_RANGE
		"smite": return MobaSim.SMITE_RANGE
	return float(shape(id, slot).get("range", 0.0))


static func spell_name(id: String, slot: String) -> String:
	return str(CHAMPS[id].spells[slot][0])
