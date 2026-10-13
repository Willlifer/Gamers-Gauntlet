class_name TourneyModule
extends Node
## One game inside the tournament. The shell hands it the match and waits
## for `finished`; the module never touches the lobby, bracket or network.
##
##   setup(match): { id, seed, players: [{ id, name, bot, ... }, ...], binds, sens }
##   finished(result): { winner: player id, summary: String, stats: {} }
##
## A module that a bot "plays" without a human (both sides bots) must still
## resolve: see simulate(), which the shell calls instead of showing it.

signal finished(result: Dictionary)

var match_cfg := {}


## Static description, for the roll and the bracket card.
static func info() -> Dictionary:
	return { "id": "base", "name": "Base", "players": 2, "blurb": "" }


func setup(m: Dictionary) -> void:
	match_cfg = m


## A result with no human involved: the shell rolls it from this.
static func simulate(m: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var p: Array = m.players
	var w: Dictionary = p[rng.randi() % p.size()]
	return { "winner": w.id, "summary": "%s took it." % w.name, "stats": {} }
