class_name GameRecorder
extends RefCounted

var metadata: Dictionary = {}
var placements: Array[Dictionary] = []
var moves: Array[Dictionary] = []
var checksums: Array[int] = []


func start_recording(mode: String, red_ai: String, blue_ai: String, first_team: PieceData.Team) -> void:
	metadata = {
		"mode": mode,
		"red_ai": red_ai,
		"blue_ai": blue_ai,
		"first_team": first_team,
		"result": "",
		"winner": -1,
		"turn_count": 0,
		"timestamp": Time.get_datetime_string_from_system(),
	}
	placements.clear()
	moves.clear()
	checksums.clear()


func record_placement(piece_id: int, rank: PieceData.Rank, team_val: PieceData.Team, pos: Vector2i) -> void:
	placements.append({
		"id": piece_id,
		"rank": rank,
		"team": team_val,
		"x": pos.x,
		"y": pos.y,
	})


func record_placements_from_board(board_state: BoardState) -> void:
	for piece_id: int in board_state.pieces:
		var piece: Dictionary = board_state.pieces[piece_id]
		record_placement(piece_id, piece["rank"], piece["team"], piece["pos"])


func record_checksum(board_state: BoardState) -> void:
	checksums.append(board_state.checksum())


func record_move(from: Vector2i, to: Vector2i) -> void:
	moves.append({
		"from_x": from.x,
		"from_y": from.y,
		"to_x": to.x,
		"to_y": to.y,
	})


func finish_recording(result: String, winner: int, turn_count: int) -> void:
	metadata["result"] = result
	metadata["winner"] = winner
	metadata["turn_count"] = turn_count


func save_to_file(filepath: String) -> void:
	var data: Dictionary = {
		"metadata": metadata,
		"placements": placements,
		"moves": moves,
		"checksums": checksums,
	}
	var file: FileAccess = FileAccess.open(filepath, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "\t"))
	file.close()


static func load_from_file(filepath: String) -> GameRecorder:
	var file: FileAccess = FileAccess.open(filepath, FileAccess.READ)
	if file == null:
		return null
	var text: String = file.get_as_text()
	file.close()

	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return null

	var data: Dictionary = json.data
	var recorder: GameRecorder = GameRecorder.new()
	recorder.metadata = data["metadata"]

	for p: Dictionary in data["placements"]:
		recorder.placements.append({
			"id": int(p["id"]),
			"rank": int(p["rank"]),
			"team": int(p["team"]),
			"x": int(p["x"]),
			"y": int(p["y"]),
		})

	for m: Dictionary in data["moves"]:
		recorder.moves.append({
			"from_x": int(m["from_x"]),
			"from_y": int(m["from_y"]),
			"to_x": int(m["to_x"]),
			"to_y": int(m["to_y"]),
		})

	if "checksums" in data:
		for c: int in data["checksums"]:
			recorder.checksums.append(int(c))

	return recorder


static func generate_filename(mode: String, red_ai: String, blue_ai: String) -> String:
	var ts: String = Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var safe_red: String = red_ai.replace(" ", "-")
	var safe_blue: String = blue_ai.replace(" ", "-")
	return "user://replays/%s_%s_vs_%s_%s.json" % [mode, safe_red, safe_blue, ts]


func get_total_moves() -> int:
	return moves.size()


# Reconstruct board state at a given move index (0 = initial placement, N = after N moves)
func get_state_at_move(move_index: int) -> Dictionary:
	var bs: BoardState = BoardState.new()
	var caps: Dictionary = {
		PieceData.Team.RED: [] as Array[PieceData.Rank],
		PieceData.Team.BLUE: [] as Array[PieceData.Rank],
	}

	# Place all pieces
	for p: Dictionary in placements:
		bs.add_piece(p["rank"], p["team"], Vector2i(p["x"], p["y"]))

	# Apply moves up to move_index
	var current_team: PieceData.Team = metadata["first_team"]
	var last_move_from: Vector2i = Vector2i(-1, -1)
	var last_move_to: Vector2i = Vector2i(-1, -1)

	for i: int in range(min(move_index, moves.size())):
		var m: Dictionary = moves[i]
		var from: Vector2i = Vector2i(m["from_x"], m["from_y"])
		var to: Vector2i = Vector2i(m["to_x"], m["to_y"])

		GameManager.apply_move(from, to, bs, caps)
		last_move_from = from
		last_move_to = to

		# Alternate turns
		if current_team == PieceData.Team.RED:
			current_team = PieceData.Team.BLUE
		else:
			current_team = PieceData.Team.RED

	return {
		"board_state": bs,
		"captured": caps,
		"current_team": current_team,
		"last_from": last_move_from,
		"last_to": last_move_to,
	}
