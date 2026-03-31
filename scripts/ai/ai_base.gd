class_name AIBase
extends RefCounted

var team: PieceData.Team = PieceData.Team.BLUE


func _init(ai_team: PieceData.Team = PieceData.Team.BLUE) -> void:
	team = ai_team


func reset() -> void:
	pass


func notify_move(_piece_id: int, _piece_team: PieceData.Team) -> void:
	pass


func generate_setup(board_state: BoardState) -> void:
	# Default: random placement
	var rows: Array[int] = board_state.get_setup_rows(team)
	var cells: Array[Vector2i] = []
	for col: int in range(BoardState.BOARD_SIZE):
		for row: int in rows:
			var pos: Vector2i = Vector2i(col, row)
			if board_state.is_valid_cell(pos) and board_state.get_piece_at(pos) == -1:
				cells.append(pos)
	cells.shuffle()
	var idx: int = 0
	for rank: int in PieceData.RANK_INFO:
		var remaining: int = PieceData.RANK_INFO[rank]["count"]
		# Subtract already placed pieces of this rank
		for piece_id: int in board_state.pieces:
			var p: Dictionary = board_state.pieces[piece_id]
			if p["team"] == team and p["rank"] == rank:
				remaining -= 1
		for i: int in range(remaining):
			if idx < cells.size():
				board_state.add_piece(rank, team, cells[idx])
				idx += 1


func choose_move(_board_state: BoardState) -> Dictionary:
	# Must be overridden. Returns { "from": Vector2i, "to": Vector2i } or {}
	return {}
