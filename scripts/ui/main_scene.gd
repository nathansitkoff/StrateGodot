extends Control

@onready var board: Control = %Board
@onready var setup_phase: Control = %SetupPhase
@onready var turn_switch: ColorRect = %TurnSwitch
@onready var combat_popup: ColorRect = %CombatPopup
@onready var game_over: ColorRect = %GameOver

var play_controller: Node

# Store combat info to show popup after turn switch
var _pending_combat: Dictionary = {}
var _waiting_for_combat_ack: bool = false
var _game_over_pending: bool = false


func _ready() -> void:
	GameManager.phase_changed.connect(_on_phase_changed)
	GameManager.turn_changed.connect(_on_turn_changed)
	GameManager.combat_occurred.connect(_on_combat_occurred)
	GameManager.game_ended.connect(_on_game_ended)
	setup_phase.setup_complete.connect(_on_setup_complete)
	turn_switch.acknowledged.connect(_on_turn_switch_acknowledged)
	combat_popup.closed.connect(_on_combat_popup_closed)
	game_over.play_again_pressed.connect(_on_play_again)

	# Create play controller
	play_controller = Node.new()
	play_controller.set_script(preload("res://scripts/ui/play_controller.gd"))
	add_child(play_controller)
	play_controller.setup(board)

	# Start game
	GameManager.start_game(GameManager.GameMode.LOCAL_2P)


func _on_phase_changed(phase: GameManager.GamePhase) -> void:
	match phase:
		GameManager.GamePhase.SETUP_RED:
			setup_phase.start_setup(PieceData.Team.RED)
		GameManager.GamePhase.SETUP_BLUE:
			# Show turn switch between Red setup and Blue setup
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
	if GameManager.game_mode == GameManager.GameMode.LOCAL_2P:
		# Show combat popup first if there was combat, then turn switch
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


func _on_combat_occurred(combat_info: Dictionary) -> void:
	_pending_combat = combat_info


func _on_game_ended(winner: PieceData.Team) -> void:
	board.refresh()
	if _pending_combat.size() > 0:
		# Show combat result first, then game over on close
		_waiting_for_combat_ack = false
		combat_popup.show_result(
			_pending_combat["atk_rank"],
			_pending_combat["def_rank"],
			_pending_combat["atk_team"],
			_pending_combat["result"],
		)
		_pending_combat.clear()
		# Game over will show after combat popup is closed
		_game_over_pending = true
	else:
		game_over.show_winner(winner)


func _on_turn_switch_acknowledged() -> void:
	# If this was between setups, start the next setup
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
		turn_switch.show_turn(GameManager.current_team)
	else:
		board.refresh()


func _on_play_again() -> void:
	GameManager.start_game(GameManager.game_mode)
