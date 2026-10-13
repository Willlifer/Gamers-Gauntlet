class_name ResultScreen
extends Node
## After a match: who won, what the pot paid, a line of comment from each
## player (yours typed, the bots' canned), then on with the bracket.

signal done

const BOT_LINES := ["gg", "that was robbery", "called it", "unlucky", "ez", "next one's mine", "I'm down 15 coins. Cool.", "rematch", "W", "who bet on that"]

var state: TourneyState
var match_id := ""
var result := {}
var payouts := {}
var _root: Control
var _comments: VBoxContainer
var _entry: LineEdit


func _ready() -> void:
	var m := state.bracket.get_match(match_id)
	_root = TourneyUI.root(self)
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.09, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)
	_root.move_child(bg, 0)
	var w := state.player(m.winner)
	var l := state.player(m.loser)
	var v := TourneyUI.panel(_root, Rect2(300, 60, 1000, 780), TourneyBracket.label(m))
	TourneyUI.big(v, "%s beat %s" % [w.name, l.name], 44, TourneyUI.GOLD)
	TourneyUI.para(v, str(result.get("summary", "")), BWStyle.F_BODY, Color.WHITE)
	if payouts.is_empty():
		TourneyUI.label(v, "Nobody backed the winner. The pot goes back to the house.", BWStyle.F_BODY, TourneyUI.DIM)
	else:
		var lines: Array = []
		for pid in payouts:
			lines.append("%s +%d" % [state.player(pid).name, payouts[pid]])
		TourneyUI.label(v, "Paid out: " + ", ".join(lines), BWStyle.F_BODY, TourneyUI.GOLD)
	TourneyUI.label(v, "Comments", BWStyle.F_SUB)
	_comments = VBoxContainer.new()
	v.add_child(_comments)
	var entry: Dictionary = state.log[-1]
	for p in state.players:
		if p.bot and state.rng.randf() < 0.7:
			entry.comments.append({ "who": p.name, "text": BOT_LINES[state.rng.randi() % BOT_LINES.size()] })
	_refresh()
	var r := TourneyUI.row(v)
	_entry = TourneyUI.line_edit(r, "", "Say something")
	_entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_entry.text_submitted.connect(func(t): _say(t))
	TourneyUI.button(r, "Send", func(): _say(_entry.text))
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sp)
	TourneyUI.button(v, "Continue", func(): done.emit())


func _say(t: String) -> void:
	if t.strip_edges() == "":
		return
	(state.log[-1].comments as Array).append({ "who": state.me().name, "text": t.strip_edges() })
	_entry.text = ""
	_refresh()


func _refresh() -> void:
	for c in _comments.get_children():
		c.queue_free()
	for c in state.log[-1].comments:
		TourneyUI.label(_comments, "%s:  %s" % [c.who, c.text], BWStyle.F_BODY, TourneyUI.DIM)
