extends Node

# WebSocket client for network Stratego.

const Proto: GDScript = preload("res://scripts/network/protocol.gd")

signal connected_to_server(team: PieceData.Team)
signal disconnected_from_server
signal phase_changed(phase: String)
signal turn_changed(team: PieceData.Team)
signal state_updated(pieces: Array, current_team: PieceData.Team, captured_red: Array, captured_blue: Array)
signal combat_occurred(info: Dictionary)
signal move_made(team: PieceData.Team, from: Vector2i, to: Vector2i)
signal game_ended(winner: PieceData.Team, reason: String)
signal error_received(message: String)

var _ws: WebSocketPeer = WebSocketPeer.new()
var my_team: PieceData.Team = PieceData.Team.RED
var _is_connected: bool = false


func connect_to_server(address: String, port: int) -> void:
	var url: String = "ws://%s:%d" % [address, port]
	var err: int = _ws.connect_to_url(url)
	if err != OK:
		push_error("Failed to connect to %s: %d" % [url, err])
		return
	print("Connecting to %s..." % url)


func _process(_delta: float) -> void:
	_ws.poll()

	var state: int = _ws.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not _is_connected:
			_is_connected = true
			print("Connected to server")
		while _ws.get_available_packet_count() > 0:
			var text: String = _ws.get_packet().get_string_from_utf8()
			var msg: Dictionary = Proto.decode(text)
			if msg.size() > 0:
				_handle_message(msg)
	elif state == WebSocketPeer.STATE_CLOSED:
		if _is_connected:
			_is_connected = false
			print("Disconnected from server")
			disconnected_from_server.emit()


func _handle_message(msg: Dictionary) -> void:
	match msg.get("type", ""):
		Proto.ASSIGN_TEAM:
			my_team = int(msg["team"]) as PieceData.Team
			print("Assigned team: %s" % PieceData.get_team_name(my_team))
			connected_to_server.emit(my_team)
		Proto.PHASE_CHANGE:
			phase_changed.emit(msg["phase"])
		Proto.TURN_CHANGE:
			turn_changed.emit(int(msg["team"]) as PieceData.Team)
		Proto.STATE_UPDATE:
			state_updated.emit(
				msg["pieces"],
				int(msg["current_team"]) as PieceData.Team,
				msg["captured_red"],
				msg["captured_blue"],
			)
		Proto.MOVE_MADE:
			move_made.emit(
				int(msg["team"]) as PieceData.Team,
				Vector2i(int(msg["from_x"]), int(msg["from_y"])),
				Vector2i(int(msg["to_x"]), int(msg["to_y"])),
			)
		Proto.COMBAT:
			combat_occurred.emit(msg)
		Proto.GAME_OVER:
			game_ended.emit(int(msg["winner"]) as PieceData.Team, msg["reason"])
		Proto.ERROR:
			error_received.emit(msg["message"])
			print("Server error: %s" % msg["message"])


# --- Commands to server ---


func send_move(from: Vector2i, to: Vector2i) -> void:
	_send({ "type": Proto.MOVE, "from_x": from.x, "from_y": from.y, "to_x": to.x, "to_y": to.y })


func _send(msg: Dictionary) -> void:
	if _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	_ws.send_text(Proto.encode(msg))
