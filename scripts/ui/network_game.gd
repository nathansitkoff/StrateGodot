extends ColorRect

const NetworkControllerClass: GDScript = preload("res://scripts/network/network_controller.gd")
const UIH: GDScript = preload("res://scripts/ui/ui_helpers.gd")

signal back_pressed

@onready var connect_panel: VBoxContainer = %ConnectPanel
@onready var address_input: LineEdit = %AddressInput
@onready var port_input: SpinBox = %PortInput
@onready var connect_button: Button = %ConnectButton
@onready var network_back_button: Button = %NetworkBackButton
@onready var status_label: Label = %NetworkStatusLabel

# References set by main_scene
var board: Control = null
var left_hud: PanelContainer = null
var hud: PanelContainer = null
var turn_bar: PanelContainer = null
var turn_label: Label = null
var setup_phase: Control = null
var main_scene: Control = null
var game_ctrl: Node = null

var _net: RefCounted = null


func _ready() -> void:
	connect_button.pressed.connect(_on_connect)
	network_back_button.pressed.connect(func() -> void:
		_cleanup()
		visible = false
		back_pressed.emit()
	)


func setup_refs(b: Control, lh: PanelContainer, h: PanelContainer, tb: PanelContainer, tl: Label, sp: Control, ms: Control, gc: Node) -> void:
	board = b
	left_hud = lh
	hud = h
	turn_bar = tb
	turn_label = tl
	setup_phase = sp
	main_scene = ms
	game_ctrl = gc


func show_connect() -> void:
	connect_panel.visible = true
	connect_button.visible = true
	connect_button.disabled = false
	status_label.text = "Enter server address"
	color = VisualConfig.MENU_BACKGROUND
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = true


func _on_connect() -> void:
	var address: String = address_input.text.strip_edges()
	if address == "":
		address = "127.0.0.1"
	var port: int = int(port_input.value)

	_net = NetworkControllerClass.new()
	_net.on_connected = _on_connected
	_net.on_disconnected = _on_disconnected
	_net.on_phase_changed = _on_phase_changed
	_net.on_turn_changed = _on_turn_changed
	_net.on_state_updated = _on_state_updated
	_net.on_move_made = _on_move_made
	_net.on_combat = _on_combat
	_net.on_game_ended = _on_game_ended
	_net.on_error = _on_error

	_net.connect_to_server(address, port, self)
	status_label.text = "Connecting to %s:%d..." % [address, port]
	connect_button.disabled = true


func _cleanup() -> void:
	if _net != null:
		_net.disconnect_from_server()
		_net = null
	setup_phase.visible = false
	if main_scene != null and not setup_phase.setup_complete.is_connected(main_scene._on_setup_complete):
		setup_phase.setup_complete.connect(main_scene._on_setup_complete)
	if setup_phase.setup_complete.is_connected(_on_setup_complete):
		setup_phase.setup_complete.disconnect(_on_setup_complete)
	_hide_game_ui()
	connect_button.disabled = false
	mouse_filter = Control.MOUSE_FILTER_STOP


func _show_game_ui() -> void:
	UIH.show_game_ui(board, left_hud, hud, turn_bar)
	GameManager.board_state = _net.local_bs
	GameManager.captured_pieces = _net.local_caps
	GameManager.game_mode = GameManager.GameMode.LOCAL_2P
	GameManager.current_team = _net.my_team
	UIH.update_remaining(left_hud, hud, _net.my_team)
	board.refresh()


func _hide_game_ui() -> void:
	UIH.hide_game_ui(left_hud, hud, turn_bar, board)


func _update_board() -> void:
	GameManager.board_state = _net.local_bs
	GameManager.captured_pieces = _net.local_caps
	GameManager.current_team = _net.my_team
	UIH.update_remaining(left_hud, hud, _net.my_team)
	board.clear_selection()
	board.refresh()


func _update_turn_label() -> void:
	var team_name: String = PieceData.get_team_name(_net.current_team)
	var text: String
	if _net.current_team == _net.my_team:
		text = "Your Turn (%s)" % team_name
	else:
		text = "Opponent's Turn (%s)" % team_name
	UIH.update_turn_label(turn_label, _net.current_team, text)


# --- Callbacks from NetworkController ---


func _on_connected(team: PieceData.Team) -> void:
	status_label.text = "Connected as %s. Waiting for opponent..." % PieceData.get_team_name(team)


func _on_disconnected() -> void:
	if _net != null and _net.phase == "game_over":
		return
	status_label.text = "Disconnected from server."
	setup_phase.visible = false
	connect_panel.visible = true
	connect_button.visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	color = VisualConfig.MENU_BACKGROUND
	if _net != null:
		_net.disconnect_from_server()


func _on_phase_changed(phase: String) -> void:
	match phase:
		"setup":
			visible = false
			if setup_phase.setup_complete.is_connected(main_scene._on_setup_complete):
				setup_phase.setup_complete.disconnect(main_scene._on_setup_complete)
			GameManager.board_state.reset()
			GameManager.current_phase = GameManager.GamePhase.SETUP_RED if _net.my_team == PieceData.Team.RED else GameManager.GamePhase.SETUP_BLUE
			setup_phase.start_setup(_net.my_team)
			if not setup_phase.setup_complete.is_connected(_on_setup_complete):
				setup_phase.setup_complete.connect(_on_setup_complete)
		"play":
			setup_phase.visible = false
			board.setup_valid_rows.clear()
			connect_panel.visible = false
			visible = false
			mouse_filter = Control.MOUSE_FILTER_IGNORE
			color = Color(0, 0, 0, 0)
			GameManager.current_phase = GameManager.GamePhase.MENU
			_show_game_ui()
			_update_turn_label()
			game_ctrl.get_board_state = func() -> BoardState: return _net.local_bs
			game_ctrl.get_my_team = func() -> PieceData.Team: return _net.my_team
			game_ctrl.is_my_turn = func() -> bool: return _net.phase == "play" and _net.current_team == _net.my_team
			game_ctrl.on_move = func(from: Vector2i, to: Vector2i) -> void: _net.send_move(from, to)


func _on_setup_complete(_team: PieceData.Team) -> void:
	if _net == null:
		return
	var pieces: Array[Dictionary] = []
	for piece_id: int in GameManager.board_state.pieces:
		var p: Dictionary = GameManager.board_state.pieces[piece_id]
		if p["team"] == _net.my_team:
			pieces.append({ "rank": p["rank"], "x": p["pos"].x, "y": p["pos"].y })
	_net.send_placement(pieces)
	setup_phase.visible = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.visible = true
	left_hud.visible = true
	hud.visible = true
	turn_bar.visible = true
	board.set_game_layout()
	board.refresh()
	turn_label.text = "Waiting for opponent to finish placing..."
	turn_label.add_theme_color_override("font_color", VisualConfig.TEAM_NEUTRAL)


func _on_turn_changed(team: PieceData.Team) -> void:
	game_ctrl.clear_selection()
	_update_turn_label()


func _on_state_updated() -> void:
	if board._anim_progress < 1.0 or board._combat_anim_state != board.CombatAnimState.NONE:
		if not board.move_ready.is_connected(_apply_pending_state):
			board.move_ready.connect(_apply_pending_state, CONNECT_ONE_SHOT)
	else:
		_apply_pending_state_now()


func _apply_pending_state(_from: Vector2i = Vector2i.ZERO, _to: Vector2i = Vector2i.ZERO) -> void:
	_apply_pending_state_now()


func _apply_pending_state_now() -> void:
	_net.apply_pending_state()
	_update_board()
	_update_turn_label()


func _on_move_made(move_team: PieceData.Team, from: Vector2i, to: Vector2i) -> void:
	var piece_id: int = _net.local_bs.get_piece_at(from)
	if piece_id != -1:
		board.animate_move_with_combat(piece_id, from, to)


func _on_combat(info: Dictionary) -> void:
	if int(info["def_rank"]) == PieceData.Rank.FLAG:
		board.flag_capture_pos = Vector2i(int(info["pos_x"]), int(info["pos_y"]))
	if board.visible:
		hud.show_combat_result(
			int(info["atk_rank"]) as PieceData.Rank,
			int(info["def_rank"]) as PieceData.Rank,
			int(info["atk_team"]) as PieceData.Team,
			int(info["result"]) as Combat.Result,
		)


func _on_game_ended(winner: PieceData.Team, reason: String) -> void:
	var text: String
	if winner == _net.my_team:
		text = "You win! (%s) — Press Escape to exit" % reason
	else:
		text = "%s wins. (%s) — Press Escape to exit" % [PieceData.get_team_name(winner), reason]
	UIH.update_turn_label(turn_label, winner, text)


func _on_error(message: String) -> void:
	status_label.text = "Error: %s" % message
