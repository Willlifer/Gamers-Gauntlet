class_name FpsWeapons
extends RefCounted
## The prototype's three guns, as data: which kit asset, how it fires, how
## it sits in the view. Damage is out of 100 HP.
##   cycle    seconds between shots (the bolt / the pump / re-nocking)
##   spread   degrees of cone at the hip; ads_spread aimed; move_spread added
##            at full run (the reticle shows the same number)
##   ads_div  field-of-view divisor when aimed in; scope: the sniper's 4x is
##            FpsTune.scope_zoom and a scope overlay replaces the view model
##   hip      the grip's place in camera space (x right, y up, -z ahead)

const ORDER := ["sniper", "shotgun", "slingshot"]


## Bullets fly (G28): the rifle's and shotgun's rounds travel at FpsTune
## bullet_speed times the slingshot ball's full-draw speed (author: 5x), in a
## straight line, with a trail.
static func bullet_speed() -> float:
	return FpsTune.value("bullet_speed") * float(SPECS.slingshot.ball_speed)

const SPECS := {
	"sniper": { "name": "Bolt rifle", "asset": "sniper", "params": { "scale": 1.0, "bipod": "folded" },
		"damage": 85.0, "head": 2.5, "pellets": 1, "cycle": 1.25, "mag": 5, "reload": 2.4,
		"spread": 5.0, "ads_spread": 0.0, "move_spread": 6.0, "recoil": 8.0, "kick": 0.07,
		"ads_div": 1.0, "scope": true, "action": "bolt", "range": 600.0,
		"hip": Vector3(0.16, -0.19, -0.34), "tracer": Color(1.0, 0.85, 0.5) },
	"shotgun": { "name": "Pump shotgun", "asset": "shotgun", "params": { "scale": 1.0 },
		"damage": 13.0, "head": 1.5, "pellets": 9, "cycle": 0.85, "mag": 6, "reload": 0.45,
		"spread": 5.5, "ads_spread": 4.0, "move_spread": 2.0, "recoil": 10.0, "kick": 0.09,
		"ads_div": 1.2, "scope": false, "action": "pump", "range": 60.0, "shell_reload": true,
		"hip": Vector3(0.15, -0.2, -0.32), "tracer": Color(1.0, 0.8, 0.45) },
	"slingshot": { "name": "Slingshot", "asset": "slingshot", "params": { "scale": 1.3 },
		"damage": 70.0, "head": 2.0, "pellets": 1, "cycle": 0.35, "mag": 0, "reload": 0.0,
		"spread": 1.0, "ads_spread": 0.3, "move_spread": 3.0, "recoil": 3.0, "kick": 0.03,
		"ads_div": 1.15, "scope": false, "action": "draw", "draw_time": 0.75, "ball_speed": 75.0,
		"hip": Vector3(0.05, -0.2, -0.42), "tracer": Color(1, 1, 1) },
}
