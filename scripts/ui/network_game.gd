extends ColorRect

signal back_pressed

@onready var connect_panel: VBoxContainer = %ConnectPanel
@onready var address_input: LineEdit = %AddressInput
@onready var port_input: SpinBox = %PortInput
@onready var connect_button: Button = %ConnectButton
@onready var network_back_button: Button = %NetworkBackButton
@onready var status_label: Label = %NetworkStatusLabel

var _client: Node = null
var _board: Control = null
var _my_team: PieceData.Team = PieceData.Team.RED
var _game_active: bool = false

# Local board state built from server updates
var _local_bs: BoardState = BoardState.new()
var _local_caps: Dictionary = {
	PieceData.Team.RED: [] as Array[PieceData.Rank],
	PieceData.Team.BLUE: [] as Array[PieceData.Rank],
}
var _current_team: PieceData.Team = PieceData.Team.RED
var _phase: String = "waiting"
var _selected_rank: int = -1
var _placed_counts: Dictionary = {}


func _ready() -> void:
	connect_button.pressed.connect(_on_connect)
	network_back_button.pressed.connect(func() -> void:
		_disconnect()
		visible = false
		back_pressed.emit()
	)


func show_connect() -> void:
	connect_panel.visible = true
	status_label.text = "Enter server address"
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
	_client.setup_state_received.connect(_on_setup_state_received)
	_client.combat_occurred.connect(_on_combat_occurred)
	_client.game_ended.connect(_on_game_ended)
	_client.error_received.connect(_on_error)

	_client.connect_to_server(address, port)
	status_label.text = "Connecting to %s:%d..." % [address, port]
	connect_button.disabled = true


func _disconnect() -> void:
	if _client != null:
		_client.queue_free()
		_client = null
	_game_active = false
	connect_button.disabled = false


func _on_connected(team: PieceData.Team) -> void:
	_my_team = team
	status_label.text = "Connected as %s. Waiting for opponent..." % PieceData.get_team_name(team)


func _on_disconnected() -> void:
	status_label.text = "Disconnected from server."
	_disconnect()


func _on_phase_changed(phase: String) -> void:
	_phase = phase
	match phase:
		"setup_red":
			status_label.text = "Setup phase: Red is placing pieces"
			if _my_team == PieceData.Team.RED:
				status_label.text = "Your turn to place pieces. Use Randomize or place manually."
		"setup_blue":
			status_label.text = "Setup phase: Blue is placing pieces"
			if _my_team == PieceData.Team.BLUE:
				status_label.text = "Your turn to place pieces. Use Randomize or place manually."
		"play":
			status_label.text = "Game started!"
			_game_active = true
		"game_over":
			_game_active = false


func _on_turn_changed(team: PieceData.Team) -> void:
	_current_team = team
	if team == _my_team:
		status_label.text = "Your turn"
	else:
		status_label.text = "Opponent's turn"


func _on_state_updated(pieces: Array, current_team: PieceData.Team, captured_red: Array, captured_blue: Array) -> void:
	_current_team = current_team
	_rebuild_local_state(pieces, captured_red, captured_blue)


func _on_setup_state_received(pieces: Array) -> void:
	# Update local view of our setup pieces
	_placed_counts.clear()
	for rank: int in PieceData.RANK_INFO:
		_placed_counts[rank] = 0
	for p: Dictionary in pieces:
		_placed_counts[int(p["rank"])] += 1


func _on_combat_occurred(info: Dictionary) -> void:
	pass  # TODO: trigger combat animation


func _on_game_ended(winner: PieceData.Team, reason: String) -> void:
	var winner_name: String = PieceData.get_team_name(winner)
	if winner == _my_team:
		status_label.text = "You win! (%s)" % reason
	else:
		status_label.text = "%s wins. (%s)" % [winner_name, reason]


func _on_error(message: String) -> void:
	status_label.text = "Error: %s" % message


func _rebuild_local_state(pieces: Array, captured_red: Array, captured_blue: Array) -> void:
	_local_bs.reset()
	for p: Dictionary in pieces:
		var rank: int = int(p["rank"])
		var piece_team: int = int(p["team"])
		var pos: Vector2i = Vector2i(int(p["x"]), int(p["y"]))
		var revealed: bool = p.get("revealed", false)
		if rank == -1:
			# Hidden enemy piece — use FLAG as placeholder rank (won't be displayed)
			rank = PieceData.Rank.FLAG
			revealed = false
		var pid: int = _local_bs.add_piece(rank, piece_team as PieceData.Team, pos)
		_local_bs.pieces[pid]["revealed"] = revealed
		# For own pieces, mark as revealed so they show rank
		if piece_team == _my_team:
			_local_bs.pieces[pid]["revealed"] = true

	_local_caps[PieceData.Team.RED].clear()
	for r: int in captured_red:
		_local_caps[PieceData.Team.RED].append(r)
	_local_caps[PieceData.Team.BLUE].clear()
	for r: int in captured_blue:
		_local_caps[PieceData.Team.BLUE].append(r)


# --- Input handling (called from main_scene or board) ---


func handle_square_click(pos: Vector2i) -> void:
	if _client == null:
		return

	if _phase == "setup_red" and _my_team == PieceData.Team.RED:
		_handle_setup_click(pos)
	elif _phase == "setup_blue" and _my_team == PieceData.Team.BLUE:
		_handle_setup_click(pos)
	elif _phase == "play" and _current_team == _my_team:
		_handle_play_click(pos)


func _handle_setup_click(pos: Vector2i) -> void:
	# Check if clicking existing piece to remove
	var existing: int = _local_bs.get_piece_at(pos)
	if existing != -1:
		_client.send_remove(pos)
		return

	if _selected_rank == -1:
		return
	_client.send_place(_selected_rank, pos)


func _handle_play_click(pos: Vector2i) -> void:
	# Simple: select piece, then click destination
	# TODO: integrate with board selection/highlighting
	pass


func send_randomize() -> void:
	if _client != null:
		_client.send_randomize()


func send_ready() -> void:
	if _client != null:
		_client.send_ready()


func send_placement_strategy(strategy: int) -> void:
	if _client != null:
		_client.send_placement_strategy(strategy)


func send_move(from: Vector2i, to: Vector2i) -> void:
	if _client != null:
		_client.send_move(from, to)
