class_name MmoUnit
extends RefCounted
## A raid member or the Giant in MmoSim. Plain state; only MmoSim changes
## it. Ground position in metres (x, z), height above the floor in `h`;
## `yaw` faces +Z at 0 (Godot's rotation.y).

var id := ""
var name := ""
var cls := ""                  # MmoClasses id ("" for the boss)
var kind := "player"           # "player" | "boss"
var role := ""                 # tank | healer | dps | hybrid
var pos := Vector2.ZERO
var h := 0.0
var vh := 0.0
var yaw := 0.0
var radius := 0.5
var hp := 1000.0
var base_hp := 1000.0
var max_hp := 1000.0
var res_kind := "mana"          # mana | rage | energy | none
var res := 0.0
var res_max := 0.0
var alive := true
var cd := {}                    # ability id -> seconds left
var gcd := 0.0
var cast := {}                  # { ab, t, total, target, channel, ticks, tick_t, done }
var auto_on := false
var swing_t := 0.0
var target := ""
var auras: Array = []           # see MmoSim.add_aura
var cp := 0                     # rogue combo points (on the current target)
var move := Vector2.ZERO        # this tick's local move: x right, y forward (the view's legs)
var moving := false
var airborne := false
var speed_now := 0.0
var flags := {}                 # instant_next, crit_next
var threat := {}                # boss: unit id -> threat
# stats (the meter)
var dmg_done := 0.0
var heal_done := 0.0
var fails := 0
var deaths := 0
# serials for the view
var cast_serial := 0
var strike_serial := 0
var hit_serial := 0
var last_ab := ""


func forward() -> Vector2:
	return Vector2(sin(yaw), cos(yaw))


func right() -> Vector2:
	return Vector2(-cos(yaw), sin(yaw))


func mod(key: String) -> float:
	var m := 1.0
	for a: Dictionary in auras:
		var mods: Dictionary = a.get("mods", {})
		if mods.has(key):
			m *= float(mods[key])
	return m


func add(key: String) -> float:
	var s := 0.0
	for a: Dictionary in auras:
		var mods: Dictionary = a.get("mods", {})
		if mods.has(key):
			s += float(mods[key])
	return s


func aura(aid: String) -> Dictionary:
	for a: Dictionary in auras:
		if str(a.id) == aid:
			return a
	return {}


func has_aura(aid: String) -> bool:
	return not aura(aid).is_empty()


func immune() -> bool:
	for a: Dictionary in auras:
		if a.get("immune", false):
			return true
	return false


func frozen() -> bool:
	for a: Dictionary in auras:
		if a.get("still", false):
			return true
	return false


func casting() -> bool:
	return not cast.is_empty()


func hp_pct() -> float:
	return hp / maxf(max_hp, 1.0)
