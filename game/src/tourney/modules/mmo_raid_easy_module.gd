class_name MmoRaidEasyModule
extends MmoModule
## MMO: Raid night (Easy) (G59): the same raid of eight on the Giant with the
## same classes, action bar, consumables bar, keys and HUD as Raid night (Hard,
## MmoModule), but the Giant fights by its rules as pushed before G52
## (1f1a933): the floor first turns at 90 s and rests 30 s between bursts, with
## 10 s / 2 s of flashing chevrons; Earthshatter and the bombs never come back
## to back; Cinderbrand smoulders without the flames. MmoSim.easy, MmoSim.EASY.


static func info() -> Dictionary:
	return { "id": "mmo_raid_easy", "name": "MMO: Raid night (Easy)", "players": 2,
		"blurb": "WoW Classic raid on the Giant, easy mode: the slower fire, one mechanic at a time. Pick a class; the better grade wins." }


static func simulate(m: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	return run(m, rng, "giant_easy")


func encounter() -> String:
	return "giant_easy"


## Says which Giant this is on the class pick.
func _dress_pick(root: Control) -> void:
	var l := TourneyUI.big(root, "Raid night: Easy", 26, Color("#9fd6a0"))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.position = Vector2(24, 16)
