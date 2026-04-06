class_name NetworkController
extends RefCounted

# Handles network communication and state reconstruction.
# No UI, no rendering — just data flow between server and game.

var client: Node = null
var my_team: PieceData.Team = PieceData.Team.RED
var phase: String = "waiting"
var current_team: PieceData.Team = PieceData.Team.RED
var awaiting_own_move: bool = false
var pending_state: Dictionary = {}

var local_bs: BoardState = BoardState.new()
var local_caps: Dictionary = {
	PieceData.Team.RED: [] as Array[PieceData.Rank],
	PieceData.Team.BLUE: [] as Array[PieceData.Rank],
}

# Callbacks set by the UI layer
var on_connected: Callable  # (team: PieceData.Team)
var on_disconnected: Callable  # ()
var on_phase_changed: Callable  # (phase: String)
var on_turn_changed: Callable  # (team: PieceData.Team)
var on_state_updated: Callable  # ()
var on_move_made: Callable  # (move_team: PieceData.Team, from: Vector2i, to: Vector2i)
var on_combat: Callable  # (info: Dictionary)
var on_game_ended: Callable  # (winner: PieceData.Team, reason: String)
var on_error: Callable  # (message: String)


func connect_to_server(address: String, port: int, parent: Node) -> void:
	client = Node.new()
	client.set_script(load("res://scripts/network/client.gd"))
	parent.add_child(client)

	client.connected_to_server.connect(_on_connected)
	client.disconnected_from_server.connect(_on_disconnected)
	client.phase_changed.connect(_on_phase_changed)
	client.turn_changed.connect(_on_turn_changed)
	client.state_updated.connect(_on_state_updated)
	client.move_made.connect(_on_move_made)
	client.combat_occurred.connect(_on_combat)
	client.game_ended.connect(_on_game_ended)
	client.error_received.connect(_on_error)

	client.connect_to_server(address, port)


func disconnect_from_server() -> void:
	if client != null:
		client.queue_free()
		client = null


func send_move(from: Vector2i, to: Vector2i) -> void:
	awaiting_own_move = true
	client.send_move(from, to)


func send_placement(pieces: Array[Dictionary]) -> void:
	client._send({
		"type": "submit_placement",
		"pieces": pieces,
	})


func rebuild_state(pieces: Array, captured_red: Array, captured_blue: Array) -> void:
	local_bs.reset()
	for p: Dictionary in pieces:
		var rank: int = int(p["rank"])
		var piece_team: int = int(p["team"])
		var pos: Vector2i = Vector2i(int(p["x"]), int(p["y"]))
		var revealed: bool = p.get("revealed", false)
		if rank == -1:
			rank = PieceData.Rank.FLAG
			revealed = false
		var pid: int = local_bs.add_piece(rank, piece_team as PieceData.Team, pos)
		local_bs.pieces[pid]["revealed"] = revealed

	local_caps[PieceData.Team.RED].clear()
	for r: int in captured_red:
		local_caps[PieceData.Team.RED].append(r)
	local_caps[PieceData.Team.BLUE].clear()
	for r: int in captured_blue:
		local_caps[PieceData.Team.BLUE].append(r)


# --- Server message handlers (delegate to callbacks) ---


func _on_connected(team: PieceData.Team) -> void:
	my_team = team
	if on_connected != null:
		on_connected.call(team)


func _on_disconnected() -> void:
	if on_disconnected != null:
		on_disconnected.call()


func _on_phase_changed(p: String) -> void:
	phase = p
	if on_phase_changed != null:
		on_phase_changed.call(p)


func _on_turn_changed(team: PieceData.Team) -> void:
	current_team = team
	if on_turn_changed != null:
		on_turn_changed.call(team)


func _on_state_updated(pieces: Array, ct: PieceData.Team, captured_red: Array, captured_blue: Array) -> void:
	pending_state = {
		"pieces": pieces,
		"current_team": ct,
		"captured_red": captured_red,
		"captured_blue": captured_blue,
	}
	if on_state_updated != null:
		on_state_updated.call()


func _on_move_made(move_team: PieceData.Team, from: Vector2i, to: Vector2i) -> void:
	if move_team == my_team:
		awaiting_own_move = false
	if on_move_made != null:
		on_move_made.call(move_team, from, to)


func _on_combat(info: Dictionary) -> void:
	if on_combat != null:
		on_combat.call(info)


func _on_game_ended(winner: PieceData.Team, reason: String) -> void:
	phase = "game_over"
	if on_game_ended != null:
		on_game_ended.call(winner, reason)


func _on_error(message: String) -> void:
	if on_error != null:
		on_error.call(message)


func apply_pending_state() -> void:
	if pending_state.size() == 0:
		return
	current_team = pending_state["current_team"]
	rebuild_state(pending_state["pieces"], pending_state["captured_red"], pending_state["captured_blue"])
	pending_state.clear()
