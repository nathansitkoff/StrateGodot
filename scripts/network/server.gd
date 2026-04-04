extends Node

# WebSocket server for network Stratego.
# Uses TCPServer + WebSocketPeer for direct packet control.

const Proto: GDScript = preload("res://scripts/network/protocol.gd")

var _tcp_server: TCPServer = TCPServer.new()
var _peers: Dictionary = {}  # id -> { "ws": WebSocketPeer, "team": Team, "ready": bool }
var _next_peer_id: int = 1
var _board_state: BoardState = BoardState.new()
var _captured: Dictionary = {
	PieceData.Team.RED: [] as Array[PieceData.Rank],
	PieceData.Team.BLUE: [] as Array[PieceData.Rank],
}
var _current_team: PieceData.Team = PieceData.Team.RED
var _phase: String = "waiting"
var _recorder: GameRecorder = null


func start(port: int) -> void:
	var err: int = _tcp_server.listen(port)
	if err != OK:
		push_error("Failed to listen on port %d: %d" % [port, err])
		return
	print("Listening on port %d" % port)


func _process(_delta: float) -> void:
	# Accept new TCP connections
	while _tcp_server.is_connection_available():
		var tcp: StreamPeerTCP = _tcp_server.take_connection()
		var ws: WebSocketPeer = WebSocketPeer.new()
		ws.accept_stream(tcp)
		var peer_id: int = _next_peer_id
		_next_peer_id += 1
		_peers[peer_id] = { "ws": ws, "team": -1, "ready": false }
		print("New connection: peer %d" % peer_id)

	# Poll all peers
	var to_remove: Array[int] = []
	for peer_id: int in _peers:
		var ws: WebSocketPeer = _peers[peer_id]["ws"]
		ws.poll()

		var state: int = ws.get_ready_state()
		if state == WebSocketPeer.STATE_OPEN:
			# Assign team if not yet assigned
			if _peers[peer_id]["team"] == -1:
				_assign_team(peer_id)

			while ws.get_available_packet_count() > 0:
				var packet: PackedByteArray = ws.get_packet()
				var text: String = packet.get_string_from_utf8()
				var msg: Dictionary = Proto.decode(text)
				if msg.size() > 0:
					_handle_message(peer_id, msg)

		elif state == WebSocketPeer.STATE_CLOSING:
			pass
		elif state == WebSocketPeer.STATE_CLOSED:
			print("Peer %d disconnected" % peer_id)
			_on_peer_disconnected(peer_id)
			to_remove.append(peer_id)

	for peer_id: int in to_remove:
		_peers.erase(peer_id)


func _assign_team(peer_id: int) -> void:
	if _get_player_count() >= 2:
		_send(peer_id, { "type": Proto.ERROR, "message": "Server full" })
		return

	var has_red: bool = false
	for pid: int in _peers:
		if _peers[pid]["team"] == PieceData.Team.RED:
			has_red = true

	var team: PieceData.Team = PieceData.Team.BLUE if has_red else PieceData.Team.RED
	_peers[peer_id]["team"] = team
	_send(peer_id, { "type": Proto.ASSIGN_TEAM, "team": team })
	print("Assigned %s to peer %d" % [PieceData.get_team_name(team), peer_id])

	if _get_player_count() == 2:
		_start_game()


func _get_player_count() -> int:
	var count: int = 0
	for pid: int in _peers:
		if _peers[pid]["team"] != -1:
			count += 1
	return count


func _on_peer_disconnected(peer_id: int) -> void:
	if _peers[peer_id]["team"] == -1:
		return
	var team_name: String = PieceData.get_team_name(_peers[peer_id]["team"])
	print("%s disconnected" % team_name)
	if _phase == "play":
		var winner: PieceData.Team = PieceData.Team.RED
		for pid: int in _peers:
			if pid != peer_id and _peers[pid]["team"] != -1:
				winner = _peers[pid]["team"]
		_end_game(winner, "disconnect")


func _start_game() -> void:
	print("Both players connected. Starting game.")
	_board_state.reset()
	_captured[PieceData.Team.RED].clear()
	_captured[PieceData.Team.BLUE].clear()

	_recorder = GameRecorder.new()
	_recorder.start_recording("Network", "Human", "Human", PieceData.Team.RED)

	_phase = "setup_red"
	_broadcast({ "type": Proto.PHASE_CHANGE, "phase": "setup_red" })
	_send_setup_state_to_team(PieceData.Team.RED)


func _handle_message(peer_id: int, msg: Dictionary) -> void:
	if _peers[peer_id]["team"] == -1:
		return
	var team: PieceData.Team = _peers[peer_id]["team"]

	match msg.get("type", ""):
		Proto.PLACE:
			_handle_place(team, msg)
		Proto.REMOVE_PIECE:
			_handle_remove(team, msg)
		Proto.READY:
			_handle_ready(team)
		Proto.MOVE:
			_handle_move(team, msg)
		Proto.RANDOMIZE:
			_handle_randomize(team)
		Proto.PLACEMENT_STRATEGY:
			_handle_placement_strategy(team, msg)


func _handle_place(team: PieceData.Team, msg: Dictionary) -> void:
	if not _is_setup_turn(team):
		return
	var rank: int = int(msg.get("rank", 0))
	var pos: Vector2i = Vector2i(int(msg.get("x", 0)), int(msg.get("y", 0)))
	var valid_rows: Array[int] = _board_state.get_setup_rows(team)

	if pos.y not in valid_rows or not _board_state.is_valid_cell(pos):
		return
	if _board_state.get_piece_at(pos) != -1:
		return

	var placed_count: int = 0
	for pid: int in _board_state.pieces:
		var p: Dictionary = _board_state.pieces[pid]
		if p["team"] == team and p["rank"] == rank:
			placed_count += 1
	if placed_count >= PieceData.RANK_INFO[rank]["count"]:
		return

	_board_state.add_piece(rank, team, pos)
	_send_setup_state_to_team(team)


func _handle_remove(team: PieceData.Team, msg: Dictionary) -> void:
	if not _is_setup_turn(team):
		return
	var pos: Vector2i = Vector2i(int(msg.get("x", 0)), int(msg.get("y", 0)))
	var piece_id: int = _board_state.get_piece_at(pos)
	if piece_id == -1 or _board_state.pieces[piece_id]["team"] != team:
		return
	_board_state.remove_piece(piece_id)
	_send_setup_state_to_team(team)


func _handle_randomize(team: PieceData.Team) -> void:
	if not _is_setup_turn(team):
		return
	_clear_team_pieces(team)
	Placement.place(Placement.Strategy.CLUSTERED_DEFENSE, _board_state, team)
	_send_setup_state_to_team(team)


func _handle_placement_strategy(team: PieceData.Team, msg: Dictionary) -> void:
	if not _is_setup_turn(team):
		return
	var strategy: int = int(msg.get("strategy", 0))
	_clear_team_pieces(team)
	Placement.place(strategy as Placement.Strategy, _board_state, team)
	_send_setup_state_to_team(team)


func _handle_ready(team: PieceData.Team) -> void:
	if not _is_setup_turn(team):
		return
	var count: int = 0
	for pid: int in _board_state.pieces:
		if _board_state.pieces[pid]["team"] == team:
			count += 1
	if count < PieceData.get_total_pieces():
		return

	if team == PieceData.Team.RED and _phase == "setup_red":
		_phase = "setup_blue"
		_broadcast({ "type": Proto.PHASE_CHANGE, "phase": "setup_blue" })
		_send_setup_state_to_team(PieceData.Team.BLUE)
	elif team == PieceData.Team.BLUE and _phase == "setup_blue":
		_recorder.record_placements_from_board(_board_state)
		_phase = "play"
		_current_team = PieceData.Team.RED
		_broadcast({ "type": Proto.PHASE_CHANGE, "phase": "play" })
		_send_game_state_to_all()
		_broadcast({ "type": Proto.TURN_CHANGE, "team": _current_team })


func _handle_move(team: PieceData.Team, msg: Dictionary) -> void:
	if _phase != "play" or team != _current_team:
		return

	var from: Vector2i = Vector2i(int(msg.get("from_x", 0)), int(msg.get("from_y", 0)))
	var to: Vector2i = Vector2i(int(msg.get("to_x", 0)), int(msg.get("to_y", 0)))

	if not GameManager.validate_move(from, to, _board_state):
		_send_to_team(team, { "type": Proto.ERROR, "message": "Invalid move" })
		return

	_recorder.record_move(from, to)
	var result: Dictionary = GameManager.apply_move(from, to, _board_state, _captured)
	_recorder.record_checksum(_board_state)

	if result["combat"]:
		var info: Dictionary = result["combat_info"]
		# Convert enums to ints for JSON
		_broadcast({
			"type": Proto.COMBAT,
			"atk_rank": info["atk_rank"],
			"def_rank": info["def_rank"],
			"atk_team": info["atk_team"],
			"def_team": info["def_team"],
			"result": info["result"],
			"pos_x": info["pos"].x,
			"pos_y": info["pos"].y,
		})

	if result.get("flag_captured", false):
		_end_game(result["winner"], "flag_captured")
		return

	_current_team = PieceData.Team.BLUE if _current_team == PieceData.Team.RED else PieceData.Team.RED
	if not _board_state.has_movable_pieces(_current_team):
		var winner: PieceData.Team = PieceData.Team.BLUE if _current_team == PieceData.Team.RED else PieceData.Team.RED
		_end_game(winner, "opponent_stuck")
		return

	_send_game_state_to_all()
	_broadcast({ "type": Proto.TURN_CHANGE, "team": _current_team })


func _end_game(winner: PieceData.Team, reason: String) -> void:
	_phase = "game_over"
	_broadcast({ "type": Proto.GAME_OVER, "winner": winner, "reason": reason })

	if _recorder != null:
		_recorder.finish_recording(reason, winner, _recorder.get_total_moves())
		DirAccess.make_dir_recursive_absolute("user://replays")
		_recorder.save_to_file(GameRecorder.generate_filename("Network", "Human", "Human"))
		print("Replay saved.")

	print("Game over: %s wins (%s)" % [PieceData.get_team_name(winner), reason])


# --- Helpers ---


func _is_setup_turn(team: PieceData.Team) -> bool:
	return (team == PieceData.Team.RED and _phase == "setup_red") or \
		   (team == PieceData.Team.BLUE and _phase == "setup_blue")


func _clear_team_pieces(team: PieceData.Team) -> void:
	var to_remove: Array[int] = []
	for pid: int in _board_state.pieces:
		if _board_state.pieces[pid]["team"] == team:
			to_remove.append(pid)
	for pid: int in to_remove:
		_board_state.remove_piece(pid)


func _send_setup_state_to_team(team: PieceData.Team) -> void:
	var pieces: Array[Dictionary] = []
	for pid: int in _board_state.pieces:
		var p: Dictionary = _board_state.pieces[pid]
		if p["team"] == team:
			pieces.append({ "id": pid, "rank": p["rank"], "team": p["team"], "x": p["pos"].x, "y": p["pos"].y })
	_send_to_team(team, { "type": Proto.SETUP_STATE, "pieces": pieces })


func _send_game_state_to_all() -> void:
	for peer_id: int in _peers:
		if _peers[peer_id]["team"] == -1:
			continue
		var team: PieceData.Team = _peers[peer_id]["team"]
		var pieces: Array[Dictionary] = []
		for pid: int in _board_state.pieces:
			var p: Dictionary = _board_state.pieces[pid]
			var pd: Dictionary = {
				"id": pid, "team": p["team"],
				"x": p["pos"].x, "y": p["pos"].y,
				"revealed": p["revealed"],
			}
			if p["team"] == team or p["revealed"]:
				pd["rank"] = p["rank"]
			else:
				pd["rank"] = -1
			pieces.append(pd)
		_send(peer_id, {
			"type": Proto.STATE_UPDATE,
			"pieces": pieces,
			"current_team": _current_team,
			"captured_red": _captured[PieceData.Team.RED],
			"captured_blue": _captured[PieceData.Team.BLUE],
		})


func _send(peer_id: int, msg: Dictionary) -> void:
	var ws: WebSocketPeer = _peers[peer_id]["ws"]
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send_text(Proto.encode(msg))


func _send_to_team(team: PieceData.Team, msg: Dictionary) -> void:
	for peer_id: int in _peers:
		if _peers[peer_id]["team"] == team:
			_send(peer_id, msg)


func _broadcast(msg: Dictionary) -> void:
	for peer_id: int in _peers:
		if _peers[peer_id]["team"] != -1:
			_send(peer_id, msg)
