class_name MmoGrade
extends RefCounted
## Raid night's verdict (G33, the author: "track damage dealt, aoes avoided,
## mechanics performed… add some weights and a grading scale. Whoever gets
## the higher grade wins"). Five parts, each 0..1, weighted into a 0-100
## score, then a letter:
##   output     damage + healing per second against a bot of your class
##              (MmoClasses.PAR), full marks at out_full x a bot's pace
##   mechanics  bombs spread, in the ring, Cinderbrand shed (run off or
##              cleansed), plus cleanse_credit per boss debuff you took off
##              someone else; done / faced
##   avoidance  Upheaval lines and meteors that landed near you and missed
##   survival   time alive / fight time
##   activity   time on the GCD, casting or auto-attacking / time alive
## Weights and the letter cut-offs are on F1 (MmoTune, Verdict). The higher
## letter wins; the same letter goes to the higher score.

const LETTERS := ["S", "A", "B", "C", "D", "F"]
const PARTS := ["output", "mechanics", "avoidance", "survival", "activity"]
const NAMES := { "output": "Output", "mechanics": "Mechanics", "avoidance": "AoEs avoided",
	"survival": "Survival", "activity": "Activity" }
const WEIGHT_KEY := { "output": "w_output", "mechanics": "w_mech", "avoidance": "w_dodge",
	"survival": "w_alive", "activity": "w_busy" }


## { score 0-100, letter, rank (0 = S), parts: { part: 0..1 }, points: { part: points }, facts: { … } }
static func grade(s: MmoSim, u: MmoUnit) -> Dictionary:
	var secs := maxf(10.0, u.fight_t)
	var out_ratio := ((u.dmg_done + u.heal_done) / secs) / float(MmoClasses.PAR.get(u.cls, 300.0))
	var brand_shed := 0.0
	if u.brand_full > 0.0:
		var brands := roundf(u.brand_full / maxf(1.0, u.max_hp * MmoTune.value("brand_pct")))
		brand_shed = clampf(1.0 - u.brand_taken / u.brand_full, 0.0, 1.0) * brands
	var mech_own := u.mech_done + brand_shed
	var mech_done := mech_own + u.cleanses * MmoTune.value("cleanse_credit")
	var parts := {
		"output": clampf(out_ratio / MmoTune.value("out_full"), 0.0, 1.0),
		"mechanics": clampf(mech_done / u.mech_faced, 0.0, 1.0) if u.mech_faced > 0.0 else 1.0,
		"avoidance": 1.0 - float(u.dodge_hit) / float(u.dodge_faced) if u.dodge_faced > 0 else 1.0,
		"survival": clampf(u.alive_t / secs, 0.0, 1.0),
		"activity": clampf(u.busy_t / maxf(1.0, u.alive_t), 0.0, 1.0),
	}
	var total_w := 0.0
	for p in PARTS:
		total_w += MmoTune.value(WEIGHT_KEY[p])
	var points := {}
	var score := 0.0
	for p in PARTS:
		var pts := 100.0 * float(parts[p]) * MmoTune.value(WEIGHT_KEY[p]) / maxf(1.0, total_w)
		points[p] = pts
		score += pts
	var letter := letter_for(score)
	return { "score": score, "letter": letter, "rank": LETTERS.find(letter), "parts": parts, "points": points,
		"facts": { "output_pct": int(round(out_ratio * 100.0)), "mech": "%.1f / %d" % [minf(mech_own, u.mech_faced), int(u.mech_faced)],
			"dodge": "%d / %d" % [u.dodge_faced - u.dodge_hit, u.dodge_faced], "deaths": u.deaths, "cleanses": u.cleanses } }


static func letter_for(score: float) -> String:
	for k in [["S", "grade_s"], ["A", "grade_a"], ["B", "grade_b"], ["C", "grade_c"], ["D", "grade_d"]]:
		if score >= MmoTune.value(k[1]):
			return k[0]
	return "F"


## True when grade `a` beats grade `b`: the higher letter, then the higher score.
static func beats(a: Dictionary, b: Dictionary) -> bool:
	if int(a.rank) != int(b.rank):
		return int(a.rank) < int(b.rank)
	return float(a.score) >= float(b.score)


static func colour(letter: String) -> Color:
	return { "S": Color("#ffcf40"), "A": Color("#7fd46a"), "B": Color("#5aa8e6"), "C": Color("#c8c8c8"),
		"D": Color("#d98a4a"), "F": Color("#d8473b") }.get(letter, Color.WHITE)
