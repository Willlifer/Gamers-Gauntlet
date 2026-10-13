class_name MobaUnit
extends RefCounted
## A champion, minion or practice dummy in the MOBA sim. Plain state; only
## MobaSim changes it. Distances are world units (1 = 100 League units).

var id := ""
var team := ""                 # "blue" | "red"
var kind := "champ"            # "champ" | "minion" | "dummy"
var champ := ""                # champion id (MobaChamps) for champs
var role := ""                 # minions: "melee" | "caster"
var name := ""
var pos := Vector2.ZERO
var facing := Vector2.RIGHT
var radius := 0.65
var hp := 700.0
var max_hp := 700.0
var ms := 3.35                 # move speed, u/s (League 335)
var ad := 60.0                 # auto-attack damage
var period := 1.0              # seconds per auto
var range := 5.5
var windup := 0.3              # auto wind-up; moving cancels it
var proj_speed := 18.0         # 0 = the auto lands at the end of the wind-up (melee)
var alive := true
var respawn_t := 0.0
var kills := 0

## orders: { kind: "idle" | "move" | "attack", to: Vector2, target: id }
var order := { "kind": "idle" }
var atk_cd := 0.0              # until the next auto may start
var atk_wind := -1.0           # >= 0: winding up an auto on atk_target
var atk_target := ""
var cd := {}                   # slot -> seconds left
var dash_t := 0.0
var dash_v := Vector2.ZERO
var dots: Array = []           # { kind, per_s, t, src }
var buffs: Array = []          # { kind, mult, t }
var still_t := 0.0             # Temu: seconds without moving
var stealth := false
var blind_t := 0.0             # Braves' smoke: sight cut to SMOKE_SIGHT
var moving := false
var cast_serial := 0           # bumps on every cast (the view poses it)
var last_cast := ""
var atk_serial := 0            # bumps on every auto fired
var hit_serial := 0            # bumps on every hit taken
var dmg_done := 0.0
var lane_dir := 1.0            # minions: +1 walks toward red, −1 toward blue


func targetable() -> bool:
	return alive and not stealth


func ms_now() -> float:
	var m := 1.0
	for b in buffs:
		if b.kind == "ms":
			m *= float(b.mult)
	return ms * m
