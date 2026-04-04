extends ColorRect

signal back_pressed

@onready var connect_panel: VBoxContainer = %ConnectPanel
@onready var address_input: LineEdit = %AddressInput
@onready var port_input: SpinBox = %PortInput
@onready var connect_button: Button = %ConnectButton
@onready var setup_row: HBoxContainer = %SetupRow
@onready var randomize_button: Button = %RandomizeButton
@onready var ready_button: Button = %ReadyButton
@onready var network_back_button: Button = %NetworkBackButton
@onready var status_label: Label = %NetworkStatusLabel

# References set by main_scene
var board: Control = null
var left_hud: PanelContainer = null
var hud: PanelContainer = null
var turn_bar: PanelContainer = null
var turn_label: Label = null

var _client: Node = null
var _my_team: PieceData.Team = PieceData.Team.RED
var _phase: String = "waiting"
var _current_team: PieceData.Team = PieceData.Team.RED
var _selected_piece_id: int = -1

var _local_bs: BoardState = BoardState.new()
var _local_caps: Dictionary = {
	PieceData.Team.RED: [] as Array[PieceData.Rank],
	PieceData.Team.BLUE: [] as Array[PieceData.Rank],
}
var _setup_pieces: Array = []


func _ready() -> void:
	connect_button.pressed.connect(_on_connect)
	randomize_button.pressed.connect(_on_randomize)
	ready_button.pressed.connect(_on_ready)
	network_back_button.pressed.connect(func() -> void:
		_cleanup()
		visible = false
		back_pressed.emit()
	)


func setup_refs(b: Control, lh: PanelContainer, h: PanelContainer, tb: PanelContainer, tl: Label) -> void:
	board = b
	left_hud = lh
	hud = h
	turn_bar = tb
	turn_label = tl


func show_connect() -> void:
	connect_panel.visible = true
	connect_button.visible = true
	setup_row.visible = false
	status_label.text = "Enter server address"
	connect_button.disabled = false
	color = Color(0.15, 0.15, 0.2, 1)
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
	_client.setup_state_received.connect(_on_setup_state)
	_client.combat_occurred.connect(_on_combat)
	_client.game_ended.connect(_on_game_ended)
	_client.error_received.connect(_on_error)

	_client.connect_to_server(address, port)
	status_label.text = "Connecting to %s:%d..." % [address, port]
	connect_button.disabled = true


func _on_randomize() -> void:
	if _client != null:
		_client.send_randomize()


func _on_ready() -> void:
	if _client != null:
		_client.send_ready()
		ready_button.disabled = true
		status_label.text = "Waiting for opponent..."


func _cleanup() -> void:
	if _client != null:
		_client.queue_free()
		_client = null
	_hide_game_ui()
	connect_button.disabled = false


func _show_game_ui() -> void:
	board.visible = true
	left_hud.visible = true
	hud.visible = true
	turn_bar.visible = true
	board.offset_left = 220
	board.offset_top = 36
	GameManager.board_state = _local_bs
	GameManager.captured_pieces = _local_caps
	GameManager.game_mode = GameManager.GameMode.LOCAL_2P  # use current_team for viewing
	GameManager.current_team = _my_team
	left_hud.update_remaining(PieceData.Team.RED)
	hud.update_enemy_remaining(_my_team)
	board.refresh()


func _hide_game_ui() -> void:
	left_hud.visible = false
	hud.visible = false
	turn_bar.visible = false
	board.offset_left = 0
	board.offset_top = 0


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
	var c: Color = Color(0.9, 0.3, 0.3) if _current_team == PieceData.Team.RED else Color(0.3, 0.4, 0.9)
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
	status_label.text = "Disconnected from server."
	_cleanup()
	show_connect()


func _on_phase_changed(phase: String) -> void:
	_phase = phase
	match phase:
		"setup":
			# Both players place simultaneously
			connect_button.visible = false
			setup_row.visible = true
			ready_button.disabled = false
			status_label.text = "Place your pieces: Randomize, then Ready"
			# Show board, make click-through
			color = Color(0, 0, 0, 0)
			mouse_filter = Control.MOUSE_FILTER_IGNORE
			_show_game_ui()
			GameManager.current_phase = GameManager.GamePhase.SETUP_RED if _my_team == PieceData.Team.RED else GameManager.GamePhase.SETUP_BLUE
			turn_label.text = "Setup — %s" % PieceData.get_team_name(_my_team)
			turn_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3) if _my_team == PieceData.Team.RED else Color(0.3, 0.4, 0.9))
		"play":
			setup_row.visible = false
			connect_panel.visible = false
			# Keep phase as MENU so play_controller doesn't intercept clicks
			GameManager.current_phase = GameManager.GamePhase.MENU
			# Make ourselves transparent and click-through
			color = Color(0, 0, 0, 0)
			mouse_filter = Control.MOUSE_FILTER_IGNORE
			_show_game_ui()
			_update_turn_label()
			if not board.square_clicked.is_connected(_on_board_click):
				board.square_clicked.connect(_on_board_click)
			if not board.move_ready.is_connected(_on_move_ready):
				board.move_ready.connect(_on_move_ready)
		"game_over":
			pass


func _on_turn_changed(team: PieceData.Team) -> void:
	_current_team = team
	_selected_piece_id = -1
	board.clear_selection()
	_update_turn_label()


func _on_state_updated(pieces: Array, current_team: PieceData.Team, captured_red: Array, captured_blue: Array) -> void:
	_current_team = current_team
	_rebuild_state(pieces, captured_red, captured_blue)
	_update_board()
	_update_turn_label()


func _on_setup_state(pieces: Array) -> void:
	_setup_pieces = pieces
	_local_bs.reset()
	for p: Dictionary in pieces:
		var pid: int = _local_bs.add_piece(int(p["rank"]), int(p["team"]) as PieceData.Team, Vector2i(int(p["x"]), int(p["y"])))
		_local_bs.pieces[pid]["revealed"] = true
	GameManager.board_state = _local_bs
	GameManager.captured_pieces = _local_caps
	board.refresh()


func _on_combat(info: Dictionary) -> void:
	if board.visible:
		hud.show_combat_result(
			int(info["atk_rank"]) as PieceData.Rank,
			int(info["def_rank"]) as PieceData.Rank,
			int(info["atk_team"]) as PieceData.Team,
			int(info["result"]) as Combat.Result,
		)


func _on_game_ended(winner: PieceData.Team, reason: String) -> void:
	if winner == _my_team:
		turn_label.text = "You win! (%s)" % reason
	else:
		turn_label.text = "%s wins. (%s)" % [PieceData.get_team_name(winner), reason]


func _on_error(message: String) -> void:
	status_label.text = "Error: %s" % message


# --- Board interaction ---


func _on_board_click(pos: Vector2i) -> void:
	if _phase != "play" or _current_team != _my_team:
		return

	var clicked_id: int = _local_bs.get_piece_at(pos)

	if _selected_piece_id != -1:
		var selected: Dictionary = _local_bs.pieces.get(_selected_piece_id, {})

		if clicked_id == _selected_piece_id:
			board.clear_selection()
			_selected_piece_id = -1
			return

		if pos in board.valid_moves:
			var from: Vector2i = selected["pos"]
			var piece_id: int = _selected_piece_id
			board.clear_selection()
			_selected_piece_id = -1
			board.animate_move_with_combat(piece_id, from, pos)
			return

		if clicked_id != -1:
			var clicked: Dictionary = _local_bs.pieces[clicked_id]
			if clicked["team"] == _my_team and PieceData.can_move(clicked["rank"]):
				_selected_piece_id = clicked_id
				board.select_piece(clicked_id)
				return

		board.clear_selection()
		_selected_piece_id = -1
		return

	if clicked_id != -1:
		var piece: Dictionary = _local_bs.pieces[clicked_id]
		if piece["team"] == _my_team and PieceData.can_move(piece["rank"]):
			_selected_piece_id = clicked_id
			board.select_piece(clicked_id)


func _on_move_ready(from: Vector2i, to: Vector2i) -> void:
	if _client != null and _phase == "play":
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
		if piece_team == _my_team:
			_local_bs.pieces[pid]["revealed"] = true

	_local_caps[PieceData.Team.RED].clear()
	for r: int in captured_red:
		_local_caps[PieceData.Team.RED].append(r)
	_local_caps[PieceData.Team.BLUE].clear()
	for r: int in captured_blue:
		_local_caps[PieceData.Team.BLUE].append(r)
