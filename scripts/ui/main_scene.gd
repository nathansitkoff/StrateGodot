extends Control

@onready var board: Control = %Board
@onready var setup_phase: Control = %SetupPhase
@onready var turn_switch: ColorRect = %TurnSwitch
@onready var hud: PanelContainer = %HUD
@onready var left_hud: PanelContainer = %LeftHUD
@onready var turn_bar: PanelContainer = %TurnBar
@onready var turn_label: Label = %TurnLabel
@onready var game_over: ColorRect = %GameOver
@onready var game_options: ColorRect = %GameOptions
@onready var headless_test: ColorRect = %HeadlessTest
@onready var replay_browser: ColorRect = %ReplayBrowser
@onready var replay_viewer: Control = %ReplayViewer
@onready var main_menu: ColorRect = %MainMenu

var play_controller: Node
var ai_players: Dictionary = {}
var _pending_mode: GameManager.GameMode = GameManager.GameMode.LOCAL_2P
var _recorder: GameRecorder = null
var _red_ai_name: String = "Human"
var _blue_ai_name: String = "Human"

const AI_MOVE_DELAY: float = 0.5


func _ready() -> void:
	GameManager.phase_changed.connect(_on_phase_changed)
	GameManager.turn_changed.connect(_on_turn_changed)
	GameManager.combat_occurred.connect(_on_combat_occurred)
	GameManager.game_ended.connect(_on_game_ended)
	setup_phase.setup_complete.connect(_on_setup_complete)
	setup_phase.ai_place_requested.connect(_on_ai_place_requested)
	turn_switch.acknowledged.connect(_on_turn_switch_acknowledged)
	game_over.play_again_pressed.connect(_on_play_again)
	main_menu.mode_selected.connect(_on_mode_selected)
	main_menu.headless_selected.connect(_on_headless_selected)
	main_menu.replays_selected.connect(_on_replays_selected)
	game_options.options_confirmed.connect(_on_options_confirmed)
	headless_test.back_pressed.connect(_on_headless_back)
	replay_browser.back_pressed.connect(_on_replay_browser_back)
	replay_browser.replay_selected.connect(_on_replay_selected)
	replay_viewer.back_pressed.connect(_on_replay_viewer_back)

	play_controller = Node.new()
	play_controller.set_script(preload("res://scripts/ui/play_controller.gd"))
	add_child(play_controller)
	play_controller.setup(board)


func _on_mode_selected(mode: GameManager.GameMode) -> void:
	_pending_mode = mode
	game_options.show_options(mode)


func _get_mode_name() -> String:
	match _pending_mode:
		GameManager.GameMode.LOCAL_2P: return "Local2P"
		GameManager.GameMode.VS_AI: return "VsAI"
		GameManager.GameMode.AI_TEST: return "AITest"
		GameManager.GameMode.AI_VS_AI: return "AIvsAI"
		_: return "Unknown"


func _on_options_confirmed(first_team: PieceData.Team, red_ai_type: int, blue_ai_type: int) -> void:
	ai_players.clear()
	_red_ai_name = "Human"
	_blue_ai_name = "Human"
	match _pending_mode:
		GameManager.GameMode.VS_AI:
			ai_players[PieceData.Team.BLUE] = AIBase.create(blue_ai_type, PieceData.Team.BLUE)
			_blue_ai_name = AIBase.AI_NAMES[blue_ai_type]
		GameManager.GameMode.AI_TEST:
			ai_players[PieceData.Team.BLUE] = AIBase.create(blue_ai_type, PieceData.Team.BLUE)
			_blue_ai_name = AIBase.AI_NAMES[blue_ai_type]
		GameManager.GameMode.AI_VS_AI:
			ai_players[PieceData.Team.RED] = AIBase.create(red_ai_type, PieceData.Team.RED)
			ai_players[PieceData.Team.BLUE] = AIBase.create(blue_ai_type, PieceData.Team.BLUE)
			_red_ai_name = AIBase.AI_NAMES[red_ai_type]
			_blue_ai_name = AIBase.AI_NAMES[blue_ai_type]

	_recorder = GameRecorder.new()
	_recorder.start_recording(_get_mode_name(), _red_ai_name, _blue_ai_name, first_team)
	GameManager.recorder = _recorder
	GameManager.start_game(_pending_mode, first_team)


func _on_phase_changed(phase: GameManager.GamePhase) -> void:
	var is_test: bool = GameManager.game_mode == GameManager.GameMode.AI_TEST
	var is_ai_vs_ai: bool = GameManager.game_mode == GameManager.GameMode.AI_VS_AI

	match phase:
		GameManager.GamePhase.SETUP_RED:
			hud.visible = false
			left_hud.visible = false
			turn_bar.visible = false
			board.offset_top = 0
			board.offset_left = 0
			if is_ai_vs_ai:
				ai_players[PieceData.Team.RED].generate_setup(GameManager.board_state)
				board.refresh()
				GameManager.finish_setup(PieceData.Team.RED)
			else:
				setup_phase.start_setup(PieceData.Team.RED, is_test)
		GameManager.GamePhase.SETUP_BLUE:
			if _is_ai_team(PieceData.Team.BLUE) and not is_test:
				ai_players[PieceData.Team.BLUE].generate_setup(GameManager.board_state)
				board.refresh()
				GameManager.finish_setup(PieceData.Team.BLUE)
			elif is_test:
				setup_phase.start_setup(PieceData.Team.BLUE, true)
			else:
				turn_switch.show_turn(PieceData.Team.BLUE, false)
		GameManager.GamePhase.PLAY:
			# Record initial placements
			if _recorder != null:
				_recorder.record_placements_from_board(GameManager.board_state)
			setup_phase.visible = false
			hud.visible = true
			left_hud.visible = true
			turn_bar.visible = true
			board.offset_top = 36
			board.offset_left = 220
			hud.clear_combat()
			_update_turn_bar(GameManager.current_team)
			_update_remaining()
			board.refresh()
		GameManager.GamePhase.GAME_OVER:
			pass


func _on_setup_complete(team: PieceData.Team) -> void:
	GameManager.finish_setup(team)


func _on_ai_place_requested(team: PieceData.Team) -> void:
	if team in ai_players:
		ai_players[team].generate_setup(GameManager.board_state)
		board.refresh()


func _on_turn_changed(team: PieceData.Team) -> void:
	board.clear_selection()
	_update_turn_bar(team)
	_update_remaining()

	# Notify AI players of enemy piece movement (only if mover survived)
	if GameManager.last_move_to != Vector2i(-1, -1):
		var moved_id: int = GameManager.board_state.get_piece_at(GameManager.last_move_to)
		if moved_id != -1 and GameManager.board_state.pieces[moved_id]["team"] == GameManager.last_move_team:
			for ai_team: int in ai_players:
				if ai_team != GameManager.last_move_team:
					ai_players[ai_team].notify_move(moved_id, GameManager.last_move_team)

	if _is_ai_team(team):
		_schedule_ai_move()
	elif GameManager.game_mode == GameManager.GameMode.LOCAL_2P:
		turn_switch.show_turn(team, true)
	else:
		board.refresh()


func _on_combat_occurred(combat_info: Dictionary) -> void:
	hud.show_combat_result(
		combat_info["atk_rank"],
		combat_info["def_rank"],
		combat_info["atk_team"],
		combat_info["result"],
	)


func _on_game_ended(winner: PieceData.Team) -> void:
	board.refresh()
	_update_remaining()
	# Save replay
	if _recorder != null:
		var result_str: String = "flag_captured"
		if not GameManager.board_state.has_movable_pieces(PieceData.Team.RED if winner == PieceData.Team.BLUE else PieceData.Team.BLUE):
			result_str = "opponent_stuck"
		_recorder.finish_recording(result_str, winner, _recorder.get_total_moves())
		DirAccess.make_dir_recursive_absolute("user://replays")
		var filepath: String = GameRecorder.generate_filename(_get_mode_name(), _red_ai_name, _blue_ai_name)
		_recorder.save_to_file(filepath)
	game_over.show_winner(winner)


func _on_turn_switch_acknowledged() -> void:
	if GameManager.current_phase == GameManager.GamePhase.SETUP_BLUE:
		setup_phase.start_setup(PieceData.Team.BLUE)
	else:
		board.refresh()


func _on_play_again() -> void:
	hud.visible = false
	left_hud.visible = false
	turn_bar.visible = false
	board.offset_left = 0
	board.offset_top = 0
	_recorder = null
	GameManager.recorder = null
	main_menu.visible = true


func _on_headless_selected() -> void:
	headless_test.visible = true


func _on_headless_back() -> void:
	main_menu.visible = true


func _on_replays_selected() -> void:
	replay_browser.show_browser()


func _on_replay_browser_back() -> void:
	main_menu.visible = true


func _on_replay_selected(filepath: String) -> void:
	var recorder: GameRecorder = GameRecorder.load_from_file(filepath)
	if recorder != null:
		replay_viewer.load_replay(recorder)


func _on_replay_viewer_back() -> void:
	main_menu.visible = true


func _update_remaining() -> void:
	left_hud.update_remaining(PieceData.Team.RED)
	hud.update_enemy_remaining(PieceData.Team.RED)


func _update_turn_bar(team: PieceData.Team) -> void:
	var team_name: String = PieceData.get_team_name(team)
	var color: Color = Color(0.9, 0.3, 0.3) if team == PieceData.Team.RED else Color(0.3, 0.4, 0.9)
	turn_label.text = "%s's Turn" % team_name
	turn_label.add_theme_color_override("font_color", color)


func _get_viewing_team() -> PieceData.Team:
	if GameManager.game_mode == GameManager.GameMode.VS_AI or GameManager.game_mode == GameManager.GameMode.AI_TEST or GameManager.game_mode == GameManager.GameMode.AI_VS_AI:
		return PieceData.Team.RED
	return GameManager.current_team


func _is_ai_team(team: PieceData.Team) -> bool:
	return team in ai_players


func _schedule_ai_move() -> void:
	board.refresh()
	get_tree().create_timer(AI_MOVE_DELAY).timeout.connect(_execute_ai_move)


func _execute_ai_move() -> void:
	if GameManager.current_phase != GameManager.GamePhase.PLAY:
		return
	if not _is_ai_team(GameManager.current_team):
		return

	var ai: AIBase = ai_players[GameManager.current_team]
	var move: Dictionary = ai.choose_move(GameManager.board_state)
	if move.size() > 0:
		GameManager.execute_move(move["from"], move["to"])
		board.refresh()
