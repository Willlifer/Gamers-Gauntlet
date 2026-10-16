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

##   recoil / kick  the view model's spring kick (rotation deg, push back m);
##            punch: the camera's kick per shot (deg at FpsTune.recoil 1);
##            bloom: inaccuracy added per shot (deg). G51: the Desert Eagle's
##            profile (big punch, big spring) went to the rifles and the
##            shotgun, scaled per gun; the automatics take it per shot, small,
##            so it climbs over a burst
##   flash    the muzzle flash's size (x; G51, after design/ref/kit/muzzle_flash.png)
##   ads_dist aimed-in distance from the eye to the sight (m; default 0.06): the
##            pistols 0.66 (G51c: at arm's length), the scoped rifles 0.11
##            (G51c: the scope 5 cm further off the eye)
##   sway     this gun's share of FpsTune sway (G51c: 0.7 on the pistols, the
##            automatic rifle and the carbine; the bolt guns keep 1)
##   lens     a sight with a picture in it (G51): [ocular lens distance ahead
##            of the eye marker, its radius] in the model's own metres (x the
##            build scale), and lens_zoom; FpsViewmodel renders a small,
##            low-res magnified view onto it
##   optics   (G51c) the sights you can pick on the radial: default, the rail
##            top (model metres), and per kind (iron / red_dot / scope) either
##            a `build` for FpsOptic (reflex, scope, irons: axis height, `at`
##            along the gun, eye_back) or the model's own part (`eye` [height,
##            z], a `lens` [z, radius]); `hide` lists model parts to take off
##   dual     two of the asset, one per hand: LMB fires the left, RMB the right,
##            no aiming in; `mag` is each gun's; the reload is a trick (G43)

## The optics' names on the radial (G51c).
const OPTIC_NAMES := { "iron": "Iron sights", "red_dot": "Red dot", "scope": "Scope" }
const OPTIC_ORDER := ["iron", "red_dot", "scope"]

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


## G51b: the recoil profile's fields, and the named presets the F1 panel
## offers per gun (the author picks one, then trims it by feel with the
## gun's own scale). A preset is a gun's baked profile; "Baked" is the gun's
## own. Fields: recoil (the view model's climb, deg), kick (its push back,
## m), punch (the camera's kick, deg at FpsTune.recoil 1), side (sideways
## jitter, x), recover (how fast the camera's punch settles, rad/s), bloom
## (inaccuracy per shot, deg).
const RECOIL_KEYS := ["recoil", "kick", "punch", "side", "recover", "bloom"]
const RECOIL_DEFAULTS := { "side": 1.0, "recover": 0.5 }
const RECOIL_PRESETS := { "Desert Eagle": "deagle", "Rifle": "auto_rifle", "Sniper": "sniper",
	"Shotgun": "shotgun", "Pistol": "pistol", "Carbine": "carbine" }


## A gun's baked recoil profile (RECOIL_KEYS).
static func baked_recoil(id: String) -> Dictionary:
	var sp: Dictionary = SPECS[id]
	var out := {}
	for k in RECOIL_KEYS:
		out[k] = float(sp.get(k, RECOIL_DEFAULTS.get(k, float(sp.recoil) * 0.35)))
	return out


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
		"spread": 5.0, "ads_spread": 0.0, "move_spread": 6.0, "recoil": 10.0, "kick": 0.09, "punch": 2.0, "bloom": 2.8, "flash": 1.6,
		"ads_div": 1.0, "scope": true, "action": "bolt", "range": 600.0, "lens": [0.186, 0.0172], "ads_dist": 0.11,
		"hip": Vector3(0.16, -0.19, -0.34), "tracer": Color(1.0, 0.85, 0.5) },
	"shotgun": { "name": "Pump shotgun", "asset": "shotgun", "params": { "scale": 1.0 },
		"damage": 13.0, "head": 1.5, "pellets": 9, "cycle": 0.85, "mag": 6, "reload": 0.45,
		"spread": 5.5, "ads_spread": 4.0, "move_spread": 2.0, "recoil": 11.0, "kick": 0.1, "punch": 2.3, "bloom": 3.5, "flash": 1.6,
		"ads_div": 1.2, "scope": false, "action": "pump", "range": 60.0, "shell_reload": true,
		"hip": Vector3(0.15, -0.2, -0.32), "tracer": Color(1.0, 0.8, 0.45) },
	"marksman": { "name": "Marksman rifle", "asset": "marksman", "params": { "scale": 1.25 },
		"damage": 62.0, "head": 2.0, "pellets": 1, "cycle": 0.85, "mag": 4, "reload": 2.0,
		"spread": 4.0, "ads_spread": 0.0, "move_spread": 5.0, "recoil": 9.0, "kick": 0.08, "punch": 1.6, "bloom": 2.1, "flash": 1.3,
		"ads_div": 1.0, "scope": true, "zoom": 2.5, "action": "bolt", "range": 500.0, "lens": [0.0803, 0.0168], "ads_dist": 0.11,
		"hip": Vector3(0.16, -0.19, -0.36), "tracer": Color(1.0, 0.85, 0.5) },
	"carbine": { "name": "Personal carbine", "asset": "carbine", "params": { "scale": 1.25 },
		"damage": 15.0, "head": 1.8, "pellets": 1, "cycle": 0.075, "mag": 30, "reload": 1.7,
		"spread": 3.5, "ads_spread": 1.0, "move_spread": 1.5, "recoil": 4.2, "kick": 0.042, "punch": 0.5, "bloom": 0.7, "flash": 0.9, "sway": 0.7,
		"ads_div": 1.2, "scope": false, "auto": true, "action": "auto", "range": 160.0,
		"optics": { "default": "iron", "rail": 0.1287,
			"iron": { "eye": [0.1489, -0.068], "hide": [] },
			"red_dot": { "build": "reflex", "axis": 0.168, "at": 0.05, "eye_back": 0.1, "hide": ["sights"] },
			"scope": { "build": "scope", "axis": 0.172, "at": 0.07, "len": 0.15, "r": 0.016, "zoom": 2.5, "eye_back": 0.1, "hide": ["sights"] } },
		"hip": Vector3(0.14, -0.18, -0.36), "tracer": Color(1.0, 0.82, 0.5) },
	"auto_rifle": { "name": "Automatic rifle", "asset": "auto_rifle", "params": { "scale": 1.25 },
		"damage": 21.0, "head": 2.0, "pellets": 1, "cycle": 0.1, "mag": 30, "reload": 2.1,
		"spread": 3.0, "ads_spread": 0.5, "move_spread": 3.5, "recoil": 4.6, "kick": 0.045, "punch": 0.6, "bloom": 0.98, "flash": 1.2, "sway": 0.7,
		"ads_div": 1.4, "scope": false, "auto": true, "action": "auto", "range": 300.0,
		"optics": { "default": "red_dot", "rail": 0.127,
			"iron": { "build": "irons", "axis": 0.157, "rear": 0.03, "front": 0.45, "eye_back": 0.05, "hide": ["optic", "sights"] },
			"red_dot": { "build": "reflex", "axis": 0.165, "at": 0.12, "eye_back": 0.1, "hide": ["optic"] },
			"scope": { "eye": [0.171, 0.02], "lens": [0.0968, 0.0128], "zoom": 2.5, "hide": [] } },
		"hip": Vector3(0.15, -0.19, -0.36), "tracer": Color(1.0, 0.8, 0.45) },
	"dual_berettas": { "name": "Dual Berettas", "asset": "pistol", "params": { "scale": 1.25 },
		"damage": 24.0, "head": 2.5, "pellets": 1, "cycle": 0.15, "mag": 15, "reload": 2.3,
		"spread": 2.8, "ads_spread": 2.8, "move_spread": 2.0, "recoil": 3.0, "kick": 0.035, "punch": 0.36, "bloom": 1.05, "flash": 0.7, "sway": 0.7,
		"ads_div": 1.0, "scope": false, "action": "slide", "slide": 0.035, "dual": true, "range": 150.0,
		"hip": Vector3(0.15, -0.17, -0.36), "tracer": Color(1.0, 0.85, 0.55) },
	"pistol": { "name": "Pistol", "asset": "pistol", "params": { "scale": 1.25 },
		"damage": 26.0, "head": 2.5, "pellets": 1, "cycle": 0.17, "mag": 15, "reload": 1.3,
		"spread": 2.2, "ads_spread": 0.6, "move_spread": 2.0, "recoil": 3.5, "kick": 0.04, "punch": 0.42, "bloom": 1.22, "flash": 0.55, "ads_dist": 0.66, "sway": 0.7,
		"ads_div": 1.15, "scope": false, "action": "slide", "slide": 0.035, "range": 150.0,
		"hip": Vector3(0.11, -0.16, -0.34), "tracer": Color(1.0, 0.85, 0.55) },
	"deagle": { "name": "Desert Eagle", "asset": "deagle", "params": { "scale": 1.25 },
		"damage": 55.0, "head": 2.2, "pellets": 1, "cycle": 0.45, "mag": 7, "reload": 1.7,
		"spread": 3.0, "ads_spread": 0.5, "move_spread": 3.5, "recoil": 10.0, "kick": 0.09, "punch": 2.16, "bloom": 3.5, "flash": 1.25, "ads_dist": 0.66, "sway": 0.7,
		"ads_div": 1.15, "scope": false, "action": "slide", "slide": 0.045, "boom": true, "range": 200.0,
		"hip": Vector3(0.11, -0.16, -0.35), "tracer": Color(1.0, 0.75, 0.4) },
	"slingshot": { "name": "Slingshot", "asset": "slingshot", "params": { "scale": 1.3 },
		"damage": 70.0, "head": 2.0, "pellets": 1, "cycle": 0.35, "mag": 0, "reload": 0.0,
		"spread": 1.0, "ads_spread": 0.3, "move_spread": 3.0, "recoil": 3.0, "kick": 0.03, "punch": 0.36, "bloom": 1.05, "flash": 0.0,
		"ads_div": 1.15, "scope": false, "action": "draw", "draw_time": 0.75, "ball_speed": 75.0,
		"hip": Vector3(0.05, -0.2, -0.42), "tracer": Color(1, 1, 1) },
}
