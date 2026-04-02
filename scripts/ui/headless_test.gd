extends ColorRect

signal back_pressed

@onready var game_count_input: SpinBox = %GameCountInput
@onready var red_ai_select: OptionButton = %RedAISelect
@onready var blue_ai_select: OptionButton = %BlueAISelect
@onready var red_place_select: OptionButton = %RedPlaceSelect
@onready var blue_place_select: OptionButton = %BluePlaceSelect
@onready var save_select: OptionButton = %SaveSelect
@onready var start_button: Button = %StartButton
@onready var stop_button: Button = %StopButton
@onready var back_button: Button = %BackButton
@onready var progress_label: Label = %ProgressLabel
@onready var status_label: Label = %StatusLabel
@onready var left_stats: Label = %LeftStats
@onready var right_stats: Label = %RightStats

var _running: bool = false
var _red_wins: int = 0
var _blue_wins: int = 0
var _draws: int = 0
var _games_played: int = 0
var _games_total: int = 0
var _first_mover_wins: int = 0
var _second_mover_wins: int = 0
var _red_first_red_wins: int = 0
var _red_first_blue_wins: int = 0
var _blue_first_red_wins: int = 0
var _blue_first_blue_wins: int = 0
var _flag_captures: Dictionary = { "red": 0, "blue": 0 }
var _no_moves: Dictionary = { "red": 0, "blue": 0 }
var _opponent_stuck: Dictionary = { "red": 0, "blue": 0 }
var _illegal_moves: Dictionary = { "red": 0, "blue": 0 }
var _timeouts: int = 0
var _total_turns: int = 0

const BATCH_SIZE: int = 1


func _ready() -> void:
	start_button.pressed.connect(_on_start)
	stop_button.pressed.connect(_on_stop)
	back_button.pressed.connect(func() -> void:
		_running = false
		visible = false
		back_pressed.emit()
	)
	for ai_name: String in AIBase.AI_NAMES:
		red_ai_select.add_item(ai_name)
		blue_ai_select.add_item(ai_name)
	for strat_name: String in Placement.STRATEGY_NAMES:
		red_place_select.add_item(strat_name)
		blue_place_select.add_item(strat_name)
	save_select.add_item("Don't Save")
	save_select.add_item("Save Draws")
	save_select.add_item("Save All")
	stop_button.disabled = true


func _on_start() -> void:
	if _running:
		return
	_running = true
	_red_wins = 0
	_blue_wins = 0
	_draws = 0
	_games_played = 0
	_first_mover_wins = 0
	_second_mover_wins = 0
	_red_first_red_wins = 0
	_red_first_blue_wins = 0
	_blue_first_red_wins = 0
	_blue_first_blue_wins = 0
	_flag_captures = { "red": 0, "blue": 0 }
	_no_moves = { "red": 0, "blue": 0 }
	_opponent_stuck = { "red": 0, "blue": 0 }
	_illegal_moves = { "red": 0, "blue": 0 }
	_timeouts = 0
	_total_turns = 0
	_games_total = int(game_count_input.value)
	_update_display()
	start_button.disabled = true
	stop_button.disabled = false
	status_label.text = "Running..."
	get_tree().create_timer(0.0).timeout.connect(_run_batch)


func _on_stop() -> void:
	_running = false
	_finish()


func _run_batch() -> void:
	if not _running:
		return

	for i: int in range(BATCH_SIZE):
		if not _running or _games_played >= _games_total:
			break

		var red_ai_name: String = AIBase.AI_NAMES[red_ai_select.selected]
		var blue_ai_name: String = AIBase.AI_NAMES[blue_ai_select.selected]
		var ai_red: AIBase = AIBase.create(red_ai_select.selected, PieceData.Team.RED)
		ai_red.placement_strategy = red_place_select.selected as Placement.Strategy
		var ai_blue: AIBase = AIBase.create(blue_ai_select.selected, PieceData.Team.BLUE)
		ai_blue.placement_strategy = blue_place_select.selected as Placement.Strategy

		var starting: PieceData.Team = PieceData.Team.RED if _games_played % 2 == 0 else PieceData.Team.BLUE
		var save_mode: int = save_select.selected
		var rec: GameRecorder = null
		if save_mode > 0:
			rec = GameRecorder.new()
			rec.start_recording("Headless", red_ai_name, blue_ai_name, starting)

		var result: Dictionary = GameManager.run_headless_game(ai_red, ai_blue, starting, rec)
		var reason: String = result["reason"]
		var turns: int = result["turns"]

		_total_turns += turns

		if rec != null:
			var should_save: bool = (save_mode == 2) or (save_mode == 1 and (reason == "timeout" or reason == "illegal_move"))
			if should_save:
				rec.finish_recording(reason, result["winner"], turns)
				DirAccess.make_dir_recursive_absolute("user://replays")
				rec.save_to_file(GameRecorder.generate_filename("Headless", red_ai_name, blue_ai_name))

		if reason == "timeout":
			_draws += 1
			_timeouts += 1
			_games_played += 1
			continue

		if reason == "illegal_move":
			_draws += 1
			var offender: String = "red" if result["last_team"] == PieceData.Team.RED else "blue"
			_illegal_moves[offender] += 1
			_games_played += 1
			continue

		var winner: PieceData.Team = result["winner"] as PieceData.Team
		var winner_key: String = "red" if winner == PieceData.Team.RED else "blue"

		if winner == PieceData.Team.RED:
			_red_wins += 1
		else:
			_blue_wins += 1

		match reason:
			"flag_captured":
				_flag_captures[winner_key] += 1
			"no_moves":
				_no_moves[winner_key] += 1
			"opponent_stuck":
				_opponent_stuck[winner_key] += 1

		if winner == starting:
			_first_mover_wins += 1
		else:
			_second_mover_wins += 1

		if starting == PieceData.Team.RED:
			if winner == PieceData.Team.RED:
				_red_first_red_wins += 1
			else:
				_red_first_blue_wins += 1
		else:
			if winner == PieceData.Team.RED:
				_blue_first_red_wins += 1
			else:
				_blue_first_blue_wins += 1

		_games_played += 1

	_update_display()

	if not _running or _games_played >= _games_total:
		_finish()
	else:
		get_tree().create_timer(0.0).timeout.connect(_run_batch)


func _update_display() -> void:
	progress_label.text = "%d / %d" % [_games_played, _games_total]

	var avg_turns: float = _total_turns / max(_games_played, 1) as float
	var red_first_total: int = _red_first_red_wins + _red_first_blue_wins
	var blue_first_total: int = _blue_first_red_wins + _blue_first_blue_wins

	var left: Array[String] = [
		"Red Wins: %d" % _red_wins,
		"Blue Wins: %d" % _blue_wins,
		"Draws: %d" % _draws,
		"",
		"First mover wins: %d" % _first_mover_wins,
		"Second mover wins: %d" % _second_mover_wins,
		"Avg turns: %.0f" % avg_turns,
		"",
		"Red goes first (%d):" % red_first_total,
		"  Red: %d  Blue: %d" % [_red_first_red_wins, _red_first_blue_wins],
		"Blue goes first (%d):" % blue_first_total,
		"  Red: %d  Blue: %d" % [_blue_first_red_wins, _blue_first_blue_wins],
	]

	var right: Array[String] = [
		"Flag capture:",
		"  Red: %d  Blue: %d" % [_flag_captures["red"], _flag_captures["blue"]],
		"No moves:",
		"  Red: %d  Blue: %d" % [_no_moves["red"], _no_moves["blue"]],
		"Opponent stuck:",
		"  Red: %d  Blue: %d" % [_opponent_stuck["red"], _opponent_stuck["blue"]],
		"Illegal moves:",
		"  Red: %d  Blue: %d" % [_illegal_moves["red"], _illegal_moves["blue"]],
		"Timeouts: %d" % _timeouts,
	]

	left_stats.text = "\n".join(left)
	right_stats.text = "\n".join(right)


func _finish() -> void:
	_running = false
	start_button.disabled = false
	stop_button.disabled = true
	status_label.text = "Done! (%d games)" % _games_played
