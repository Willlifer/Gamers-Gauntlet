class_name TourneyMusic
extends Node
## The Gamer's music (G25): the author's three Chris loops everywhere in the
## tournament, one shared player that crossfades between them and carries on
## across screens (asking for the track already playing changes nothing).
## Black | White's own music stays for Black | White's game; its stings
## (BWMusic.sting) still play over this.
##
##   TourneyMusic.ensure(node)
##   TourneyMusic.play("lobby")          lobby, range, bracket, results
##   TourneyMusic.play("hype")           matchup and bets, loading into a game, the champion
##   TourneyMusic.play("fight")          every game while it plays
##   TourneyMusic.play("boss")           boss fights, the raid's last 30%
##   TourneyMusic.play("")               silence (a sting has the floor)
## Tracks: res://audio/music/chris/ (tools/audio/trim_chris.py, G24).

const DIR := "res://audio/music/chris/"
const CUES := { "lobby": "chris_loop_a", "hype": "chris_loop_b", "fight": "chris_full", "boss": "chris_loop_b" }
const FADE := 1.4

static var _inst: TourneyMusic

var _decks: Array[AudioStreamPlayer] = []
var _cur := -1
var _track := ""


static func ensure(parent: Node) -> TourneyMusic:
	if _inst != null and is_instance_valid(_inst):
		return _inst
	BWAudio.ensure(parent)
	_inst = TourneyMusic.new()
	_inst.name = "TourneyMusic"
	_inst.process_mode = Node.PROCESS_MODE_ALWAYS
	var tree := parent.get_tree() if parent.is_inside_tree() else Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		tree.root.add_child.call_deferred(_inst)
	else:
		parent.add_child.call_deferred(_inst)
	return _inst


func _init() -> void:
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		p.volume_db = -60.0
		add_child(p)
		_decks.append(p)


## Play a cue ("lobby", "hype", "fight", "boss") or a track name; "" fades out.
static func play(cue: String) -> void:
	if _inst == null or not is_instance_valid(_inst):
		var tree := Engine.get_main_loop() as SceneTree
		if tree == null or tree.root == null:
			return
		ensure(tree.root)
	_inst._play(str(CUES.get(cue, cue)))
	_quiet_bw()


static func current() -> String:
	return _inst._track if _inst and is_instance_valid(_inst) else ""


static func stream(track: String) -> AudioStream:
	return load(DIR + track + ".wav") as AudioStream


## Black | White's layered music keeps quiet while this plays.
static func _quiet_bw() -> void:
	var bw := BWMusic.instance()
	if bw == null:
		return
	for c in bw.find_children("*", "AudioStreamPlayer", true, false):
		var p := c as AudioStreamPlayer
		if p.playing:
			p.stop()


func _play(track: String) -> void:
	if not is_inside_tree():
		_play.call_deferred(track)                 # just created: it joins the tree at the end of the frame
		return
	if track == _track:
		return
	_track = track
	var old := _decks[_cur] if _cur >= 0 else null
	_cur = (_cur + 1) % 2
	var p := _decks[_cur]
	if track != "":
		var s := stream(track)
		if s:
			p.stream = s
			p.volume_db = -40.0
			p.play()
			create_tween().tween_property(p, "volume_db", 0.0, FADE)
	if old and old.playing:
		var tw := create_tween()
		tw.tween_property(old, "volume_db", -60.0, FADE)
		tw.tween_callback(old.stop)
