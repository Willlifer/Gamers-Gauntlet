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
##   caliber  Extraction: "rifle" | "shotgun" | "pistol", the magazine pool a
##            reload draws from when FpsPlayer.scarce (the rifles, the carbine
##            and the automatic rifle share "rifle"; every pistol "pistol")
##   value    $ for the Extraction verdict (and the loot tables)
##   base     a variant: the gun it is built on (Extraction: two per base, 14,
##            VARIANTS). The asset and every number not given come from the
##            base (spec() merges them; `params` and `optics` merge a level
##            deeper); `dress` is how it looks: FpsVariants.apply reads it
##            ({ tint: a GKMaterials role or "role:#hex" for the furniture
##            surfaces (tint_of names other base roles), mods: [{ kind, ... }]
##            built onto the base asset at its markers })

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
	"carbine": "Fast, light, close", "auto_rifle": "Full auto, red dot", "dual_berettas": "Left click left, right click right", "pistol": "Sidearm", "deagle": "Sidearm, big boom",
	# Extraction's variants (loot, never on the duel radial)
	"sniper_scout": "Short bolt rifle, red dot, 65", "sniper_sd": "Suppressed bolt rifle: quiet, soft",
	"marksman_am": "Anti-materiel: 90, three rounds, kicks", "marksman_ranch": "Light bolt rifle, 8 rounds, 50",
	"shotgun_slug": "One slug, 70, 2.5x scope", "shotgun_riot": "Short riot gun: 12 pellets, 8 shells",
	"carbine_buck": "Buckshot carbine: slow, 12 rounds of spread", "carbine_sd": "Suppressed carbine: quiet, less kick, 13",
	"auto_rifle_drum": "Drum rifle: 60 rounds, slower, blooms", "auto_rifle_battle": "Battle rifle: semi, 34, 2.5x",
	"pistol_compact": "Compact: 10 rounds, quick, 22", "pistol_match": "Match pistol: long slide, red dot, 17",
	"deagle_brass": "Brass Desert Eagle, 8 rounds", "deagle_snub": "Snub Desert Eagle: 5 rounds, 62, bigger boom" }

## Extraction: the 14 variants (two per base), in base order. Loot and the
## bot's loadout roll from here; PRIMARIES (the duel radial) is unchanged.
const VARIANTS := ["sniper_scout", "sniper_sd", "marksman_am", "marksman_ranch", "shotgun_slug", "shotgun_riot",
	"carbine_buck", "carbine_sd", "auto_rifle_drum", "auto_rifle_battle", "pistol_compact", "pistol_match", "deagle_brass", "deagle_snub"]

static var _merged := {}                    # id -> the merged spec (spec())


## The gun's full spec: a base gun's SPECS entry as is; a variant's merged
## over its base (its own keys win; `params` and `optics` merge a level
## deeper, so a variant can change one parameter or just the default sight).
## Everything that reads a gun by id goes through here, so variants fire,
## sit in the hand and arm the bot like the base guns.
static func spec(id: String) -> Dictionary:
	if _merged.has(id):
		return _merged[id]
	var sp: Dictionary = SPECS[id]
	if not sp.has("base"):
		return sp
	var out: Dictionary = (SPECS[str(sp.base)] as Dictionary).duplicate(true)
	for k in sp:
		if sp[k] == null:
			out.erase(k)                        # "lens": null drops the base's sight picture
		elif (k == "params" or k == "optics") and out.get(k) is Dictionary and sp[k] is Dictionary:
			var d: Dictionary = (out[k] as Dictionary).duplicate()
			d.merge(sp[k], true)
			out[k] = d
		else:
			out[k] = sp[k]
	_merged[id] = out
	return out


## The variants of a base gun (Extraction's loot tables).
static func variants_of(base_id: String) -> Array:
	return VARIANTS.filter(func(id: String) -> bool: return str(SPECS[id].base) == base_id)


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
	var sp := spec(id)
	var out := {}
	for k in RECOIL_KEYS:
		out[k] = float(sp.get(k, RECOIL_DEFAULTS.get(k, float(sp.recoil) * 0.35)))
	return out


## Is the gun's model built (procedural ones always are)?
static func available(id: String) -> bool:
	return SPECS.has(id) and GKRegistry.def(str(spec(id).asset)) != null


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
	"sniper": { "name": "Bolt rifle", "asset": "sniper", "params": { "scale": 1.0, "bipod": "folded" }, "caliber": "rifle", "value": 4500,
		"damage": 85.0, "head": 2.5, "pellets": 1, "cycle": 1.25, "mag": 5, "reload": 2.4,
		"spread": 5.0, "ads_spread": 0.0, "move_spread": 6.0, "recoil": 10.0, "kick": 0.09, "punch": 2.0, "bloom": 2.8, "flash": 1.6,
		"ads_div": 1.0, "scope": true, "action": "bolt", "range": 600.0, "lens": [0.186, 0.0172], "ads_dist": 0.11,
		"hip": Vector3(0.16, -0.19, -0.34), "tracer": Color(1.0, 0.85, 0.5) },
	"shotgun": { "name": "Pump shotgun", "asset": "shotgun", "params": { "scale": 1.0 }, "caliber": "shotgun", "value": 1200,
		"damage": 13.0, "head": 1.5, "pellets": 9, "cycle": 0.85, "mag": 6, "reload": 0.45,
		"spread": 5.5, "ads_spread": 4.0, "move_spread": 2.0, "recoil": 11.0, "kick": 0.1, "punch": 2.3, "bloom": 3.5, "flash": 1.6,
		"ads_div": 1.2, "scope": false, "action": "pump", "range": 60.0, "shell_reload": true,
		"hip": Vector3(0.15, -0.2, -0.32), "tracer": Color(1.0, 0.8, 0.45) },
	"marksman": { "name": "Marksman rifle", "asset": "marksman", "params": { "scale": 1.25 }, "caliber": "rifle", "value": 3100,
		"damage": 62.0, "head": 2.0, "pellets": 1, "cycle": 0.85, "mag": 4, "reload": 2.0,
		"spread": 4.0, "ads_spread": 0.0, "move_spread": 5.0, "recoil": 9.0, "kick": 0.08, "punch": 1.6, "bloom": 2.1, "flash": 1.3,
		"ads_div": 1.0, "scope": true, "zoom": 2.5, "action": "bolt", "range": 500.0, "lens": [0.0803, 0.0168], "ads_dist": 0.11,
		"hip": Vector3(0.16, -0.19, -0.36), "tracer": Color(1.0, 0.85, 0.5) },
	"carbine": { "name": "Personal carbine", "asset": "carbine", "params": { "scale": 1.25 }, "caliber": "rifle", "value": 1500,
		"damage": 15.0, "head": 1.8, "pellets": 1, "cycle": 0.075, "mag": 30, "reload": 1.7,
		"spread": 3.5, "ads_spread": 1.0, "move_spread": 1.5, "recoil": 4.2, "kick": 0.042, "punch": 0.5, "bloom": 0.7, "flash": 0.9, "sway": 0.7,
		"ads_div": 1.2, "scope": false, "auto": true, "action": "auto", "range": 160.0,
		"optics": { "default": "iron", "rail": 0.1287,
			"iron": { "eye": [0.1489, -0.068], "hide": [] },
			"red_dot": { "build": "reflex", "axis": 0.168, "at": 0.05, "eye_back": 0.1, "hide": ["sights"] },
			"scope": { "build": "scope", "axis": 0.172, "at": 0.07, "len": 0.15, "r": 0.016, "zoom": 2.5, "eye_back": 0.1, "hide": ["sights"] } },
		"hip": Vector3(0.14, -0.18, -0.36), "tracer": Color(1.0, 0.82, 0.5) },
	"auto_rifle": { "name": "Automatic rifle", "asset": "auto_rifle", "params": { "scale": 1.25 }, "caliber": "rifle", "value": 2900,
		"damage": 21.0, "head": 2.0, "pellets": 1, "cycle": 0.1, "mag": 30, "reload": 2.1,
		"spread": 3.0, "ads_spread": 0.5, "move_spread": 3.5, "recoil": 4.6, "kick": 0.045, "punch": 0.6, "bloom": 0.98, "flash": 1.2, "sway": 0.7,
		"ads_div": 1.4, "scope": false, "auto": true, "action": "auto", "range": 300.0,
		"optics": { "default": "red_dot", "rail": 0.127,
			"iron": { "build": "irons", "axis": 0.157, "rear": 0.03, "front": 0.45, "eye_back": 0.05, "hide": ["optic", "sights"] },
			"red_dot": { "build": "reflex", "axis": 0.165, "at": 0.12, "eye_back": 0.1, "hide": ["optic"] },
			"scope": { "eye": [0.171, 0.02], "lens": [0.0968, 0.0128], "zoom": 2.5, "hide": [] } },
		"hip": Vector3(0.15, -0.19, -0.36), "tracer": Color(1.0, 0.8, 0.45) },
	"dual_berettas": { "name": "Dual Berettas", "asset": "pistol", "params": { "scale": 1.25 }, "caliber": "pistol", "value": 700,
		"damage": 24.0, "head": 2.5, "pellets": 1, "cycle": 0.15, "mag": 15, "reload": 2.3,
		"spread": 2.8, "ads_spread": 2.8, "move_spread": 2.0, "recoil": 3.0, "kick": 0.035, "punch": 0.36, "bloom": 1.05, "flash": 0.7, "sway": 0.7,
		"ads_div": 1.0, "scope": false, "action": "slide", "slide": 0.035, "dual": true, "range": 150.0,
		"hip": Vector3(0.15, -0.17, -0.36), "tracer": Color(1.0, 0.85, 0.55) },
	"pistol": { "name": "Pistol", "asset": "pistol", "params": { "scale": 1.25 }, "caliber": "pistol", "value": 400,
		"damage": 26.0, "head": 2.5, "pellets": 1, "cycle": 0.17, "mag": 15, "reload": 1.3,
		"spread": 2.2, "ads_spread": 0.6, "move_spread": 2.0, "recoil": 3.5, "kick": 0.04, "punch": 0.42, "bloom": 1.22, "flash": 0.55, "ads_dist": 0.66, "sway": 0.7,
		"ads_div": 1.15, "scope": false, "action": "slide", "slide": 0.035, "range": 150.0,
		"hip": Vector3(0.11, -0.16, -0.34), "tracer": Color(1.0, 0.85, 0.55) },
	"deagle": { "name": "Desert Eagle", "asset": "deagle", "params": { "scale": 1.25 }, "caliber": "pistol", "value": 900,
		"damage": 55.0, "head": 2.2, "pellets": 1, "cycle": 0.45, "mag": 7, "reload": 1.7,
		"spread": 3.0, "ads_spread": 0.5, "move_spread": 3.5, "recoil": 10.0, "kick": 0.09, "punch": 2.16, "bloom": 3.5, "flash": 1.25, "ads_dist": 0.66, "sway": 0.7,
		"ads_div": 1.15, "scope": false, "action": "slide", "slide": 0.045, "boom": true, "range": 200.0,
		"hip": Vector3(0.11, -0.16, -0.35), "tracer": Color(1.0, 0.75, 0.4) },
	"slingshot": { "name": "Slingshot", "asset": "slingshot", "params": { "scale": 1.3 }, "caliber": "pistol", "value": 50,
		"damage": 70.0, "head": 2.0, "pellets": 1, "cycle": 0.35, "mag": 0, "reload": 0.0,
		"spread": 1.0, "ads_spread": 0.3, "move_spread": 3.0, "recoil": 3.0, "kick": 0.03, "punch": 0.36, "bloom": 1.05, "flash": 0.0,
		"ads_div": 1.15, "scope": false, "action": "draw", "draw_time": 0.75, "ball_speed": 75.0,
		"hip": Vector3(0.05, -0.2, -0.42), "tracer": Color(1, 1, 1) },
	# ---- Extraction's variants (VARIANTS): base ⊕ these. Mod sizes are model
	# metres (x the build scale); `at`/`axis` along and above the grip.
	"sniper_scout": { "base": "sniper", "name": "Scout rifle", "value": 3600, "params": { "barrel": 0.46, "scope": false, "bipod": "none" },
		"damage": 65.0, "cycle": 0.8, "mag": 5, "reload": 2.0, "spread": 4.0, "ads_spread": 0.4, "move_spread": 4.0,
		"recoil": 8.0, "kick": 0.07, "punch": 1.5, "bloom": 2.2, "flash": 1.4, "ads_div": 1.3, "scope": false, "range": 350.0, "ads_dist": 0.09, "sway": 0.85, "lens": null,
		"dress": { "tint": "polymer_fde", "mods": [{ "kind": "red_dot", "at": 0.14, "eye_back": 0.14 }, { "kind": "brake", "len": 0.055, "r": 0.015 }] } },
	"sniper_sd": { "base": "sniper", "name": "Suppressed bolt rifle", "value": 5200, "params": { "stock": "black" },
		"damage": 78.0, "cycle": 1.25, "mag": 5, "recoil": 6.5, "kick": 0.06, "punch": 1.3, "bloom": 2.0, "flash": 0.35, "range": 500.0,
		"dress": { "tint": "polymer_black", "mods": [{ "kind": "suppressor", "len": 0.19, "r": 0.021 }] } },
	"marksman_am": { "base": "marksman", "name": "Anti-materiel rifle", "value": 4200,
		"damage": 90.0, "head": 2.0, "cycle": 1.4, "mag": 3, "reload": 2.8, "spread": 5.0, "move_spread": 6.0,
		"recoil": 16.0, "kick": 0.14, "punch": 3.2, "bloom": 4.0, "flash": 2.0, "zoom": 3.0, "range": 700.0,
		"dress": { "tint": "paint_army", "tint_of": ["polymer_speckle"], "mods": [{ "kind": "long_barrel", "len": 0.14, "r": 0.013 }, { "kind": "brake", "len": 0.07, "r": 0.019 }, { "kind": "stock", "len": 0.04 }] } },
	"marksman_ranch": { "base": "marksman", "name": "Ranch rifle", "value": 2400,
		"damage": 50.0, "cycle": 0.6, "mag": 8, "reload": 1.8, "spread": 3.5, "recoil": 6.5, "kick": 0.06, "punch": 1.1, "bloom": 1.6, "flash": 1.1, "range": 400.0,
		"dress": { "tint": "polymer_fde", "tint_of": ["polymer_speckle"], "mods": [{ "kind": "ext_mag", "len": 0.055 }] } },
	"shotgun_slug": { "base": "shotgun", "name": "Slug shotgun", "value": 1900, "params": { "barrel": 0.8, "finish": "olive" },
		"damage": 70.0, "head": 1.8, "pellets": 1, "cycle": 1.0, "mag": 5, "spread": 1.6, "ads_spread": 0.0, "move_spread": 4.0,
		"recoil": 12.0, "kick": 0.11, "punch": 2.4, "bloom": 3.0, "ads_div": 1.0, "scope": true, "zoom": 2.5, "range": 160.0, "ads_dist": 0.11, "lens": [0.079, 0.0166],
		"dress": { "tint": "polymer_olive", "mods": [{ "kind": "long_barrel", "len": 0.08, "r": 0.0108 }, { "kind": "scope", "at": 0.1, "len": 0.2, "r": 0.0155, "eye_back": 0.08 }] } },
	"shotgun_riot": { "base": "shotgun", "name": "Riot shotgun", "value": 1000, "params": { "barrel": 0.47, "mag": 0.45, "vent_rib": false, "stock": "pistol_grip" },
		"damage": 10.0, "pellets": 12, "cycle": 0.7, "mag": 8, "reload": 0.4, "spread": 8.0, "ads_spread": 6.0, "recoil": 12.0, "kick": 0.11, "punch": 2.5, "bloom": 4.0, "flash": 1.8, "range": 40.0,
		"hip": Vector3(0.15, -0.2, -0.3),
		"dress": { "tint": "polymer_black", "mods": [{ "kind": "brake", "len": 0.05, "r": 0.016, "role": "steel" }] } },
	"carbine_buck": { "base": "carbine", "name": "Buckshot carbine", "value": 1300,
		"damage": 9.0, "head": 1.5, "pellets": 6, "cycle": 0.14, "mag": 12, "reload": 1.9, "spread": 6.0, "ads_spread": 4.5, "move_spread": 2.0,
		"recoil": 7.0, "kick": 0.07, "punch": 1.2, "bloom": 2.0, "flash": 1.4, "range": 50.0, "optics": { "default": "iron" },
		"dress": { "tint": "polymer_olive", "mods": [{ "kind": "brake", "len": 0.045, "r": 0.016 }] } },
	"carbine_sd": { "base": "carbine", "name": "Suppressed carbine", "value": 1800,
		"damage": 13.0, "spread": 3.0, "ads_spread": 0.8, "recoil": 3.0, "kick": 0.03, "punch": 0.35, "bloom": 0.5, "flash": 0.3, "optics": { "default": "red_dot" },
		"dress": { "tint": "polymer_speckle", "mods": [{ "kind": "suppressor", "len": 0.17, "r": 0.018 }] } },
	"auto_rifle_drum": { "base": "auto_rifle", "name": "Drum rifle", "value": 3300,
		"cycle": 0.115, "mag": 60, "reload": 3.2, "spread": 3.5, "ads_spread": 0.8, "bloom": 1.4, "recoil": 5.0, "sway": 0.85,
		"dress": { "tint": "paint_army", "tint_of": ["anodized_fde"], "mods": [{ "kind": "drum", "r": 0.046, "w": 0.055 }] } },
	"auto_rifle_battle": { "base": "auto_rifle", "name": "Battle rifle", "value": 3400,
		"damage": 34.0, "cycle": 0.2, "auto": false, "mag": 20, "reload": 2.3, "spread": 2.5, "ads_spread": 0.3, "move_spread": 4.0,
		"recoil": 7.0, "kick": 0.07, "punch": 1.1, "bloom": 1.6, "flash": 1.4, "range": 450.0, "optics": { "default": "scope" },
		"dress": { "tint": "polymer_black", "tint_of": ["anodized_fde"], "mods": [{ "kind": "long_barrel", "len": 0.1, "r": 0.011 }, { "kind": "brake", "len": 0.06, "r": 0.016 }, { "kind": "stock", "len": 0.035, "h": 0.1 }] } },
	"pistol_compact": { "base": "pistol", "name": "Compact pistol", "value": 300,
		"damage": 22.0, "cycle": 0.13, "mag": 10, "reload": 1.1, "spread": 2.6, "ads_spread": 0.9, "recoil": 3.0, "kick": 0.035, "punch": 0.36, "bloom": 1.1, "flash": 0.5, "range": 110.0,
		"dress": { "tint": "steel_bright", "tint_of": ["blued"], "mods": [{ "kind": "light", "len": 0.04, "r": 0.011 }] } },
	"pistol_match": { "base": "pistol", "name": "Match pistol", "value": 700,
		"damage": 28.0, "cycle": 0.15, "mag": 17, "reload": 1.4, "spread": 1.6, "ads_spread": 0.3, "bloom": 0.9, "flash": 0.6, "range": 180.0,
		"dress": { "tint": "polymer_fde", "mods": [{ "kind": "long_barrel", "len": 0.045, "r": 0.0085, "role": "steel_bright" }, { "kind": "red_dot", "at": 0.02, "size": 0.6, "eye_back": 0.08 }, { "kind": "ext_mag", "len": 0.025 }] } },
	"deagle_brass": { "base": "deagle", "name": "Desert Eagle, brass", "value": 1400,
		"mag": 8, "cycle": 0.4, "reload": 1.6, "bloom": 3.0,
		"dress": { "tint": "brass", "tint_of": ["steel_bright"], "mods": [{ "kind": "ext_mag", "len": 0.03, "w": 0.028, "d": 0.046, "z": 0.005 }] } },
	"deagle_snub": { "base": "deagle", "name": "Desert Eagle snub", "value": 1100,
		"damage": 62.0, "mag": 5, "cycle": 0.55, "spread": 3.6, "ads_spread": 0.8, "recoil": 13.0, "kick": 0.11, "punch": 2.8, "bloom": 4.0, "flash": 1.7, "range": 120.0,
		"dress": { "tint": "blued", "tint_of": ["steel_bright"], "mods": [{ "kind": "brake", "len": 0.022, "r": 0.02, "ports": 2, "role": "steel_bright" }] } },
}
