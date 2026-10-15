extends Node
## The tournament's entry point and flow: lobby → bracket (rolls) → for each
## match: vote → matchup and bets → the game → result → bracket … → champion.
## Args after `--`: --bots n (seat n bots at once), --autostart (ready and go).

var state: TourneyState
var screen: Node
## Tools: roll every game's result instead of playing it.
static var simulate_all := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	BWSettings.init(true)
	BWMusic.ensure(self)
	TourneyMusic.ensure(self)
	BWEsc.ensure(self)
	BWSettings.apply_all()
	BWShaderWarm.start(self)
	for n in [BWMusic._inst, BWSfx._inst]:
		if n and is_instance_valid(n):
			n.process_mode = Node.PROCESS_MODE_ALWAYS
	state = TourneyState.new()
	state.add_local(TourneyState.load_profile())
	var bots := int(_arg(args, "--bots", "3"))
	for i in bots:
		state.add_bot()
	if "--autostart" in args:
		state.me().ready = true
	go_lobby("--autostart" in args)


func _arg(args: PackedStringArray, flag: String, fallback: String) -> String:
	var i := args.find(flag)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else fallback


func _swap(next: Node) -> void:
	if screen and is_instance_valid(screen):
		screen.queue_free()
	screen = next
	add_child(next)


# ------------------------------------------------------------------ flow

func go_lobby(autostart: bool = false) -> void:
	var s := LobbyScreen.new()
	s.state = state
	s.start.connect(start_tournament)
	s.open_range.connect(go_range)
	_swap(s)
	TourneyMusic.play("lobby")
	if autostart:
		start_tournament.call_deferred()


func go_range(kind: String) -> void:
	var s := RangeScreen.new()
	s.kind = kind
	s.back.connect(func(): go_lobby())
	_swap(s)
	TourneyMusic.play("lobby")


func start_tournament() -> void:
	state.bracket = TourneyBracket.new()
	state.bracket.build(state.players.map(func(p): return str(p.id)), state.rng)
	state.bets = {}
	state.log = []
	for p in state.players:
		p.wins = 0
		p.losses = 0
		p.coins = 0
	go_bracket(true)


func go_bracket(first: bool) -> void:
	state.hand_out_coins()
	var s := BracketScreen.new()
	s.state = state
	s.first_open = first
	s.chosen.connect(go_matchup)
	s.finished.connect(go_champion)
	_swap(s)
	TourneyMusic.play("lobby")


func go_matchup(match_id: String) -> void:
	var s := MatchupScreen.new()
	s.state = state
	s.match_id = match_id
	s.start.connect(func(): go_game(match_id))
	_swap(s)
	TourneyMusic.play("hype")


func go_game(match_id: String) -> void:
	var m := state.bracket.get_match(match_id)
	var cfg := { "id": match_id, "seed": int(state.rng.randi()), "players": [state.player(m.p1), state.player(m.p2)],
		"binds": TourneyState.load_binds(), "sens": TourneyState.load_sens() }
	var script := TourneyModules.script_for(m.game)
	var humans: bool = cfg.players.any(func(p): return not p.bot)
	if not humans or simulate_all:
		var r: Dictionary = script.simulate(cfg, state.rng)
		_record(match_id, r)
		return
	var mod: TourneyModule = script.new()
	mod.finished.connect(func(r): _record(match_id, r))
	_swap(mod)
	TourneyMusic.play("hype")                       # loading in and picking: the game cues "fight" when it starts
	mod.setup(cfg)


func _record(match_id: String, r: Dictionary) -> void:
	var m := state.bracket.get_match(match_id)
	state.bracket.report(match_id, str(r.winner))
	state.player(m.winner).wins += 1
	state.player(m.loser).losses += 1
	var pay := state.settle(match_id, m.winner)
	state.log.append({ "match": match_id, "game": m.game, "winner": m.winner, "loser": m.loser, "comments": [] })
	var s := ResultScreen.new()
	s.state = state
	s.match_id = match_id
	s.result = r
	s.payouts = pay
	s.done.connect(func(): go_bracket(false))
	_swap(s)
	TourneyMusic.play("lobby")
	BWMusic.sting("level_up")


func go_champion() -> void:
	var s := ChampionScreen.new()
	s.state = state
	s.done.connect(func():
		for p in state.players:
			p.ready = p.bot
		go_lobby())
	_swap(s)
