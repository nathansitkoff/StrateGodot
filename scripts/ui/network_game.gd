extends ColorRect

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

var _client: Node = null
var _my_team: PieceData.Team = PieceData.Team.RED
var _phase: String = "waiting"
var _current_team: PieceData.Team = PieceData.Team.RED
var _awaiting_own_move: bool = false
var _pending_state: Dictionary = {}

var _local_bs: BoardState = BoardState.new()
var _local_caps: Dictionary = {
	PieceData.Team.RED: [] as Array[PieceData.Rank],
	PieceData.Team.BLUE: [] as Array[PieceData.Rank],
}


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

	_client = Node.new()
	_client.set_script(load("res://scripts/network/client.gd"))
	add_child(_client)

	_client.connected_to_server.connect(_on_connected)
	_client.disconnected_from_server.connect(_on_disconnected)
	_client.phase_changed.connect(_on_phase_changed)
	_client.turn_changed.connect(_on_turn_changed)
	_client.state_updated.connect(_on_state_updated)
	_client.move_made.connect(_on_move_made)
	_client.combat_occurred.connect(_on_combat)
	_client.game_ended.connect(_on_game_ended)
	_client.error_received.connect(_on_error)

	_client.connect_to_server(address, port)
	status_label.text = "Connecting to %s:%d..." % [address, port]
	connect_button.disabled = true


func _cleanup() -> void:
	if _client != null:
		_client.queue_free()
		_client = null
	setup_phase.visible = false
	# Reconnect main_scene's setup handler
	if main_scene != null and not setup_phase.setup_complete.is_connected(main_scene._on_setup_complete):
		setup_phase.setup_complete.connect(main_scene._on_setup_complete)
	# Disconnect our handler
	if setup_phase.setup_complete.is_connected(_on_setup_complete):
		setup_phase.setup_complete.disconnect(_on_setup_complete)
	_hide_game_ui()
	connect_button.disabled = false
	mouse_filter = Control.MOUSE_FILTER_STOP


func _show_game_ui() -> void:
	board.visible = true
	left_hud.visible = true
	hud.visible = true
	turn_bar.visible = true
	board.set_game_layout()
	GameManager.board_state = _local_bs
	GameManager.captured_pieces = _local_caps
	GameManager.game_mode = GameManager.GameMode.LOCAL_2P
	GameManager.current_team = _my_team
	left_hud.update_remaining(PieceData.Team.RED)
	hud.update_enemy_remaining(_my_team)
	board.refresh()


func _hide_game_ui() -> void:
	left_hud.visible = false
	hud.visible = false
	turn_bar.visible = false
	board.reset_layout()


func _update_board() -> void:
	GameManager.board_state = _local_bs
	GameManager.captured_pieces = _local_caps
	GameManager.current_team = _my_team
	left_hud.update_remaining(PieceData.Team.RED)
	hud.update_enemy_remaining(_my_team)
	board.clear_selection()
	board.refresh()


func _update_turn_label() -> void:
	var name: String = PieceData.get_team_name(_current_team)
	var c: Color = VisualConfig.get_team_color(_current_team)
	if _current_team == _my_team:
		turn_label.text = "Your Turn (%s)" % name
	else:
		turn_label.text = "Opponent's Turn (%s)" % name
	turn_label.add_theme_color_override("font_color", c)


# --- Server message handlers ---


func _on_connected(team: PieceData.Team) -> void:
	_my_team = team
	status_label.text = "Connected as %s. Waiting for opponent..." % PieceData.get_team_name(team)


func _on_disconnected() -> void:
	if _phase == "game_over":
		return
	status_label.text = "Disconnected from server."
	setup_phase.visible = false
	connect_panel.visible = true
	connect_button.visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	color = VisualConfig.MENU_BACKGROUND
	if _client != null:
		_client.queue_free()
		_client = null


func _on_phase_changed(phase: String) -> void:
	_phase = phase
	match phase:
		"setup":
			# Hide network overlay, show normal setup phase
			visible = false
			# Disconnect main_scene's setup handler so it doesn't trigger turn switches
			if setup_phase.setup_complete.is_connected(main_scene._on_setup_complete):
				setup_phase.setup_complete.disconnect(main_scene._on_setup_complete)
			# Use the standard setup UI — placement is fully local
			GameManager.board_state.reset()
			GameManager.current_phase = GameManager.GamePhase.SETUP_RED if _my_team == PieceData.Team.RED else GameManager.GamePhase.SETUP_BLUE
			setup_phase.start_setup(_my_team)
			# Connect our setup_complete handler
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
			# Configure controller for network play
			game_ctrl.get_board_state = func() -> BoardState: return _local_bs
			game_ctrl.get_my_team = func() -> PieceData.Team: return _my_team
			game_ctrl.is_my_turn = func() -> bool: return _phase == "play" and _current_team == _my_team
			game_ctrl.on_move = _do_network_move
		"game_over":
			pass


func _on_setup_complete(_team: PieceData.Team) -> void:
	# Send full placement to server
	if _client == null:
		return
	var pieces: Array[Dictionary] = []
	for piece_id: int in GameManager.board_state.pieces:
		var p: Dictionary = GameManager.board_state.pieces[piece_id]
		if p["team"] == _my_team:
			pieces.append({
				"rank": p["rank"],
				"x": p["pos"].x,
				"y": p["pos"].y,
			})
	_client._send({
		"type": "submit_placement",
		"pieces": pieces,
	})
	# Show waiting message in turn bar, keep pieces visible
	setup_phase.visible = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Keep the current board state (has our placed pieces) for display
	# Don't swap to _local_bs yet — that happens when play starts
	board.visible = true
	left_hud.visible = true
	hud.visible = true
	turn_bar.visible = true
	board.set_game_layout()
	board.refresh()
	turn_label.text = "Waiting for opponent to finish placing..."
	turn_label.add_theme_color_override("font_color", VisualConfig.TEAM_NEUTRAL)


func _on_turn_changed(team: PieceData.Team) -> void:
	_current_team = team
	game_ctrl.clear_selection()
	_update_turn_label()


func _on_state_updated(pieces: Array, current_team: PieceData.Team, captured_red: Array, captured_blue: Array) -> void:
	_pending_state = {
		"pieces": pieces,
		"current_team": current_team,
		"captured_red": captured_red,
		"captured_blue": captured_blue,
	}
	if board._anim_progress < 1.0 or board._combat_anim_state != board.CombatAnimState.NONE:
		if not board.move_ready.is_connected(_apply_pending_state):
			board.move_ready.connect(_apply_pending_state, CONNECT_ONE_SHOT)
	else:
		_apply_pending_state_now()


func _apply_pending_state(_from: Vector2i = Vector2i.ZERO, _to: Vector2i = Vector2i.ZERO) -> void:
	_apply_pending_state_now()


func _apply_pending_state_now() -> void:
	if _pending_state.size() == 0:
		return
	_current_team = _pending_state["current_team"]
	_rebuild_state(_pending_state["pieces"], _pending_state["captured_red"], _pending_state["captured_blue"])
	_pending_state = {}
	_update_board()
	_update_turn_label()


func _on_move_made(move_team: PieceData.Team, from: Vector2i, to: Vector2i) -> void:
	var piece_id: int = _local_bs.get_piece_at(from)
	if piece_id != -1:
		board.animate_move_with_combat(piece_id, from, to)
	if move_team == _my_team:
		_awaiting_own_move = false


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
	_phase = "game_over"
	if winner == _my_team:
		turn_label.text = "You win! (%s) — Press Escape to exit" % reason
	else:
		turn_label.text = "%s wins. (%s) — Press Escape to exit" % [PieceData.get_team_name(winner), reason]
	var c: Color = VisualConfig.get_team_color(winner)
	turn_label.add_theme_color_override("font_color", c)


func _on_error(message: String) -> void:
	status_label.text = "Error: %s" % message


# --- Board interaction ---


func _do_network_move(from: Vector2i, to: Vector2i) -> void:
	_awaiting_own_move = true
	_client.send_move(from, to)


# --- State reconstruction ---


func _rebuild_state(pieces: Array, captured_red: Array, captured_blue: Array) -> void:
	_local_bs.reset()
	for p: Dictionary in pieces:
		var rank: int = int(p["rank"])
		var piece_team: int = int(p["team"])
		var pos: Vector2i = Vector2i(int(p["x"]), int(p["y"]))
		var revealed: bool = p.get("revealed", false)
		if rank == -1:
			rank = PieceData.Rank.FLAG
			revealed = false
		var pid: int = _local_bs.add_piece(rank, piece_team as PieceData.Team, pos)
		_local_bs.pieces[pid]["revealed"] = revealed

	_local_caps[PieceData.Team.RED].clear()
	for r: int in captured_red:
		_local_caps[PieceData.Team.RED].append(r)
	_local_caps[PieceData.Team.BLUE].clear()
	for r: int in captured_blue:
		_local_caps[PieceData.Team.BLUE].append(r)
