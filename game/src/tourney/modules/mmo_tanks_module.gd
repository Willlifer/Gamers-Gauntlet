class_name MmoTanksModule
extends MmoModule
## Planet of Tanks (G46), raid night 2: the same raid of eight and the same
## classes as Raid night, against the kit tank in a clearing of the forest
## campus (MmoTankFight, MmoTankArena). Graded the same way (MmoGrade).

const LOGO := "res://art/ui/planet_of_tanks_logo_small.png"


static func info() -> Dictionary:
	return { "id": "mmo_tanks", "name": "Planet of Tanks", "players": 2,
		"blurb": "Raid night 2: the raid against a tank in the campus woods. Drag its gun off the raid; the better grade wins." }


static func simulate(m: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	return run(m, rng, "tank")


func encounter() -> String:
	return "tank"


func _dress_pick(root: Control) -> void:
	if not ResourceLoader.exists(LOGO):
		return
	var t := TextureRect.new()
	t.texture = load(LOGO)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.position = Vector2(20, 4)
	t.size = Vector2(220, 90)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(t)
