extends Control

signal back_pressed

@onready var board: Control = %Board
@onready var left_hud: PanelContainer = %LeftHUD
@onready var hud: PanelContainer = %HUD
@onready var turn_bar: PanelContainer = %TurnBar
@onready var turn_label: Label = %TurnLabel

@onready var play_button: Button = %PlayButton
@onready var pause_button: Button = %PauseButton
@onready var step_back_button: Button = %StepBackButton
@onready var step_fwd_button: Button = %StepFwdButton
@onready var back_button: Button = %ReplayBackButton
@onready var move_label: Label = %MoveLabel
@onready var speed_select: OptionButton = %SpeedSelect
@onready var info_label: Label = %ReplayInfoLabel

var _recorder: GameRecorder = null
var _current_move: int = 0
var _playing: bool = false
var _play_timer: float = 0.0
var _play_speed: float = 0.5

# Saved state to restore when exiting replay
var _saved_bs: BoardState = null
var _saved_caps: Dictionary = {}
var _saved_mode: GameManager.GameMode = GameManager.GameMode.LOCAL_2P
var _saved_to: Vector2i = Vector2i(-1, -1)
var _saved_move_team: PieceData.Team = PieceData.Team.RED
var _saved_current: PieceData.Team = PieceData.Team.RED


func _ready() -> void:
	play_button.pressed.connect(_on_play)
	pause_button.pressed.connect(_on_pause)
	step_back_button.pressed.connect(_on_step_back)
	step_fwd_button.pressed.connect(_on_step_fwd)
	back_button.pressed.connect(func() -> void:
		_playing = false
		_restore_state()
		visible = false
		_hide_ui()
		back_pressed.emit()
	)
	speed_select.add_item("0.1s")
	speed_select.add_item("0.25s")
	speed_select.add_item("0.5s")
	speed_select.add_item("1.0s")
	speed_select.select(2)
	speed_select.item_selected.connect(func(idx: int) -> void:
		match idx:
			0: _play_speed = 0.1
			1: _play_speed = 0.25
			2: _play_speed = 0.5
			3: _play_speed = 1.0
	)


func load_replay(recorder: GameRecorder) -> void:
	_recorder = recorder
	_current_move = 0
	_playing = false

	# Save current GameManager state
	_saved_bs = GameManager.board_state
	_saved_caps = GameManager.captured_pieces
	_saved_mode = GameManager.game_mode
	_saved_to = GameManager.last_move_to
	_saved_move_team = GameManager.last_move_team
	_saved_current = GameManager.current_team

	# Set mode so board shows all pieces
	GameManager.game_mode = GameManager.GameMode.AI_VS_AI

	_show_ui()
	_update_info()
	_apply_state()


func _restore_state() -> void:
	GameManager.board_state = _saved_bs
	GameManager.captured_pieces = _saved_caps
	GameManager.game_mode = _saved_mode
	GameManager.last_move_to = _saved_to
	GameManager.last_move_team = _saved_move_team
	GameManager.current_team = _saved_current


func _process(delta: float) -> void:
	if not _playing or _recorder == null:
		return
	_play_timer += delta
	if _play_timer >= _play_speed:
		_play_timer = 0.0
		if _current_move < _recorder.get_total_moves():
			_current_move += 1
			_apply_state()
		else:
			_playing = false


func _on_play() -> void:
	if _recorder == null:
		return
	if _current_move >= _recorder.get_total_moves():
		_current_move = 0
	_playing = true
	_play_timer = 0.0


func _on_pause() -> void:
	_playing = false


func _on_step_back() -> void:
	_playing = false
	if _current_move > 0:
		_current_move -= 1
		_apply_state()


func _on_step_fwd() -> void:
	_playing = false
	if _recorder != null and _current_move < _recorder.get_total_moves():
		_current_move += 1
		_apply_state()


func _apply_state() -> void:
	if _recorder == null:
		return

	var state: Dictionary = _recorder.get_state_at_move(_current_move)
	var bs: BoardState = state["board_state"]
	var caps: Dictionary = state["captured"]
	var current_team: PieceData.Team = state["current_team"]

	# Set GameManager state persistently (board reads it at draw time)
	GameManager.board_state = bs
	GameManager.captured_pieces = caps
	GameManager.last_move_to = state["last_to"]
	GameManager.current_team = current_team

	if _current_move > 0:
		if current_team == PieceData.Team.RED:
			GameManager.last_move_team = PieceData.Team.BLUE
		else:
			GameManager.last_move_team = PieceData.Team.RED
	else:
		GameManager.last_move_team = current_team
		GameManager.last_move_to = Vector2i(-1, -1)

	turn_label.text = "%s's Turn — Move %d/%d" % [PieceData.get_team_name(current_team), _current_move, _recorder.get_total_moves()]
	var color: Color = Color(0.9, 0.3, 0.3) if current_team == PieceData.Team.RED else Color(0.3, 0.4, 0.9)
	turn_label.add_theme_color_override("font_color", color)

	left_hud.update_remaining(PieceData.Team.RED)
	hud.update_enemy_remaining(PieceData.Team.RED)
	board.refresh()

	move_label.text = "Move %d / %d" % [_current_move, _recorder.get_total_moves()]


func _update_info() -> void:
	if _recorder == null:
		return
	var m: Dictionary = _recorder.metadata
	info_label.text = "%s — %s vs %s — %s" % [
		m.get("mode", ""),
		m.get("red_ai", "Human"),
		m.get("blue_ai", "Human"),
		m.get("result", ""),
	]


func _show_ui() -> void:
	visible = true
	board.visible = true
	left_hud.visible = true
	hud.visible = true
	turn_bar.visible = true
	board.offset_left = 220
	board.offset_top = 36


func _hide_ui() -> void:
	left_hud.visible = false
	hud.visible = false
	turn_bar.visible = false
	board.offset_left = 0
	board.offset_top = 0
