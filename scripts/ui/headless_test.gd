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

var _running: bool = false
var _red_wins: int = 0
var _blue_wins: int = 0
var _draws: int = 0
var _games_played: int = 0
var _games_total: int = 0
# How many games to run per frame before yielding
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
	_games_total = int(game_count_input.value)
	_update_display()
	start_button.disabled = true
	back_button.disabled = true
	status_label.text = "Running..."
	# Wait one frame so the UI updates before we start
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

		var winner: PieceData.Team = GameManager.run_headless_game(ai_red, ai_blue)
		if winner == PieceData.Team.RED:
			_red_wins += 1
		else:
			_blue_wins += 1

		_games_played += 1

	_update_display()

	if _games_played >= _games_total:
		_finish()
	else:
		# Yield a frame so the UI redraws
		get_tree().create_timer(0.0).timeout.connect(_run_batch)


func _update_display() -> void:
	red_wins_label.text = "Red Wins: %d" % _red_wins
	blue_wins_label.text = "Blue Wins: %d" % _blue_wins
	draws_label.text = "Draws: %d" % _draws
	progress_label.text = "%d / %d" % [_games_played, _games_total]


func _finish() -> void:
	_running = false
	start_button.disabled = false
	back_button.disabled = false
	status_label.text = "Done!"
