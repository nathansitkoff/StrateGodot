extends Control

@onready var board: Control = %Board
@onready var setup_phase: Control = %SetupPhase
@onready var turn_switch: ColorRect = %TurnSwitch
@onready var combat_popup: ColorRect = %CombatPopup
@onready var game_over: ColorRect = %GameOver
@onready var main_menu: ColorRect = %MainMenu

var play_controller: Node
var ai_player: AIPlayer

# Store combat info to show popup after turn switch
var _pending_combat: Dictionary = {}
var _waiting_for_combat_ack: bool = false
var _game_over_pending: bool = false

const AI_MOVE_DELAY: float = 0.5


func _ready() -> void:
	GameManager.phase_changed.connect(_on_phase_changed)
	GameManager.turn_changed.connect(_on_turn_changed)
	GameManager.combat_occurred.connect(_on_combat_occurred)
	GameManager.game_ended.connect(_on_game_ended)
	setup_phase.setup_complete.connect(_on_setup_complete)
	turn_switch.acknowledged.connect(_on_turn_switch_acknowledged)
	combat_popup.closed.connect(_on_combat_popup_closed)
	game_over.play_again_pressed.connect(_on_play_again)
	main_menu.mode_selected.connect(_on_mode_selected)

	# Create play controller
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
			setup_phase.start_setup(PieceData.Team.RED)
		GameManager.GamePhase.SETUP_BLUE:
			if _is_ai_team(PieceData.Team.BLUE):
				# AI places pieces automatically
				ai_player.generate_setup(GameManager.board_state)
				board.refresh()
				GameManager.finish_setup(PieceData.Team.BLUE)
			else:
				turn_switch.show_turn(PieceData.Team.BLUE)
		GameManager.GamePhase.PLAY:
			setup_phase.visible = false
			board.refresh()
		GameManager.GamePhase.GAME_OVER:
			pass


func _on_setup_complete(team: PieceData.Team) -> void:
	GameManager.finish_setup(team)


func _on_turn_changed(team: PieceData.Team) -> void:
	board.clear_selection()

	if _is_ai_team(team):
		# Show combat popup for player's attack first, then AI moves
		if _pending_combat.size() > 0:
			_waiting_for_combat_ack = true
			combat_popup.show_result(
				_pending_combat["atk_rank"],
				_pending_combat["def_rank"],
				_pending_combat["atk_team"],
				_pending_combat["result"],
			)
		else:
			_schedule_ai_move()
	elif GameManager.game_mode == GameManager.GameMode.LOCAL_2P:
		if _pending_combat.size() > 0:
			_waiting_for_combat_ack = true
			combat_popup.show_result(
				_pending_combat["atk_rank"],
				_pending_combat["def_rank"],
				_pending_combat["atk_team"],
				_pending_combat["result"],
			)
		else:
			turn_switch.show_turn(team)
	elif GameManager.game_mode == GameManager.GameMode.VS_AI:
		# AI just moved, show combat result if any, then player's turn
		if _pending_combat.size() > 0:
			combat_popup.show_result(
				_pending_combat["atk_rank"],
				_pending_combat["def_rank"],
				_pending_combat["atk_team"],
				_pending_combat["result"],
			)
		else:
			board.refresh()


func _on_combat_occurred(combat_info: Dictionary) -> void:
	_pending_combat = combat_info


func _on_game_ended(winner: PieceData.Team) -> void:
	board.refresh()
	if _pending_combat.size() > 0:
		_waiting_for_combat_ack = false
		combat_popup.show_result(
			_pending_combat["atk_rank"],
			_pending_combat["def_rank"],
			_pending_combat["atk_team"],
			_pending_combat["result"],
		)
		_pending_combat.clear()
		_game_over_pending = true
	else:
		game_over.show_winner(winner)


func _on_turn_switch_acknowledged() -> void:
	if GameManager.current_phase == GameManager.GamePhase.SETUP_BLUE:
		setup_phase.start_setup(PieceData.Team.BLUE)
	else:
		board.refresh()


func _on_combat_popup_closed() -> void:
	_pending_combat.clear()
	if _game_over_pending:
		_game_over_pending = false
		game_over.show_winner(GameManager.winner)
	elif _waiting_for_combat_ack:
		_waiting_for_combat_ack = false
		if _is_ai_team(GameManager.current_team):
			_schedule_ai_move()
		else:
			if GameManager.game_mode == GameManager.GameMode.LOCAL_2P:
				turn_switch.show_turn(GameManager.current_team)
			else:
				board.refresh()
	else:
		board.refresh()


func _on_play_again() -> void:
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
