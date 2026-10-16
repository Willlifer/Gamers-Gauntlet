class_name GGAnim
extends RefCounted
## Gamers Gauntlet's own stick-figure clips (G55), authored in Black | White's
## clip pipeline (BWAnimClips: pose-space keys, the solver turns them into
## bones) and baked into a character's library at runtime. Black | White's
## sets and saved .res files are untouched: each style gets an extended copy
## of its library (B/W's clips + these), built once and shared.
##
##   GGAnim.install(ch, "skip")      # Temu: walk / run play the skip
##   GGAnim.install(ch, "float")     # Merr: godly floating (hover + serene glide)
##   GGAnim.install(ch, "cool")      # Braves: the cool walk
##   ch.pose(GGAnim.cast_clip("thrust"))   # a short cast gesture (any installed style)
##   GGAnim.float_twins_under(node)  # the Twins in a B/W fight float this way too
##
## Clips (frames at 24 fps, "on ones"):
##   gg_skip       18 f loop, 2.5 u per cycle: step-hop, step-hop, knee up,
##                 the opposite arm swinging high
##   gg_float      48 f loop: upright, chest open, arms out low with the palms
##                 open, one knee bent and the toes hanging; it rides on B/W's
##                 Twin hover (D298), which lifts, bobs and drops the feet
##   gg_cool_walk  16 f loop, 2.1 u per cycle: leaned back, long unhurried
##                 steps toes-out, the shoulders roll; the gun (pistol set)
##                 hangs along the right leg, the free hand barely swings
##   gg_cast_*     14 f one-shots: coil f3, release f6 (0.25 s, inside the
##                 ~0.3 s cast stop), held to f9, back to the guard by f14:
##                 thrust, slam, flick, shoot, blast, toss, rally

const FPS := 24.0
const CAST_KINDS: PackedStringArray = ["thrust", "slam", "flick", "shoot", "blast", "toss", "rally"]
const CAST_FRAMES := 14
const SKIP_FRAMES := 18
const SKIP_STRIDE := 2.5
const COOL_FRAMES := 16
const COOL_STRIDE := 2.1
const FLOAT_FRAMES := 48

static var _libs := {}            # style -> AnimationLibrary (B/W's set + ours)


# ================================================================ install

## B/W's library for a style plus every GG clip, built once per style.
static func library(style: String) -> AnimationLibrary:
	if _libs.has(style):
		return _libs[style]
	var base := BWAnimClips.load_set(style)
	var lib := AnimationLibrary.new()
	for n in base.get_animation_list():
		lib.add_animation(n, base.get_animation(n))
	lib.set_meta("bw", base.get_meta("bw", {}))
	for c in clips(style):
		lib.add_animation(StringName(c.name), BWAnimClips.bake(c))
	_libs[style] = lib
	return lib


## Give a built character the GG clips and (optionally) a locomotion:
## "skip", "float", "cool" or "" (keep B/W's walk and run).
static func install(ch: BWCharacter, gait: String = "") -> void:
	if ch == null or ch.animator == null:
		return
	var an := ch.animator
	an.library = library(an.set_id)
	match gait:
		"skip":
			an.actions.walk = { "clip": "gg_skip" }
			an.actions.run = { "clip": "gg_skip" }
		"cool":
			an.actions.walk = { "clip": "gg_cool_walk" }
			an.actions.run = { "clip": "gg_cool_walk" }
		"float":
			# B/W's Twin hover (D298) does the lifting, the bob and the hanging
			# toes; our clip is the serene body on top of it
			an.encounter = "twin"
			an.rotate_idles = false
			an.actions.walk = { "clip": "gg_float" }
			an.actions.run = { "clip": "gg_float" }
	if an.current in ["walk", "run"]:
		an.play(an.current)


## The pose name of a cast gesture (a clip name: BWAnimator plays clips by name).
static func cast_clip(kind: String) -> String:
	return "gg_cast_" + (kind if kind in CAST_KINDS else "thrust")


## The Twins in a Black | White fight under `n` glide with godly floating:
## every Twin character built under it gets the float as its walk / run.
static func float_twins_under(n: Node) -> void:
	if n == null:
		return
	var tree := n.get_tree() if n.is_inside_tree() else Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var cb := func(added: Node) -> void:
		if added is BWCharacter and n.is_ancestor_of(added):
			_float_twin.call_deferred(added)
	tree.node_added.connect(cb)
	n.tree_exiting.connect(func() -> void:
		if tree.node_added.is_connected(cb):
			tree.node_added.disconnect(cb), CONNECT_ONE_SHOT)
	_float_all(n)


static func _float_all(n: Node) -> void:
	if n is BWCharacter:
		_float_twin(n)
	for c in n.get_children():
		_float_all(c)


static func _float_twin(ch: BWCharacter) -> void:
	if not is_instance_valid(ch) or ch.animator == null or ch.animator.encounter != "twin":
		return
	if ch.animator.actions.get("walk", {}).get("clip", "") == "gg_float":
		return
	ch.animator.library = library(ch.animator.set_id)
	ch.animator.actions.walk = { "clip": "gg_float" }
	ch.animator.actions.run = { "clip": "gg_float" }


# ================================================================ sources

static func clips(st: String) -> Array:
	var out: Array = [skip(st), godly_float(st), cool_walk(st)]
	for k in CAST_KINDS:
		out.append(cast(st, k))
	return out


## Which hand holds the weapon / which is free, per style.
static func _weapon_hand(st: String) -> String:
	return "hand_l" if st == "bow" else "hand_r"


static func _free_hand(st: String) -> String:
	return "hand_r" if st == "bow" else "hand_l"


static func _sx(hand: String) -> float:
	return 1.0 if hand == "hand_l" else -1.0


static func _minjerk(s: float) -> float:
	return 10 * pow(s, 3) - 15 * pow(s, 4) + 6 * pow(s, 5)


# ------------------------------------------------------------------ skip

## One foot of the skip at phase u (0 = this foot's step down). In the
## world the foot lands, hops once on the spot (a short forward travel),
## lands again on the ball, then swings through with the knee driven up.
## Model z = world z minus the root's travel (D per cycle), so the stance
## foot never slides (the runtime lock agrees).
static func skip_foot(u: float, x: float, yaw: float, D: float) -> Array:
	const S1 := 0.15       # first stance ends: the hop leaves
	const S2 := 0.29       # the hop lands
	const S3 := 0.44       # second stance ends: toe-off into the swing
	var H := 0.12 * D      # the hop's forward travel
	var A := (S3 * D - H) * 0.5
	var w := 0.0
	var lift := 0.0
	var p := 0.0
	if u < S1:
		var s := u / S1
		w = A
		p = lerpf(0.32, 0.04, smoothstep(0.0, 1.0, s))        # down on the ball, rolling flat
	elif u < S2:
		var s := (u - S1) / (S2 - S1)
		w = A + H * smoothstep(0.0, 1.0, s)
		lift = 0.075 * sin(PI * s)
		p = 0.45 + 0.12 * sin(PI * s)                          # the hop: toes stay pointed
	elif u < S3:
		var s := (u - S2) / (S3 - S2)
		w = A + H
		p = lerpf(0.3, 0.8, pow(s, 1.5))                       # landed on the ball, peel off
	else:
		var s := (u - S3) / (1.0 - S3)
		w = lerpf(A + H, A + D, _minjerk(s))
		lift = 0.3 * pow(sin(PI * pow(s, 0.75)), 1.2)          # knee driven high
		p = lerpf(0.8, 0.32, smoothstep(0.0, 1.0, s)) + 0.3 * sin(PI * s) * (1.0 - s)
	var z := w - D * u
	return [BWAnimClips.ankle(Vector2(x, z), p, yaw, lift), Vector3(p, yaw, 0)]


static func skip(st: String) -> BWAnimClips.Clip:
	var T := float(SKIP_FRAMES)
	var D := SKIP_STRIDE
	var c := BWAnimClips.new_clip("gg_skip", int(T), true, st)
	c.meta = { "stride": D, "speed": D / (T / FPS), "beta": 0.3, "gait": "skip" }
	for side in ["l", "r"]:
		var off := 0.0 if side == "l" else 0.5
		var x := 0.09 if side == "l" else -0.09
		var yaw := 0.12 if side == "l" else -0.12
		c.proc("foot_%s_pos" % side, func(f: float) -> Vector3:
			return skip_foot(fposmod(f / T - off, 1.0), x, yaw, D)[0])
		c.proc("foot_%s_rot" % side, func(f: float) -> Vector3:
			return skip_foot(fposmod(f / T - off, 1.0), x, yaw, D)[1])
	# body, per half (s = +1: the left foot's skip): step down (low), the hop's
	# peak (high, stretched), the hop's landing (low, squashed), toe-off
	for half in [0, 1]:
		var f: float = half * T * 0.5
		var s: float = 1.0 if half == 0 else -1.0
		c.pose(f + 0.0, { "root": Vector3(0.02 * s, -0.11, 0.03), "squash": -0.03, "hips": Vector3(0.02, -0.1 * s, 0.05 * s),
			"chest": Vector3(0.05, 0.12 * s, -0.03 * s) })
		c.pose(f + 2.0, { "root": Vector3(0.025 * s, -0.02, 0.03), "squash": 0.035, "hips": Vector3(0.0, -0.14 * s, 0.03 * s),
			"chest": Vector3(-0.02, 0.16 * s, -0.02 * s) }, "f")
		c.pose(f + 5.2, { "root": Vector3(0.02 * s, -0.12, 0.03), "squash": -0.045, "hips": Vector3(0.03, -0.08 * s, 0.06 * s),
			"chest": Vector3(0.07, 0.1 * s, -0.03 * s) })
		c.pose(f + 7.6, { "root": Vector3(0.0, -0.05, 0.03), "squash": 0.02, "hips": Vector3(0.0, 0.0, 0.0),
			"chest": Vector3(0.0, 0.0, 0.0) })
		c.pose(f + 1.0, { "head": Vector3(0.06, -0.06 * s, 0.05 * s), "head_sq": 0.04, "neck": Vector3(0.03, 0, 0) })
		c.pose(f + 3.5, { "head": Vector3(-0.12, 0.04 * s, -0.04 * s), "head_sq": -0.03, "neck": Vector3(-0.05, 0, 0) })
		c.pose(f + 6.0, { "head": Vector3(0.05, -0.02 * s, 0.03 * s), "head_sq": 0.035 })
	c.key("spine", 0, Vector3(0.06, 0, 0))
	# arms: the arm opposite the knee swings high (the left knee rises in the
	# right foot's hop, so the right arm leads there), a frame of drag
	var b := c.base
	var wh := _weapon_hand(st)
	var fh := _free_hand(st)
	for hand in [wh, fh]:
		var sx := _sx(hand)
		var free: bool = hand == fh
		var up := Vector3(0.12 * sx, 0.16 if free else -0.02, 0.42 if free else 0.36)
		var back := Vector3(0.24 * sx, -0.32, -0.32 if free else -0.18)
		# hand_l is up while the right knee is up (the left foot's hop, f0-f9)
		var lead_first: bool = hand == "hand_l"
		c.key(hand + "_pos", 3.0, up if lead_first else back, "f")
		c.key(hand + "_pos", 3.0 + T * 0.5, back if lead_first else up, "f")
		c.key(hand + "_pos", 7.5, up.lerp(back, 0.5) + Vector3(0, -0.06, 0))
		c.key(hand + "_pos", 7.5 + T * 0.5, up.lerp(back, 0.5) + Vector3(0, -0.06, 0))
	# the weapon keeps its carry angle (a slingshot / staff / gun swung along)
	var carry := BWAnimCarry.loco(st, "walk")
	for ch in carry.k:
		c.key(ch, 0, carry.k[ch])
	c.key(wh + "_aim", 0, b[wh + "_aim"])
	return c


# ------------------------------------------------------------------ float

## GODLY FLOATING: serene. Upright with the chest open and the chin a
## touch up; both arms out and low, palms open, breathing out and in over
## two seconds; the left knee bent so that foot trails behind the right,
## the toes hanging (the hover layer points them). The weapon rides in its
## hand, held out to the side. Counter-leans the hover's forward lean.
static func godly_float(st: String) -> BWAnimClips.Clip:
	const LIFT := 0.22                     # on top of the hover layer's own ~0.3
	var T := float(FLOAT_FRAMES)
	var c := BWAnimClips.new_clip("gg_float", int(T), true, st)
	c.meta = { "speed": 3.3, "gait": "float", "stride": 3.3 * T / FPS }
	var b := c.base
	# body: a slow breath (chest rises and opens), a lazy sway side to side
	c.pose(0, { "root": Vector3(0.0, LIFT - 0.02, 0.0), "spine": Vector3(-0.12, 0, 0.0), "chest": Vector3(-0.06, 0, 0.0),
		"head": Vector3(-0.08, 0, 0), "neck": Vector3(-0.02, 0, 0), "hips": Vector3(0.0, 0.0, 0.02), "squash": 0.0 }, "f")
	c.pose(T * 0.25, { "root": Vector3(0.012, LIFT, 0.0), "hips": Vector3(0.0, 0.03, 0.0) })
	c.pose(T * 0.5, { "root": Vector3(0.0, LIFT + 0.015, 0.0), "spine": Vector3(-0.15, 0, 0.0), "chest": Vector3(-0.1, 0, 0.0),
		"head": Vector3(-0.12, 0, 0), "hips": Vector3(0.0, 0.0, -0.02), "squash": 0.02 }, "f")
	c.pose(T * 0.75, { "root": Vector3(-0.012, LIFT, 0.0), "hips": Vector3(0.0, -0.03, 0.0) })
	# legs: together, the left knee bent (its foot back and up), toes down
	var fl: Vector3 = b.foot_l_pos
	var fr: Vector3 = b.foot_r_pos
	c.pose(0, { "foot_l_pos": Vector3(0.06, fl.y + LIFT + 0.13, -0.14), "foot_l_rot": Vector3(0.6, 0.08, 0),
		"foot_r_pos": Vector3(-0.05, fr.y + LIFT + 0.02, 0.03), "foot_r_rot": Vector3(0.5, -0.06, 0) }, "f")
	c.pose(T * 0.5, { "foot_l_pos": Vector3(0.06, fl.y + LIFT + 0.15, -0.16), "foot_l_rot": Vector3(0.62, 0.08, 0),
		"foot_r_pos": Vector3(-0.05, fr.y + LIFT + 0.03, 0.02), "foot_r_rot": Vector3(0.52, -0.06, 0) }, "f")
	# arms: out and low, rising a little on the in-breath
	var wh := _weapon_hand(st)
	var fh := _free_hand(st)
	for hand in [wh, fh]:
		var sx := _sx(hand)
		var weap: bool = hand == wh
		var lo := Vector3(0.44 * sx, -0.2 if not weap else -0.2, 0.12)
		var hi := lo + Vector3(0.03 * sx, 0.07, 0.0)
		c.key(hand + "_pos", 0, lo, "f").key(hand + "_pos", T * 0.5 + 2.0, hi, "f")
		c.key(hand + "_pole", 0, Vector3(0.6 * sx, -1.0, -0.3))
		c.key(hand + "_grip", 0, 0.0)              # two-handers let go: one hand on the weapon
	if st == "staff":
		# the staff upright beside him, a slow sway
		c.key(wh + "_aim", 0, Vector3(-0.08, 1.0, 0.12).normalized(), "f")
		c.key(wh + "_aim", T * 0.5 + 3.0, Vector3(-0.02, 1.0, 0.04).normalized(), "f")
	else:
		c.key(wh + "_aim", 0, b[wh + "_aim"])
	return c


# ------------------------------------------------------------- cool walk

## COOL WALK: nonchalant. Leaned back, chin up, long unhurried steps with
## the toes turned out; the shoulders roll over each planted leg (more
## twist, less bounce than B/W's walk). The weapon hand hangs straight
## down, the gun along the leg, barrel to the ground; the free hand swings
## loose and short.
static func cool_walk(st: String) -> BWAnimClips.Clip:
	var T := float(COOL_FRAMES)
	var D := COOL_STRIDE
	var c := BWAnimClips.new_clip("gg_cool_walk", int(T), true, st)
	c.meta = { "stride": D, "speed": D / (T / FPS), "beta": 0.56, "gait": "walk" }
	var g := { "strike": -0.28, "toe": 0.6, "lift": 0.1, "match_v": true }
	for side in ["l", "r"]:
		var off := 0.0 if side == "l" else 0.5
		var x := 0.1 if side == "l" else -0.1
		var yaw := 0.22 if side == "l" else -0.22
		c.proc("foot_%s_pos" % side, func(f: float) -> Vector3:
			return BWAnimClips.gait_foot(fposmod(f / T - off, 1.0), x, yaw, D, 0.56, g)[0])
		c.proc("foot_%s_rot" % side, func(f: float) -> Vector3:
			return BWAnimClips.gait_foot(fposmod(f / T - off, 1.0), x, yaw, D, 0.56, g)[1])
	for half in [0, 1]:
		var f: float = half * T * 0.5
		var s: float = 1.0 if half == 0 else -1.0
		var q := T / 20.0                   # the beats were laid out on a 20 f cycle
		# contact, down (late, slow), passing, up: low bounce, big roll
		c.pose(f + 0.0, { "root": Vector3(0.02 * s, -0.1, 0.0), "hips": Vector3(0.0, -0.17 * s, 0.05 * s),
			"chest": Vector3(-0.02, 0.2 * s, -0.04 * s), "squash": -0.01 })
		c.pose(f + 3.0 * q, { "root": Vector3(0.04 * s, -0.125, 0.0), "hips": Vector3(0.0, -0.1, 0.09 * s) * Vector3(1, s, 1),
			"chest": Vector3(0.0, 0.13 * s, -0.07 * s), "squash": -0.02 }, "f")
		c.pose(f + 5.5 * q, { "root": Vector3(0.03 * s, -0.08, 0.0), "hips": Vector3(0.0, 0.0, 0.06 * s),
			"chest": Vector3(-0.02, 0.0, -0.05 * s), "squash": 0.005 })
		c.pose(f + 8.0 * q, { "root": Vector3(0.01 * s, -0.06, 0.0), "hips": Vector3(0.0, 0.1 * s, 0.0),
			"chest": Vector3(-0.03, -0.1 * s, 0.0), "squash": 0.012 }, "f")
		c.pose(f + 4.0 * q, { "head": Vector3(-0.1, -0.1 * s, 0.05 * s), "head_sq": 0.02, "neck": Vector3(-0.02, 0, 0) })
		c.pose(f + 9.0 * q, { "head": Vector3(-0.14, 0.04 * s, -0.02 * s), "head_sq": -0.01, "neck": Vector3(-0.05, 0, 0) })
	c.key("spine", 0, Vector3(-0.17, 0, 0))
	var b := c.base
	var wh := _weapon_hand(st)
	var fh := _free_hand(st)
	if st == "pistol":
		# the gun hangs at arm's length along the right leg, barrel down; it
		# drifts a hand's width with the stride, a frame behind the hips
		var aim := Vector3(0.0, -0.2, 0.98).normalized()        # the gun's top faces forward
		var edge := Vector3(0.0, -0.98, -0.2).normalized()      # the barrel points at the ground
		c.key("hand_r_pos", 1.0, Vector3(-0.27, -0.5, 0.06), "f").key("hand_r_pos", 1.0 + T * 0.5, Vector3(-0.27, -0.49, -0.06), "f")
		c.key("hand_r_aim", 0, aim).key("hand_r_edge", 0, edge)
		c.key("hand_r_pole", 0, Vector3(-0.6, -0.2, -1.0))
		c.key("flat", 0, 0.0)
	else:
		var sxw := _sx(wh)
		c.key(wh + "_pos", 1.0, Vector3(0.26 * sxw, -0.4, 0.06), "f").key(wh + "_pos", 1.0 + T * 0.5, Vector3(0.26 * sxw, -0.39, -0.06), "f")
		c.key(wh + "_aim", 0, b[wh + "_aim"])
	var sx := _sx(fh)
	c.key(fh + "_pos", 2.0, Vector3(0.25 * sx, -0.42, -0.1), "f").key(fh + "_pos", 2.0 + T * 0.5, Vector3(0.22 * sx, -0.4, 0.12), "f")
	c.key(fh + "_pole", 0, Vector3(0.5 * sx, -0.1, -1.0))
	c.key(fh + "_grip", 0, 0.0)
	return c


# ------------------------------------------------------------------ casts

## A cast gesture: base at f0, coil f3, release f6 (linear in, the snap),
## held to f9, back at the guard by f14. Hands in the root frame (like
## B/W's cast). kind: thrust (the staff head / an open palm drives at the
## target), slam (raised overhead, brought down at the ground ahead), flick
## (a quick point), shoot / blast (the weapon arm levelled, a recoil; blast
## kicks harder and rocks a step back), toss (an underhand lob), rally (a
## crouch and a spring, the free fist pumped).
static func cast(st: String, kind: String) -> BWAnimClips.Clip:
	var N := float(CAST_FRAMES)
	var c := BWAnimClips.new_clip("gg_cast_" + kind, int(N), false, st)
	c.marker("coil", 3).marker("release", 6).marker("hit", 6).marker("recovered", 12).marker("pose", 6)
	c.meta = { "hand_frame": "root", "kind": "cast" }
	var b := c.base
	var body := ["root", "hips", "spine", "chest", "neck", "head", "squash", "head_sq"]
	var hands: Array = []
	for ch in BWAnimClips.CHANNELS:
		if str(ch).begins_with("hand_") or ch in ["flat", "arm_stretch", "smear"]:
			hands.append(ch)
	c.at_base(0, body + hands)
	c.at_base(N, body + hands)
	var wh := _weapon_hand(st)
	var fh := _free_hand(st)
	var sf := _sx(fh)
	var wb: Vector3 = b[wh + "_pos"]
	var sw := _sx(wh)
	# the caster: the staff for staves, the gun / bow for shots, else the free hand
	var who := fh
	if st == "staff" and kind in ["thrust", "slam", "flick"]:
		who = wh
	if kind in ["shoot", "blast"]:
		who = wh
	var sx := _sx(who)
	var other := fh if who == wh else wh
	var held := func(f: float, d: Dictionary, mode: String = "a") -> void:
		c.pose(f, d, mode)
	match kind:
		"thrust", "flick":
			var k := 1.0 if kind == "thrust" else 0.75
			held.call(3, { "root": Vector3(0, -0.1 * k, -0.03 * k), "hips": Vector3(0, -0.18 * k * -sx, 0),
				"chest": Vector3(-0.08 * k, -0.24 * k * -sx, 0.02), "head": Vector3(0.04, 0.2 * -sx * k, 0), "squash": -0.025 * k }, "f")
			held.call(6, { "root": Vector3(0, -0.06, 0.06 * k), "hips": Vector3(0.04, 0.12 * k * -sx, 0), "chest": Vector3(0.12 * k, 0.18 * k * -sx, -0.02),
				"spine": Vector3(0.03 + 0.06 * k, 0, 0), "head": Vector3(-0.04, -0.1 * k * -sx, 0), "squash": 0.04 * k, "head_sq": -0.03 }, "l")
			held.call(9, { "root": Vector3(0, -0.07, 0.06 * k), "chest": Vector3(0.1 * k, 0.16 * k * -sx, -0.02), "squash": 0.0, "head_sq": 0.0 }, "f")
			if who == wh and st == "staff":
				if kind == "thrust":
					c.key("hand_r_pos", 3, Vector3(-0.32, 0.42, -0.06), "f").key("hand_r_aim", 3, Vector3(-0.3, 0.75, -0.6).normalized(), "f")
					c.key("hand_r_pos", 6, Vector3(-0.1, 0.32, 0.44), "l").key("hand_r_aim", 6, Vector3(0.0, 0.55, 0.83).normalized(), "l")
					c.key("hand_r_pos", 9, Vector3(-0.1, 0.3, 0.45), "f").key("hand_r_aim", 9, Vector3(0.0, 0.52, 0.85).normalized(), "f")
				else:
					c.key("hand_r_pos", 3, Vector3(-0.3, 0.16, 0.0), "f").key("hand_r_aim", 3, Vector3(-0.15, 0.9, -0.35).normalized(), "f")
					c.key("hand_r_pos", 6, Vector3(-0.16, 0.24, 0.4), "l").key("hand_r_aim", 6, Vector3(0.0, 0.3, 0.95).normalized(), "l")
					c.key("hand_r_pos", 9, Vector3(-0.16, 0.22, 0.4), "f").key("hand_r_aim", 9, Vector3(0.0, 0.32, 0.94).normalized(), "f")
				c.key("hand_r_edge", 3, Vector3(0, 0, 1)).key("hand_r_edge", 10, Vector3(0, 0, 1))
				# the free hand opens and pushes after the staff
				c.key("hand_l_pos", 3, Vector3(0.26, 0.28, 0.16), "f").key("hand_l_pos", 6, Vector3(0.16, 0.2, 0.5 * k + 0.1), "l")
				c.key("hand_l_pos", 9, Vector3(0.16, 0.18, 0.5 * k + 0.1), "f")
				c.key("flat", 3, 0.3).key("flat", 10, 0.3)
			else:
				c.key(who + "_pos", 3, Vector3(0.04 * sx, 0.1, 0.14), "f")
				c.key(who + "_pos", 6, Vector3(0.08 * sx, 0.22, 0.32 + 0.28 * k), "l")
				c.key(who + "_pos", 9, Vector3(0.08 * sx, 0.22, 0.3 + 0.28 * k), "f")
				c.key(who + "_pole", 3, Vector3(0.8 * sx, -1, -0.2)).key(who + "_pole", 10, Vector3(0.8 * sx, -1, -0.2))
				_draw_back(c, wh, wb, sw)
			c.key("arm_stretch", 5, 0.0).key("arm_stretch", 6, 0.07 * k).key("arm_stretch", 9, 0.02).key("arm_stretch", 11, 0.0)
		"slam":
			held.call(3, { "root": Vector3(0, -0.0, -0.03), "spine": Vector3(-0.1, 0, 0), "chest": Vector3(-0.14, 0.06 * sx, 0),
				"head": Vector3(-0.16, 0, 0), "squash": 0.03, "head_sq": -0.02 }, "f")
			held.call(6, { "root": Vector3(0, -0.16, 0.05), "spine": Vector3(0.22, 0, 0), "chest": Vector3(0.14, 0, 0),
				"head": Vector3(-0.1, 0, 0), "squash": -0.05, "head_sq": 0.04 }, "l")
			held.call(9, { "root": Vector3(0, -0.14, 0.05), "spine": Vector3(0.2, 0, 0), "chest": Vector3(0.12, 0, 0), "squash": -0.02, "head_sq": 0.0 }, "f")
			if who == wh and st == "staff":
				c.key("hand_r_pos", 3, Vector3(-0.16, 0.66, 0.02), "f").key("hand_r_aim", 3, Vector3(-0.1, 0.75, -0.65).normalized(), "f")
				c.key("hand_r_pos", 6, Vector3(-0.12, 0.08, 0.44), "l").key("hand_r_aim", 6, Vector3(0.0, -0.4, 0.92).normalized(), "l")
				c.key("hand_r_pos", 9, Vector3(-0.12, 0.06, 0.44), "f").key("hand_r_aim", 9, Vector3(0.0, -0.42, 0.9).normalized(), "f")
				c.key("hand_r_edge", 3, Vector3(0, 0, 1)).key("hand_r_edge", 10, Vector3(0, 0, 1))
				c.key("hand_l_pos", 3, Vector3(0.12, 0.6, 0.04), "f").key("hand_l_pos", 6, Vector3(0.1, 0.06, 0.42), "l")
				c.key("hand_l_pos", 9, Vector3(0.1, 0.05, 0.42), "f")
				c.key("flat", 3, 0.2).key("flat", 10, 0.2)
			else:
				c.key(who + "_pos", 3, Vector3(0.16 * sx, 0.6, 0.04), "f")
				c.key(who + "_pos", 6, Vector3(0.1 * sx, 0.0, 0.5), "l")
				c.key(who + "_pos", 9, Vector3(0.1 * sx, -0.02, 0.5), "f")
				c.key(who + "_pole", 3, Vector3(0.8 * sx, -1, -0.2)).key(who + "_pole", 10, Vector3(0.8 * sx, -1, -0.2))
				_draw_back(c, wh, wb, sw)
			c.key("arm_stretch", 5, 0.0).key("arm_stretch", 6, 0.06).key("arm_stretch", 10, 0.0)
		"shoot", "blast":
			var k := 1.0 if kind == "shoot" else 1.7
			var ty := -0.2 * -sx                     # turn the shooting shoulder in
			held.call(3, { "root": Vector3(0, -0.06, 0.0), "hips": Vector3(0, ty, 0), "chest": Vector3(0.02, ty * 0.6, 0),
				"head": Vector3(0.02, -ty * 1.4, 0) }, "f")
			held.call(6, { "root": Vector3(0, -0.07, -0.04 * k), "chest": Vector3(-0.1 * k, ty * 0.5, 0.03), "head": Vector3(-0.1 * k, -ty * 1.5, 0.03),
				"squash": 0.02 * k, "head_sq": -0.04 }, "l")
			held.call(7.5, { "root": Vector3(0, -0.08, -0.05 * k), "chest": Vector3(-0.12 * k, ty * 0.5, 0.03), "squash": -0.025 * k, "head_sq": 0.04 })
			held.call(10, { "root": Vector3(0, -0.06, -0.02), "chest": Vector3(0.0, ty * 0.6, 0.0), "head": Vector3(0.02, -ty * 1.4, 0), "squash": 0.0, "head_sq": 0.0 }, "f")
			if st == "bow":
				# the slingshot arm out at the target, the band drawn to the chin, let go
				c.key("hand_l_pos", 3, Vector3(0.06, 0.24, 0.58), "f").key("hand_l_aim", 3, Vector3(0.0, 1.0, 0.1).normalized(), "f")
				c.key("hand_l_pos", 6, Vector3(0.06, 0.26 + 0.04 * k, 0.54), "l").key("hand_l_pos", 10, Vector3(0.06, 0.24, 0.58), "f")
				c.key("hand_l_edge", 3, Vector3(0, 0, 1)).key("hand_l_edge", 10, Vector3(0, 0, 1))
				c.key("hand_r_pos", 3, Vector3(-0.04, 0.24, 0.3)).key("hand_r_pos", 5, Vector3(-0.06, 0.26, 0.1), "f")
				c.key("hand_r_pos", 6, Vector3(-0.14, 0.3, -0.02), "l").key("hand_r_pos", 9, Vector3(-0.16, 0.26, -0.02), "f")
			else:
				# the gun levelled (the pistol strike's aim), then the kick
				var gun_aim := Vector3(0, 1, 0)
				var gun_edge := Vector3(0, 0, 1)
				var kick := 0.6 * k
				c.key(who + "_pos", 3, Vector3(-0.08 * -sx, 0.24, 0.64), "f").key(who + "_aim", 3, gun_aim, "f").key(who + "_edge", 3, gun_edge, "f")
				c.key(who + "_pos", 5, Vector3(-0.08 * -sx, 0.24, 0.66), "f").key(who + "_aim", 5, gun_aim, "f").key(who + "_edge", 5, gun_edge, "f")
				c.key(who + "_pos", 6, Vector3(-0.08 * -sx, 0.24 + 0.08 * k, 0.66 - 0.06 * k), "l")
				c.key(who + "_aim", 6, Vector3(0, 1.0, -kick).normalized(), "l").key(who + "_edge", 6, Vector3(0, kick, 1.0).normalized(), "l")
				c.key(who + "_pos", 7.5, Vector3(-0.08 * -sx, 0.26 + 0.08 * k, 0.6 - 0.04 * k))
				c.key(who + "_aim", 7.5, Vector3(0, 1.0, -kick * 0.9).normalized()).key(who + "_edge", 7.5, Vector3(0, kick * 0.9, 1.0).normalized())
				c.key(who + "_pos", 10, Vector3(-0.08 * -sx, 0.24, 0.62), "f").key(who + "_aim", 10, gun_aim, "f").key(who + "_edge", 10, gun_edge, "f")
				c.key(who + "_pole", 3, Vector3(-1, -0.6, -0.2)).key(who + "_pole", 11, Vector3(-1, -0.6, -0.2))
				# the other hand cups the grip
				c.key(other + "_pos", 3, Vector3(-0.03 * -sx, 0.17, 0.58), "f").key(other + "_pos", 5, Vector3(-0.03 * -sx, 0.17, 0.6), "f")
				c.key(other + "_pos", 7, Vector3(-0.03 * -sx, 0.24, 0.54)).key(other + "_pos", 10, Vector3(-0.03 * -sx, 0.17, 0.58), "f")
				c.key(other + "_pole", 3, Vector3(1, -0.6, -0.2)).key(other + "_pole", 11, Vector3(1, -0.6, -0.2))
				c.key("flat", 3, 0.15).key("flat", 11, 0.15)
				if kind == "blast":
					# rocked back on the heels by the big shell
					c.key("hips", 7, Vector3(-0.05, ty, 0)).key("spine", 7, Vector3(-0.1, 0, 0)).key("spine", 11, Vector3(0.03, 0, 0))
		"toss":
			held.call(3, { "root": Vector3(0, -0.13, -0.02), "spine": Vector3(0.2, 0, 0), "hips": Vector3(0, 0.12 * -sx, 0),
				"chest": Vector3(0.06, 0.22 * -sx, 0.0), "head": Vector3(-0.12, -0.15 * -sx, 0), "squash": -0.04 }, "f")
			held.call(6, { "root": Vector3(0, -0.05, 0.05), "spine": Vector3(0.04, 0, 0), "hips": Vector3(0, -0.1 * -sx, 0),
				"chest": Vector3(0.02, -0.16 * -sx, 0.0), "head": Vector3(-0.08, 0.08 * -sx, 0), "squash": 0.035 }, "l")
			held.call(9, { "root": Vector3(0, -0.05, 0.04), "spine": Vector3(0.05, 0, 0), "chest": Vector3(0.02, -0.12 * -sx, 0.0), "squash": 0.0 }, "f")
			c.key(who + "_pos", 3, Vector3(0.22 * sx, -0.36, -0.26), "f")
			c.key(who + "_pos", 6, Vector3(0.1 * sx, 0.08, 0.46), "l")
			c.key(who + "_pos", 9, Vector3(0.1 * sx, 0.12, 0.44), "f")
			c.key(who + "_pole", 3, Vector3(0.8 * sx, -1, 0.2)).key(who + "_pole", 10, Vector3(0.8 * sx, -1, -0.2))
			_draw_back(c, wh, wb, sw)
		"rally":
			held.call(3, { "root": Vector3(0, -0.17, -0.02), "spine": Vector3(0.24, 0, 0), "chest": Vector3(0.1, 0, 0),
				"head": Vector3(-0.14, 0, 0), "squash": -0.06, "head_sq": 0.04 }, "f")
			held.call(6, { "root": Vector3(0, 0.0, 0.03), "spine": Vector3(-0.06, 0, 0), "chest": Vector3(-0.08, 0, 0),
				"head": Vector3(-0.12, 0, 0), "squash": 0.06, "head_sq": -0.04 }, "l")
			held.call(9, { "root": Vector3(0, -0.03, 0.02), "spine": Vector3(-0.02, 0, 0), "chest": Vector3(-0.04, 0, 0), "squash": 0.0, "head_sq": 0.0 }, "f")
			c.key(fh + "_pos", 3, Vector3(0.16 * sf, -0.06, 0.24), "f")
			c.key(fh + "_pos", 6, Vector3(0.2 * sf, 0.56, 0.14), "l")
			c.key(fh + "_pos", 9, Vector3(0.2 * sf, 0.52, 0.12), "f")
			c.key(fh + "_pole", 3, Vector3(0.8 * sf, -1, -0.2)).key(fh + "_pole", 10, Vector3(0.8 * sf, -1, -0.2))
			c.key(fh + "_grip", 2, 0.0)
			c.key(wh + "_pos", 3, wb + Vector3(-0.04 * sw, 0.06, 0.04), "f")
			c.key(wh + "_pos", 6, wb + Vector3(0.04 * sw, 0.1, -0.04), "l")
			c.key(wh + "_pos", 9, wb + Vector3(0.04 * sw, 0.08, -0.04), "f")
	return c


## The weapon hand draws back and out of the way while the other hand casts.
static func _draw_back(c: BWAnimClips.Clip, wh: String, wb: Vector3, sw: float) -> void:
	var b := c.base
	c.key(wh + "_pos", 3, wb + Vector3(0.05 * sw, 0.06, -0.12), "f")
	c.key(wh + "_pos", 6, wb + Vector3(0.08 * sw, 0.05, -0.22), "l")
	c.key(wh + "_pos", 9, wb + Vector3(0.08 * sw, 0.04, -0.2), "f")
	c.key(wh + "_aim", 3, (Basis.from_euler(Vector3(0.25, 0, 0)) * (b[wh + "_aim"] as Vector3)).normalized(), "f")
	c.key(wh + "_aim", 9, (Basis.from_euler(Vector3(0.3, 0, 0)) * (b[wh + "_aim"] as Vector3)).normalized(), "f")
