extends ColorRect

signal back_pressed

@onready var game_count_input: SpinBox = %GameCountInput
@onready var start_button: Button = %StartButton
@onready var back_button: Button = %BackButton
@onready var red_wins_label: Label = %RedWinsLabel
@onready var blue_wins_label: Label = %BlueWinsLabel
@onready var draws_label: Label = %DrawsLabel
@onready var progress_label: Label = %ProgressLabel
@onready var status_label: Label = %StatusLabel
@onready var breakdown_label: Label = %BreakdownLabel

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
# Win reason counters
var _flag_captures: Dictionary = { "red": 0, "blue": 0 }
var _no_moves: Dictionary = { "red": 0, "blue": 0 }
var _opponent_stuck: Dictionary = { "red": 0, "blue": 0 }
var _timeouts: int = 0
var _total_turns: int = 0

const BATCH_SIZE: int = 5


func _ready() -> void:
	start_button.pressed.connect(_on_start)
	back_button.pressed.connect(func() -> void:
		visible = false
		back_pressed.emit()
	)


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
	_timeouts = 0
	_total_turns = 0
	_games_total = int(game_count_input.value)
	_update_display()
	start_button.disabled = true
	back_button.disabled = true
	status_label.text = "Running..."
	get_tree().create_timer(0.0).timeout.connect(_run_batch)


func _run_batch() -> void:
	if not _running:
		return

	for i: int in range(BATCH_SIZE):
		if _games_played >= _games_total:
			break

		var ai_red: AIPlayer = AIPlayer.new()
		ai_red.team = PieceData.Team.RED
		var ai_blue: AIPlayer = AIPlayer.new()
		ai_blue.team = PieceData.Team.BLUE

		var starting: PieceData.Team = PieceData.Team.RED if _games_played % 2 == 0 else PieceData.Team.BLUE
		var result: Dictionary = GameManager.run_headless_game(ai_red, ai_blue, starting)
		var winner: PieceData.Team = result["winner"]
		var reason: String = result["reason"]
		var turns: int = result["turns"]

		_total_turns += turns
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
			"timeout":
				_timeouts += 1

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

	if _games_played >= _games_total:
		_finish()
	else:
		get_tree().create_timer(0.0).timeout.connect(_run_batch)


func _update_display() -> void:
	red_wins_label.text = "Red Wins: %d" % _red_wins
	blue_wins_label.text = "Blue Wins: %d" % _blue_wins
	draws_label.text = "Draws: %d" % _draws
	progress_label.text = "%d / %d" % [_games_played, _games_total]

	var avg_turns: float = _total_turns / max(_games_played, 1) as float
	var red_first_total: int = _red_first_red_wins + _red_first_blue_wins
	var blue_first_total: int = _blue_first_red_wins + _blue_first_blue_wins
	var lines: Array[String] = [
		"First mover wins: %d  Second: %d" % [_first_mover_wins, _second_mover_wins],
		"Avg turns: %.0f" % avg_turns,
		"",
		"Red goes first (%d):" % red_first_total,
		"  Red: %d  Blue: %d" % [_red_first_red_wins, _red_first_blue_wins],
		"Blue goes first (%d):" % blue_first_total,
		"  Red: %d  Blue: %d" % [_blue_first_red_wins, _blue_first_blue_wins],
		"",
		"Win by flag capture:",
		"  Red: %d  Blue: %d" % [_flag_captures["red"], _flag_captures["blue"]],
		"Win by no moves:",
		"  Red: %d  Blue: %d" % [_no_moves["red"], _no_moves["blue"]],
		"Win by opponent stuck:",
		"  Red: %d  Blue: %d" % [_opponent_stuck["red"], _opponent_stuck["blue"]],
		"Timeouts: %d" % _timeouts,
	]
	breakdown_label.text = "\n".join(lines)


func _finish() -> void:
	_running = false
	start_button.disabled = false
	back_button.disabled = false
	status_label.text = "Done!"
