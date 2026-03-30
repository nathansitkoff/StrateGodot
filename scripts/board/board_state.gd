class_name BoardState
extends RefCounted

const BOARD_SIZE: int = 10

const LAKE_CELLS: Array[Vector2i] = [
	Vector2i(2, 4), Vector2i(2, 5),
	Vector2i(3, 4), Vector2i(3, 5),
	Vector2i(6, 4), Vector2i(6, 5),
	Vector2i(7, 4), Vector2i(7, 5),
]

# grid[col][row] = piece_id or -1 for empty
var grid: Array[Array] = []
# pieces[piece_id] = { "rank": Rank, "team": Team, "revealed": bool, "pos": Vector2i }
var pieces: Dictionary = {}
var _next_id: int = 0


func _init() -> void:
	_clear_grid()


func _clear_grid() -> void:
	grid.clear()
	for col: int in range(BOARD_SIZE):
		var column: Array[int] = []
		column.resize(BOARD_SIZE)
		column.fill(-1)
		grid.append(column)


func reset() -> void:
	_clear_grid()
	pieces.clear()
	_next_id = 0


func is_lake(pos: Vector2i) -> bool:
	return pos in LAKE_CELLS


func is_in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < BOARD_SIZE and pos.y >= 0 and pos.y < BOARD_SIZE


func is_valid_cell(pos: Vector2i) -> bool:
	return is_in_bounds(pos) and not is_lake(pos)


func get_piece_at(pos: Vector2i) -> int:
	if not is_in_bounds(pos):
		return -1
	return grid[pos.x][pos.y]


func add_piece(rank: PieceData.Rank, team: PieceData.Team, pos: Vector2i) -> int:
	var id: int = _next_id
	_next_id += 1
	pieces[id] = {
		"rank": rank,
		"team": team,
		"revealed": false,
		"pos": pos,
	}
	grid[pos.x][pos.y] = id
	return id


func remove_piece(piece_id: int) -> void:
	if piece_id not in pieces:
		return
	var pos: Vector2i = pieces[piece_id]["pos"]
	grid[pos.x][pos.y] = -1
	pieces.erase(piece_id)


func move_piece(piece_id: int, to: Vector2i) -> void:
	if piece_id not in pieces:
		return
	var from: Vector2i = pieces[piece_id]["pos"]
	grid[from.x][from.y] = -1
	grid[to.x][to.y] = piece_id
	pieces[piece_id]["pos"] = to


func get_valid_moves(piece_id: int) -> Array[Vector2i]:
	var moves: Array[Vector2i] = []
	if piece_id not in pieces:
		return moves

	var piece: Dictionary = pieces[piece_id]
	var rank: PieceData.Rank = piece["rank"]
	var team: PieceData.Team = piece["team"]
	var pos: Vector2i = piece["pos"]

	if not PieceData.can_move(rank):
		return moves

	var move_range: int = PieceData.get_move_range(rank)
	var directions: Array[Vector2i] = [
		Vector2i(0, -1), Vector2i(0, 1),
		Vector2i(-1, 0), Vector2i(1, 0),
	]

	for dir: Vector2i in directions:
		for dist: int in range(1, move_range + 1):
			var target: Vector2i = pos + dir * dist
			if not is_in_bounds(target) or is_lake(target):
				break
			var occupant: int = grid[target.x][target.y]
			if occupant == -1:
				moves.append(target)
			else:
				# Can attack enemy pieces, but can't move through or onto friendly
				if pieces[occupant]["team"] != team:
					moves.append(target)
				break
	return moves


func has_movable_pieces(team: PieceData.Team) -> bool:
	for piece_id: int in pieces:
		var piece: Dictionary = pieces[piece_id]
		if piece["team"] == team and PieceData.can_move(piece["rank"]):
			if get_valid_moves(piece_id).size() > 0:
				return true
	return false


func get_team_pieces(team: PieceData.Team) -> Array[int]:
	var result: Array[int] = []
	for piece_id: int in pieces:
		if pieces[piece_id]["team"] == team:
			result.append(piece_id)
	return result


func get_setup_rows(team: PieceData.Team) -> Array[int]:
	# Returns [back_row, second_row, third_row, front_row]
	# Back = furthest from enemy, front = closest to enemy
	if team == PieceData.Team.RED:
		return [9, 8, 7, 6]
	else:
		return [0, 1, 2, 3]
