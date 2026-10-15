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

##   auto     hold the trigger to keep firing (carbine, automatic rifle)
##   zoom     a scoped gun's own magnification (default FpsTune.scope_zoom)
##   slide    the pistols' action: the `slide` part kicks back and returns
## Loadouts (G43): every life you pick a primary on the radial (PRIMARIES);
## the sidearm is rolled: the 92FS, or half the time the Desert Eagle.
## Guns whose Blender model isn't built yet drop out of the lists.

##   dual     two of the asset, one per hand: LMB fires the left, RMB the right,
##            no aiming in; `mag` is each gun's; the reload is a trick (G43)

const ORDER := ["sniper", "marksman", "shotgun", "carbine", "auto_rifle", "dual_berettas", "pistol", "deagle", "slingshot"]
const PRIMARIES := ["sniper", "marksman", "shotgun", "carbine", "auto_rifle", "dual_berettas"]
## The radial's price tags (G43). Nothing costs anything; the Berettas are
## the cheapest thing on the wheel for no reason (author).
const PRICE := { "sniper": 4750, "marksman": 3100, "shotgun": 1200, "carbine": 1500, "auto_rifle": 2900, "dual_berettas": 1 }
const SIDEARMS := ["pistol", "deagle"]
const DEAGLE_CHANCE := 0.5
## What each gun is for, on the radial.
const ROLE := { "sniper": "One shot, long range", "marksman": "Fast bolt, 2.5x scope", "shotgun": "Close, brutal",
	"carbine": "Fast, light, close", "auto_rifle": "Full auto, red dot", "dual_berettas": "Left click left, right click right", "pistol": "Sidearm", "deagle": "Sidearm, big boom" }


## Is the gun's model built (procedural ones always are)?
static func available(id: String) -> bool:
	return SPECS.has(id) and GKRegistry.def(str(SPECS[id].asset)) != null


static func primaries() -> Array:
	return PRIMARIES.filter(func(id: String) -> bool: return available(id))


## The sidearm for a life: the Desert Eagle `DEAGLE_CHANCE` of the time; the
## slingshot only while no pistol is built.
static func roll_sidearm(rng: RandomNumberGenerator) -> String:
	var pick := "deagle" if rng.randf() < DEAGLE_CHANCE else "pistol"
	if not available(pick):
		pick = "pistol" if available("pistol") else ("deagle" if available("deagle") else "slingshot")
	return pick


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
	"marksman": { "name": "Marksman rifle", "asset": "marksman", "params": { "scale": 1.25 },
		"damage": 62.0, "head": 2.0, "pellets": 1, "cycle": 0.85, "mag": 4, "reload": 2.0,
		"spread": 4.0, "ads_spread": 0.0, "move_spread": 5.0, "recoil": 6.0, "kick": 0.06,
		"ads_div": 1.0, "scope": true, "zoom": 2.5, "action": "bolt", "range": 500.0,
		"hip": Vector3(0.16, -0.19, -0.36), "tracer": Color(1.0, 0.85, 0.5) },
	"carbine": { "name": "Personal carbine", "asset": "carbine", "params": { "scale": 1.25 },
		"damage": 15.0, "head": 1.8, "pellets": 1, "cycle": 0.075, "mag": 30, "reload": 1.7,
		"spread": 3.5, "ads_spread": 1.0, "move_spread": 1.5, "recoil": 2.0, "kick": 0.02,
		"ads_div": 1.2, "scope": false, "auto": true, "action": "auto", "range": 160.0,
		"hip": Vector3(0.14, -0.18, -0.36), "tracer": Color(1.0, 0.82, 0.5) },
	"auto_rifle": { "name": "Automatic rifle", "asset": "auto_rifle", "params": { "scale": 1.25 },
		"damage": 21.0, "head": 2.0, "pellets": 1, "cycle": 0.1, "mag": 30, "reload": 2.1,
		"spread": 3.0, "ads_spread": 0.5, "move_spread": 3.5, "recoil": 2.8, "kick": 0.025,
		"ads_div": 1.4, "scope": false, "auto": true, "action": "auto", "range": 300.0,
		"hip": Vector3(0.15, -0.19, -0.36), "tracer": Color(1.0, 0.8, 0.45) },
	"dual_berettas": { "name": "Dual Berettas", "asset": "pistol", "params": { "scale": 1.25 },
		"damage": 24.0, "head": 2.5, "pellets": 1, "cycle": 0.15, "mag": 15, "reload": 2.3,
		"spread": 2.8, "ads_spread": 2.8, "move_spread": 2.0, "recoil": 3.0, "kick": 0.035,
		"ads_div": 1.0, "scope": false, "action": "slide", "slide": 0.035, "dual": true, "range": 150.0,
		"hip": Vector3(0.15, -0.17, -0.36), "tracer": Color(1.0, 0.85, 0.55) },
	"pistol": { "name": "Pistol", "asset": "pistol", "params": { "scale": 1.25 },
		"damage": 26.0, "head": 2.5, "pellets": 1, "cycle": 0.17, "mag": 15, "reload": 1.3,
		"spread": 2.2, "ads_spread": 0.6, "move_spread": 2.0, "recoil": 3.5, "kick": 0.04,
		"ads_div": 1.15, "scope": false, "action": "slide", "slide": 0.035, "range": 150.0,
		"hip": Vector3(0.11, -0.16, -0.34), "tracer": Color(1.0, 0.85, 0.55) },
	"deagle": { "name": "Desert Eagle", "asset": "deagle", "params": { "scale": 1.25 },
		"damage": 55.0, "head": 2.2, "pellets": 1, "cycle": 0.45, "mag": 7, "reload": 1.7,
		"spread": 3.0, "ads_spread": 0.5, "move_spread": 3.5, "recoil": 10.0, "kick": 0.09,
		"ads_div": 1.15, "scope": false, "action": "slide", "slide": 0.045, "boom": true, "range": 200.0,
		"hip": Vector3(0.11, -0.16, -0.35), "tracer": Color(1.0, 0.75, 0.4) },
	"slingshot": { "name": "Slingshot", "asset": "slingshot", "params": { "scale": 1.3 },
		"damage": 70.0, "head": 2.0, "pellets": 1, "cycle": 0.35, "mag": 0, "reload": 0.0,
		"spread": 1.0, "ads_spread": 0.3, "move_spread": 3.0, "recoil": 3.0, "kick": 0.03,
		"ads_div": 1.15, "scope": false, "action": "draw", "draw_time": 0.75, "ball_speed": 75.0,
		"hip": Vector3(0.05, -0.2, -0.42), "tracer": Color(1, 1, 1) },
}
