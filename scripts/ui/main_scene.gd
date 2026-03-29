extends Control

@onready var board: Control = %Board
@onready var setup_phase: Control = %SetupPhase
@onready var turn_switch: ColorRect = %TurnSwitch
@onready var hud: PanelContainer = %HUD
@onready var game_over: ColorRect = %GameOver
@onready var main_menu: ColorRect = %MainMenu

var play_controller: Node
var ai_player: AIPlayer

const AI_MOVE_DELAY: float = 0.5


func _ready() -> void:
	GameManager.phase_changed.connect(_on_phase_changed)
	GameManager.turn_changed.connect(_on_turn_changed)
	GameManager.combat_occurred.connect(_on_combat_occurred)
	GameManager.game_ended.connect(_on_game_ended)
	setup_phase.setup_complete.connect(_on_setup_complete)
	turn_switch.acknowledged.connect(_on_turn_switch_acknowledged)
	game_over.play_again_pressed.connect(_on_play_again)
	main_menu.mode_selected.connect(_on_mode_selected)

	play_controller = Node.new()
	play_controller.set_script(preload("res://scripts/ui/play_controller.gd"))
	add_child(play_controller)
	play_controller.setup(board)


func _on_mode_selected(mode: GameManager.GameMode) -> void:
	if mode == GameManager.GameMode.VS_AI:
		ai_player = AIPlayer.new()
		ai_player.team = PieceData.Team.BLUE
	else:
		ai_player = null
	GameManager.start_game(mode)


func _on_phase_changed(phase: GameManager.GamePhase) -> void:
	match phase:
		GameManager.GamePhase.SETUP_RED:
			hud.visible = false
			setup_phase.start_setup(PieceData.Team.RED)
		GameManager.GamePhase.SETUP_BLUE:
			if _is_ai_team(PieceData.Team.BLUE):
				ai_player.generate_setup(GameManager.board_state)
				board.refresh()
				GameManager.finish_setup(PieceData.Team.BLUE)
			else:
				turn_switch.show_turn(PieceData.Team.BLUE)
		GameManager.GamePhase.PLAY:
			setup_phase.visible = false
			hud.visible = true
			hud.clear_combat()
			hud.update_turn(GameManager.current_team)
			hud.update_captured()
			board.refresh()
		GameManager.GamePhase.GAME_OVER:
			pass


func _on_setup_complete(team: PieceData.Team) -> void:
	GameManager.finish_setup(team)


func _on_turn_changed(team: PieceData.Team) -> void:
	board.clear_selection()
	hud.update_turn(team)
	hud.update_captured()

	if _is_ai_team(team):
		_schedule_ai_move()
	elif GameManager.game_mode == GameManager.GameMode.LOCAL_2P:
		turn_switch.show_turn(team)
	else:
		# VS_AI, player's turn
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
	hud.update_captured()
	game_over.show_winner(winner)


func _on_turn_switch_acknowledged() -> void:
	if GameManager.current_phase == GameManager.GamePhase.SETUP_BLUE:
		setup_phase.start_setup(PieceData.Team.BLUE)
	else:
		board.refresh()


func _on_play_again() -> void:
	hud.visible = false
	main_menu.visible = true


func _is_ai_team(team: PieceData.Team) -> bool:
	return ai_player != null and team == ai_player.team


func _schedule_ai_move() -> void:
	board.refresh()
	get_tree().create_timer(AI_MOVE_DELAY).timeout.connect(_execute_ai_move)


func _execute_ai_move() -> void:
	if GameManager.current_phase != GameManager.GamePhase.PLAY:
		return
	if not _is_ai_team(GameManager.current_team):
		return

	var move: Dictionary = ai_player.choose_move(GameManager.board_state)
	if move.size() > 0:
		GameManager.execute_move(move["from"], move["to"])
		board.refresh()
