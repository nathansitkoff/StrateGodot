extends Control

@onready var board: Control = %Board
@onready var setup_phase: Control = %SetupPhase
@onready var turn_switch: ColorRect = %TurnSwitch
@onready var hud: PanelContainer = %HUD
@onready var left_hud: PanelContainer = %LeftHUD
@onready var game_over: ColorRect = %GameOver
@onready var main_menu: ColorRect = %MainMenu

var play_controller: Node
# AI players keyed by team — null entries mean human-controlled
var ai_players: Dictionary = {}

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

	play_controller = Node.new()
	play_controller.set_script(preload("res://scripts/ui/play_controller.gd"))
	add_child(play_controller)
	play_controller.setup(board)


func _on_mode_selected(mode: GameManager.GameMode) -> void:
	ai_players.clear()
	match mode:
		GameManager.GameMode.VS_AI:
			var ai_blue: AIPlayer = AIPlayer.new()
			ai_blue.team = PieceData.Team.BLUE
			ai_players[PieceData.Team.BLUE] = ai_blue
		GameManager.GameMode.AI_TEST:
			var ai_blue: AIPlayer = AIPlayer.new()
			ai_blue.team = PieceData.Team.BLUE
			ai_players[PieceData.Team.BLUE] = ai_blue
		GameManager.GameMode.AI_VS_AI:
			var ai_red: AIPlayer = AIPlayer.new()
			ai_red.team = PieceData.Team.RED
			var ai_blue: AIPlayer = AIPlayer.new()
			ai_blue.team = PieceData.Team.BLUE
			ai_players[PieceData.Team.RED] = ai_red
			ai_players[PieceData.Team.BLUE] = ai_blue
	for team: int in ai_players:
		ai_players[team].reset()
	GameManager.start_game(mode)


func _uses_dual_sidebars() -> bool:
	return GameManager.game_mode == GameManager.GameMode.AI_TEST or GameManager.game_mode == GameManager.GameMode.AI_VS_AI


func _on_phase_changed(phase: GameManager.GamePhase) -> void:
	var is_test: bool = GameManager.game_mode == GameManager.GameMode.AI_TEST
	var is_ai_vs_ai: bool = GameManager.game_mode == GameManager.GameMode.AI_VS_AI

	match phase:
		GameManager.GamePhase.SETUP_RED:
			hud.visible = false
			left_hud.visible = false
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
				turn_switch.show_turn(PieceData.Team.BLUE)
		GameManager.GamePhase.PLAY:
			setup_phase.visible = false
			hud.visible = true
			hud.clear_combat()
			hud.update_turn(GameManager.current_team)
			if _uses_dual_sidebars():
				left_hud.visible = true
				board.offset_left = 220
				left_hud.update_remaining(PieceData.Team.RED)
				hud.update_enemy_remaining(PieceData.Team.RED)
			else:
				left_hud.visible = false
				board.offset_left = 0
				hud.update_enemy_remaining(_get_viewing_team())
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
	hud.update_turn(team)

	if _uses_dual_sidebars():
		left_hud.update_remaining(PieceData.Team.RED)
		hud.update_enemy_remaining(PieceData.Team.RED)
	else:
		hud.update_enemy_remaining(_get_viewing_team())

	# Notify AI players of enemy piece movement
	if GameManager.last_move_to != Vector2i(-1, -1):
		var moved_id: int = GameManager.board_state.get_piece_at(GameManager.last_move_to)
		if moved_id != -1:
			for ai_team: int in ai_players:
				if ai_team != GameManager.last_move_team:
					ai_players[ai_team].notify_move(moved_id, GameManager.last_move_team)

	if _is_ai_team(team):
		_schedule_ai_move()
	elif GameManager.game_mode == GameManager.GameMode.LOCAL_2P:
		turn_switch.show_turn(team)
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
	if _uses_dual_sidebars():
		left_hud.update_remaining(PieceData.Team.RED)
		hud.update_enemy_remaining(PieceData.Team.RED)
	else:
		hud.update_enemy_remaining(_get_viewing_team())
	game_over.show_winner(winner)


func _on_turn_switch_acknowledged() -> void:
	if GameManager.current_phase == GameManager.GamePhase.SETUP_BLUE:
		setup_phase.start_setup(PieceData.Team.BLUE)
	else:
		board.refresh()


func _on_play_again() -> void:
	hud.visible = false
	left_hud.visible = false
	board.offset_left = 0
	main_menu.visible = true


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

	var ai: AIPlayer = ai_players[GameManager.current_team]
	var move: Dictionary = ai.choose_move(GameManager.board_state)
	if move.size() > 0:
		GameManager.execute_move(move["from"], move["to"])
		board.refresh()
