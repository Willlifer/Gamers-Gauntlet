class_name OsrsSim
extends RefCounted
## OSRS: Warden's Trial (G34), after Tombs of Amascut's Wardens. Pure state on
## OSRS game ticks (0.6 s), seeded, no nodes: the view draws it, a bot or the
## mouse gives it orders, a probe replays it.
##
## The floor is a grid of game squares (W x H; x west→east, y north→south,
## the Warden north of row 0). Everything lives on a square, like a chess
## piece: you move a square a tick walking, two running, along a path that
## never cuts a blocked corner. The Warden is a 5x5 piece in the void north
## of the floor.
##
## The Warden:
##   projectiles  magic (blue orb) or ranged (arrow), shown over its head as
##                it looses; they land `flight` ticks later and do nothing
##                if the matching protect prayer is up when they land. In
##                phase 3 a twin volley sends the other style a tick behind
##                (a flick). Stand next to it and it smacks you (melee).
##   lightning    shadows grow on squares; a bolt strikes each when it's full.
##                A struck square can't be picked again for a few ticks.
##   boulders     shadows under falling rocks (one on you); a rock that lands
##                blocks its square for a while.
##   slam         the floor glows east, then west, then both sides; stand in
##                the safe columns when each lands.
##   tear-out     phase 3: the furthest row cracks and falls away, again and
##                again, down to `rows_left` rows.
## The twist, the Sun Sigil: a gold sigil lights on a square now and then;
## stand on it when it ignites and your next attacks hit twice as hard. It
## tends to light where it's dangerous to stand.
## Phases by the Warden's HP: 1 above 66%, 2 above 33%, 3 below.

const TICK := 0.6
const W := 15
const H := 12
const BOSS_RECT := Rect2i(5, -5, 5, 5)          ## the Warden's squares
const STYLES := ["magic", "ranged"]

var rng := RandomNumberGenerator.new()
var tick := 0
var gone := {}                 # Vector2i -> true: torn-out squares
var rocks := {}                # Vector2i -> ticks left
var me := {}                   # the player (see _init)
var boss := {}
var projs: Array = []          # { id, style, launch, land, dmg }
var bolts: Array = []          # lightning { tile, t, total }
var falls: Array = []          # boulders { tile, t, total }
var slams: Array = []          # { cols: [x], t, total, side }
var rip := {}                  # { row, t, total } while a row is cracking
var sigils: Array = []         # { tile, t, total }
var cooled := {}               # Vector2i -> ticks before lightning may pick it again
var over := ""                 # "" | "win" | "dead" | "time"
var events: Array = []
var _special_i := 0
var _next_proj := 1


func _init(seed: int = 1) -> void:
	rng.seed = seed
	var hp := OsrsTune.value("hp")
	var pr := OsrsTune.value("prayer")
	me = { "tile": Vector2i(7, 9), "trail": [Vector2i(7, 9)], "path": [], "hp": hp, "max_hp": hp, "pray": pr, "max_pray": pr,
		"prayer": "", "drain": 0, "weapon": "bow", "attack": false, "atk_cd": 0, "food": int(OsrsTune.value("food")),
		"doses": int(OsrsTune.value("potions")) * 4, "run": true, "alive": true, "empowered": 0, "acted": "",
		# the record
		"dmg_done": 0.0, "dmg_taken": 0.0, "blocked": 0, "unblocked": 0, "dodged": 0, "struck": 0, "sigils": 0, "attacks": 0 }
	var bh := OsrsTune.value("boss_hp")
	boss = { "hp": bh, "max_hp": bh, "auto_cd": 8, "special_cd": 14, "rip_cd": int(OsrsTune.value("rip_every")),
		"sigil_cd": 15, "last_style": "", "anim": "", "anim_tick": -99, "phase": 1 }


# ------------------------------------------------------------------ squares

static func inside(t: Vector2i) -> bool:
	return t.x >= 0 and t.x < W and t.y >= 0 and t.y < H


func walkable(t: Vector2i) -> bool:
	return inside(t) and not gone.has(t) and not rocks.has(t)


## Squares from `t` to the Warden's nearest square (Chebyshev, like OSRS range).
static func boss_dist(t: Vector2i) -> int:
	var dx := maxi(maxi(BOSS_RECT.position.x - t.x, 0), t.x - (BOSS_RECT.end.x - 1))
	var dy := maxi(maxi(BOSS_RECT.position.y - t.y, 0), t.y - (BOSS_RECT.end.y - 1))
	return maxi(dx, dy)


## A path of squares (not including `from`) by breadth-first search, eight
## ways, no corner cutting. An unwalkable goal walks to the nearest
## reachable square to it.
func path(from: Vector2i, goal: Vector2i) -> Array:
	var prev := { from: from }
	var q: Array = [from]
	var best := from
	var best_d := _gd(from, goal)
	var i := 0
	while i < q.size():
		var c: Vector2i = q[i]
		i += 1
		if c == goal:
			best = c
			break
		var d := _gd(c, goal)
		if d < best_d:
			best_d = d
			best = c
		for o in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]:
			var n: Vector2i = c + o
			if prev.has(n) or not walkable(n):
				continue
			if o.x != 0 and o.y != 0 and (not walkable(Vector2i(c.x + o.x, c.y)) or not walkable(Vector2i(c.x, c.y + o.y))):
				continue
			prev[n] = c
			q.append(n)
	var out: Array = []
	var k := best
	while k != from:
		out.push_front(k)
		k = prev[k]
	return out


static func _gd(a: Vector2i, b: Vector2i) -> float:
	return Vector2(a).distance_to(Vector2(b))


func phase() -> int:
	var f := float(boss.hp) / float(boss.max_hp)
	return 1 if f > 0.66 else (2 if f > 0.33 else 3)


# --------------------------------------------------------------------- step

## orders: { move: Vector2i, attack: bool, pray: "magic"|"ranged"|"melee"|"off",
##   eat: true, drink: true, swap: true, run: bool }
func step(o: Dictionary) -> Array:
	events = []
	if over != "":
		return events
	tick += 1
	_orders(o)
	_walk()
	_attack()
	_boss_turn()
	_resolve()
	_prayer_drain()
	for k in cooled.keys():
		cooled[k] = int(cooled[k]) - 1
		if int(cooled[k]) <= 0:
			cooled.erase(k)
	for k in rocks.keys():
		rocks[k] = int(rocks[k]) - 1
		if int(rocks[k]) <= 0:
			rocks.erase(k)
			_ev({ "type": "rock_gone", "tile": k })
	if float(boss.hp) <= 0.0:
		over = "win"
		_ev({ "type": "over", "how": "win" })
	elif not me.alive:
		over = "dead"
		_ev({ "type": "over", "how": "dead" })
	elif tick * TICK >= OsrsTune.value("time_limit"):
		over = "time"
		_ev({ "type": "over", "how": "time" })
	return events


func _ev(e: Dictionary) -> void:
	e["tick"] = tick
	events.append(e)


func _orders(o: Dictionary) -> void:
	me.acted = ""
	if not me.alive:
		return
	if o.has("run"):
		me.run = bool(o.run)
	if o.has("pray"):
		var p := str(o.pray)
		if p == "off" or p == me.prayer:
			me.prayer = ""
		elif float(me.pray) > 0.0:
			me.prayer = p
		_ev({ "type": "pray", "prayer": me.prayer })
	if o.get("swap", false):
		me.weapon = "staff" if me.weapon == "bow" else "bow"
		me.atk_cd = maxi(int(me.atk_cd), 1)
		_ev({ "type": "swap", "weapon": me.weapon })
	if o.get("eat", false) and int(me.food) > 0 and float(me.hp) < float(me.max_hp):
		me.food = int(me.food) - 1
		var add := minf(float(me.max_hp) * OsrsTune.value("restore"), float(me.max_hp) - float(me.hp))
		me.hp = float(me.hp) + add
		me.atk_cd = int(me.atk_cd) + int(OsrsTune.value("eat_delay"))
		me.acted = "eat"
		_ev({ "type": "eat", "heal": add })
	elif o.get("drink", false) and int(me.doses) > 0:
		me.doses = int(me.doses) - 1
		var add := minf(float(me.max_pray) * OsrsTune.value("restore"), float(me.max_pray) - float(me.pray))
		me.pray = float(me.pray) + add
		me.acted = "drink"
		_ev({ "type": "drink", "restore": add })
	if o.has("move"):
		me.path = path(me.tile, o.move)
		me.attack = bool(o.get("attack", false))
	elif o.has("attack"):
		me.attack = bool(o.attack)
		if me.attack:
			me.path = []


func _walk() -> void:
	me.trail = [me.tile]
	if not me.alive:
		return
	if me.attack and (me.path as Array).is_empty() and boss_dist(me.tile) > int(OsrsTune.value("range")):
		me.path = _path_into_range()
	var steps := 2 if me.run else 1
	for i in steps:
		if (me.path as Array).is_empty():
			break
		var n: Vector2i = me.path[0]
		if not walkable(n):                                  # a rock fell or the floor went: re-path
			var goal: Vector2i = me.path[-1]
			me.path = path(me.tile, goal)
			if (me.path as Array).is_empty() or not walkable(me.path[0]):
				me.path = []
				break
			n = me.path[0]
		me.path.pop_front()
		me.tile = n
		me.trail.append(n)


func _path_into_range() -> Array:
	var best: Array = []
	var r := int(OsrsTune.value("range"))
	var p := path(me.tile, Vector2i(me.tile.x, 0))
	for i in p.size():
		if boss_dist(p[i]) <= r:
			return p.slice(0, i + 1)
	return best if not best.is_empty() else p


func _attack() -> void:
	me.atk_cd = maxi(0, int(me.atk_cd) - 1)
	if not me.alive or not me.attack or not (me.path as Array).is_empty():
		return
	if boss_dist(me.tile) > int(OsrsTune.value("range")) or int(me.atk_cd) > 0:
		return
	var w := str(me.weapon)
	me.atk_cd = int(OsrsTune.value(w + "_speed"))
	me.attacks = int(me.attacks) + 1
	var dmg := 0.0
	if rng.randf() < OsrsTune.value("accuracy"):
		dmg = float(rng.randi_range(int(OsrsTune.value(w + "_lo")), int(OsrsTune.value(w + "_hi"))))
	var emp := int(me.empowered) > 0
	if emp:
		me.empowered = int(me.empowered) - 1
		dmg = roundf(dmg * OsrsTune.value("sigil_mult"))
	dmg = minf(dmg, float(boss.hp))
	boss.hp = float(boss.hp) - dmg
	me.dmg_done = float(me.dmg_done) + dmg
	_ev({ "type": "attack", "weapon": w, "dmg": dmg, "empowered": emp, "land": tick + (1 if w == "bow" else 2) })


# --------------------------------------------------------------------- boss

func _boss_turn() -> void:
	var ph := phase()
	if ph != int(boss.phase):
		boss.phase = ph
		_ev({ "type": "phase", "phase": ph })
	# projectiles (and the melee smack)
	boss.auto_cd = int(boss.auto_cd) - 1
	if int(boss.auto_cd) <= 0:
		boss.auto_cd = int(OsrsTune.value("auto_every_p3" if ph == 3 else "auto_every"))
		if boss_dist(me.tile) <= 1:
			_launch("melee", 1, OsrsTune.value("melee_hit"))
		else:
			var style: String = STYLES[rng.randi() % 2]
			_launch(style, int(OsrsTune.value("flight")), -1.0)
			if ph == 3 and rng.randf() < OsrsTune.value("twin_chance"):
				_launch("ranged" if style == "magic" else "magic", int(OsrsTune.value("flight")) + 1, -1.0)
	# specials
	boss.special_cd = int(boss.special_cd) - 1
	if int(boss.special_cd) <= 0:
		boss.special_cd = int(OsrsTune.value("special_every")) - (1 if ph == 3 else 0)
		var order: Array = [["lightning"], ["boulders", "slam", "lightning"], ["lightning", "boulders", "slam"]][ph - 1]
		var sp: String = order[_special_i % order.size()]
		_special_i += 1
		match sp:
			"lightning": _lightning(int(OsrsTune.value("lightning_n_p3" if ph == 3 else "lightning_n")))
			"boulders": _boulders()
			"slam": _slam()
	# phase 3: tear out the far row
	if ph == 3 and rip.is_empty():
		boss.rip_cd = int(boss.rip_cd) - 1
		if int(boss.rip_cd) <= 0 and rows_left() > int(OsrsTune.value("rows_left")):
			boss.rip_cd = int(OsrsTune.value("rip_every"))
			var row := far_row()
			var w := int(OsrsTune.value("rip_warn"))
			rip = { "row": row, "t": w, "total": w }
			_ev({ "type": "rip_warn", "row": row })
			_anim("upheaval")
	# the Sun Sigil (the twist)
	boss.sigil_cd = int(boss.sigil_cd) - 1
	if int(boss.sigil_cd) <= 0:
		boss.sigil_cd = int(OsrsTune.value("sigil_every"))
		var at := _sigil_spot()
		if at != Vector2i(-1, -1):
			var w := int(OsrsTune.value("sigil_warn"))
			sigils.append({ "tile": at, "t": w, "total": w })
			_ev({ "type": "sigil", "tile": at })


func _anim(id: String) -> void:
	boss.anim = id
	boss.anim_tick = tick
	_ev({ "type": "boss_anim", "anim": id })


func _launch(style: String, flight: int, dmg: float) -> void:
	if dmg < 0.0:
		dmg = float(rng.randi_range(int(OsrsTune.value("auto_lo")), int(OsrsTune.value("auto_hi"))))
	var p := { "id": _next_proj, "style": style, "launch": tick, "land": tick + flight, "dmg": dmg }
	_next_proj += 1
	projs.append(p)
	boss.last_style = style
	_ev({ "type": "proj", "proj": p })


func rows_left() -> int:
	var n := 0
	for y in H:
		if not gone.has(Vector2i(0, y)):
			n += 1
	return n


func far_row() -> int:
	for y in range(H - 1, -1, -1):
		if not gone.has(Vector2i(0, y)):
			return y
	return 0


func floor_tiles() -> Array:
	var out: Array = []
	for y in H:
		for x in W:
			var t := Vector2i(x, y)
			if not gone.has(t):
				out.append(t)
	return out


func _lightning(n: int) -> void:
	_anim("meteors")
	var w := int(OsrsTune.value("lightning_warn"))
	var pool := floor_tiles().filter(func(t: Vector2i) -> bool: return not cooled.has(t) and not _bolt_at(t))
	var near := pool.filter(func(t: Vector2i) -> bool: return _cheb(t, me.tile) <= 3)
	var picks: Array = []
	# about half land around you (one right on you), the rest anywhere
	if pool.has(me.tile):
		picks.append(me.tile)
	while picks.size() < n / 2 and not near.is_empty():
		picks.append(near.pop_at(rng.randi() % near.size()))
	while picks.size() < n and not pool.is_empty():
		var t: Vector2i = pool.pop_at(rng.randi() % pool.size())
		if not picks.has(t):
			picks.append(t)
	for t: Vector2i in picks:
		bolts.append({ "tile": t, "t": w + rng.randi_range(0, 1), "total": w })
	_ev({ "type": "lightning", "n": picks.size() })


func _bolt_at(t: Vector2i) -> bool:
	for b in bolts:
		if b.tile == t:
			return true
	return false


func _boulders() -> void:
	_anim("bombs")
	var w := int(OsrsTune.value("boulder_warn"))
	var picks: Array = [me.tile]
	var near := floor_tiles().filter(func(t: Vector2i) -> bool: return _cheb(t, me.tile) <= 4 and t != me.tile)
	while picks.size() < int(OsrsTune.value("boulder_n")) and not near.is_empty():
		picks.append(near.pop_at(rng.randi() % near.size()))
	for t: Vector2i in picks:
		falls.append({ "tile": t, "t": w, "total": w })
	_ev({ "type": "boulders", "n": picks.size() })


## East, then west, then both sides (the centre columns are the safe ones then).
func _slam() -> void:
	_anim("upheaval")
	var w := int(OsrsTune.value("slam_warn"))
	var east: Array = range(8, W)
	var west: Array = range(0, 7)
	var both: Array = range(0, 6) + range(9, W)
	slams.append({ "cols": east, "t": w, "total": w, "side": "east" })
	slams.append({ "cols": west, "t": w + 4, "total": w, "side": "west" })
	slams.append({ "cols": both, "t": w + 8, "total": w, "side": "both" })
	_ev({ "type": "slam", "side": "east" })


func _sigil_spot() -> Vector2i:
	var r := int(OsrsTune.value("range"))
	var pool := floor_tiles().filter(func(t: Vector2i) -> bool: return _cheb(t, me.tile) >= 2 and _cheb(t, me.tile) <= 4 and boss_dist(t) <= r)
	if pool.is_empty():
		return Vector2i(-1, -1)
	return pool[rng.randi() % pool.size()]


static func _cheb(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


# ------------------------------------------------------------------ resolve

func _resolve() -> void:
	for p: Dictionary in projs.duplicate():
		if int(p.land) <= tick:
			projs.erase(p)
			if not me.alive:
				continue
			if me.prayer == p.style:
				me.blocked = int(me.blocked) + 1
				_ev({ "type": "blocked", "style": p.style })
				_hurt(0.0, str(p.style))
			else:
				me.unblocked = int(me.unblocked) + 1
				_hurt(float(p.dmg), str(p.style))
	for b: Dictionary in bolts.duplicate():
		b.t = int(b.t) - 1
		if int(b.t) <= 0:
			bolts.erase(b)
			cooled[b.tile] = 3
			_ev({ "type": "bolt", "tile": b.tile })
			_hazard(b.tile == me.tile, OsrsTune.value("lightning_dmg"), "lightning")
	for f: Dictionary in falls.duplicate():
		f.t = int(f.t) - 1
		if int(f.t) <= 0:
			falls.erase(f)
			_ev({ "type": "boulder", "tile": f.tile })
			var on_me: bool = f.tile == me.tile
			_hazard(on_me, OsrsTune.value("boulder_dmg"), "boulder")
			if OsrsTune.value("boulder_stay") > 0.0 and not gone.has(f.tile):
				rocks[f.tile] = int(OsrsTune.value("boulder_stay"))
				if on_me:
					_shove()
	for s: Dictionary in slams.duplicate():
		s.t = int(s.t) - 1
		if int(s.t) == int(s.total) and str(s.side) != "east":
			_ev({ "type": "slam", "side": s.side })
			_anim("upheaval")
		if int(s.t) <= 0:
			slams.erase(s)
			_ev({ "type": "slam_land", "side": s.side, "cols": s.cols })
			_hazard((s.cols as Array).has(int(me.tile.x)), OsrsTune.value("slam_dmg"), "slam")
	if not rip.is_empty():
		rip.t = int(rip.t) - 1
		if int(rip.t) <= 0:
			var row := int(rip.row)
			for x in W:
				gone[Vector2i(x, row)] = true
				rocks.erase(Vector2i(x, row))
			for s in sigils.duplicate():
				if int(s.tile.y) == row:
					sigils.erase(s)
			_ev({ "type": "rip", "row": row })
			rip = {}
			if int(me.tile.y) == row:
				_hazard(true, OsrsTune.value("rip_dmg"), "fall")
				_shove()
	for s: Dictionary in sigils.duplicate():
		s.t = int(s.t) - 1
		if int(s.t) <= 0:
			sigils.erase(s)
			var hit: bool = me.alive and s.tile == me.tile
			if hit:
				me.empowered = int(OsrsTune.value("sigil_hits"))
				me.sigils = int(me.sigils) + 1
			_ev({ "type": "sigil_fire", "tile": s.tile, "took": hit })


## A danger landed: it hit you or you dodged it (only counted when it was near).
func _hazard(hit: bool, dmg: float, what: String) -> void:
	if not me.alive:
		return
	if hit:
		me.struck = int(me.struck) + 1
		_hurt(dmg, what)
	else:
		me.dodged = int(me.dodged) + 1


## Off a square that just became unwalkable: the nearest walkable one.
func _shove() -> void:
	var best: Vector2i = me.tile
	var bd := 999.0
	for t: Vector2i in floor_tiles():
		if walkable(t):
			var d := _gd(t, me.tile)
			if d < bd:
				bd = d
				best = t
	me.tile = best
	me.trail.append(best)
	me.path = []


func _hurt(dmg: float, what: String) -> void:
	dmg = minf(dmg, float(me.hp))
	me.hp = float(me.hp) - dmg
	me.dmg_taken = float(me.dmg_taken) + dmg
	_ev({ "type": "hurt", "dmg": dmg, "what": what })
	if float(me.hp) <= 0.0:
		me.alive = false
		me.prayer = ""
		me.path = []
		_ev({ "type": "death" })


func _prayer_drain() -> void:
	if me.prayer == "":
		return
	me.drain = int(me.drain) + 1
	if int(me.drain) >= int(OsrsTune.value("drain_every")):
		me.drain = 0
		me.pray = maxf(0.0, float(me.pray) - 1.0)
		if float(me.pray) <= 0.0:
			me.prayer = ""
			_ev({ "type": "pray", "prayer": "", "why": "out" })


# --------------------------------------------------------------- the danger

## Squares that something will hit within `ticks` ticks (the bot dodges these).
func danger(ticks: int) -> Dictionary:
	var out := {}
	for b in bolts:
		if int(b.t) <= ticks:
			out[b.tile] = true
	for f in falls:
		if int(f.t) <= ticks:
			out[f.tile] = true
	for s in slams:
		if int(s.t) <= ticks:
			for x in s.cols:
				for y in H:
					out[Vector2i(int(x), y)] = true
	if not rip.is_empty() and int(rip.t) <= ticks + 1:
		for x in W:
			out[Vector2i(x, int(rip.row))] = true
	return out


## How the run went, for the verdict: a kill beats a death; then speed, then damage.
func result() -> Dictionary:
	return { "how": over, "ticks": tick, "secs": tick * TICK, "boss_dmg": float(me.dmg_done),
		"boss_pct": 1.0 - float(boss.hp) / float(boss.max_hp), "taken": float(me.dmg_taken),
		"blocked": int(me.blocked), "unblocked": int(me.unblocked), "dodged": int(me.dodged), "struck": int(me.struck), "sigils": int(me.sigils) }


## True when run `a` beats run `b`.
static func beats(a: Dictionary, b: Dictionary) -> bool:
	var ka: bool = a.how == "win"
	var kb: bool = b.how == "win"
	if ka != kb:
		return ka
	if ka and int(a.ticks) != int(b.ticks):
		return int(a.ticks) < int(b.ticks)
	if not is_equal_approx(float(a.boss_dmg), float(b.boss_dmg)):
		return float(a.boss_dmg) > float(b.boss_dmg)
	return float(a.taken) <= float(b.taken)


func state_hash() -> int:
	return hash([tick, me.tile, me.hp, me.pray, boss.hp, gone.size(), rocks.size(), projs.size(), bolts.size()])
