class_name AIBase
extends RefCounted

const AI_NAMES: Array[String] = ["Heuristic", "Monte Carlo"]

var team: PieceData.Team = PieceData.Team.BLUE
# Track enemy piece IDs that have moved at least once
var has_moved: Dictionary = {}


static func create(type_index: int, ai_team: PieceData.Team) -> AIBase:
	match type_index:
		1:
			return MonteCarloAI.new(ai_team)
		_:
			return HeuristicAI.new(ai_team)


func _init(ai_team: PieceData.Team = PieceData.Team.BLUE) -> void:
	team = ai_team


func reset() -> void:
	has_moved.clear()


func notify_move(piece_id: int, piece_team: PieceData.Team) -> void:
	if piece_team != team:
		has_moved[piece_id] = true


func get_enemy_team() -> PieceData.Team:
	if team == PieceData.Team.BLUE:
		return PieceData.Team.RED
	return PieceData.Team.BLUE


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
