class_name BWBarks
## Picks a bark line per design/BARKS.md: match event (+ action), speaker
## friendliness, trust stage, and the other party's friendliness; pair-
## specific lines weigh 3× over `any`. Trust leans the pick, it doesn't lock
## it (author, 2026-10-12): every stage with lines can play, weighted by its
## distance from the pair's stage (STAGE_WEIGHT). Deterministic given the rng.

const PAIR_WEIGHT := 3
const STAGES := ["strangers", "acquainted", "trusted"]
## Weight by distance from the pair's stage: strangers hear 60% stranger
## lines, 30% acquainted, 10% trusted; acquainted hears 25 / 50 / 25.
const STAGE_WEIGHT := [6, 3, 1]


static func _pool(event: String, speaker: String, stage: String, toward: String, action: String) -> Array:
	var pool: Array = []
	for b in BWData.table("barks"):
		if b.event != event or b.speaker_friendliness != speaker or b.trust != stage:
			continue
		if action != "" and str(b.action) != action:
			continue
		if b.toward_friendliness == toward and toward != "any":
			for i in PAIR_WEIGHT:
				pool.append(b)
		elif b.toward_friendliness == "any":
			pool.append(b)
	return pool


static func pick(event: String, speaker: String, trust: String, toward: String = "any",
		action: String = "", rng: RandomNumberGenerator = null) -> Dictionary:
	var at := STAGES.find(trust) if trust in STAGES else 1
	var pools: Array = []          # [pool, weight] per stage that has lines
	var total := 0
	for i in STAGES.size():
		var pool := _pool(event, speaker, STAGES[i], toward, action)
		if not pool.is_empty():
			var w: int = STAGE_WEIGHT[absi(i - at)]
			pools.append([pool, w])
			total += w
	if total == 0:
		return {}
	var roll := rng.randi() % total if rng else randi() % total
	for pw in pools:
		roll -= int(pw[1])
		if roll < 0:
			var pool: Array = pw[0]
			return pool[rng.randi() % pool.size() if rng else randi() % pool.size()]
	return {}


## "{speaker}" etc. filled in from a context dictionary.
static func fill(line: String, ctx: Dictionary) -> String:
	var out := line
	for k in ctx:
		out = out.replace("{%s}" % k, str(ctx[k]))
	return out


static func clip_path(clip: String) -> String:
	return "res://audio/barks/%s.wav" % clip.to_lower().replace(" ", "_")
