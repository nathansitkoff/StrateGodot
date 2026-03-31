class_name AIBase
extends RefCounted

const AI_NAMES: Array[String] = ["Heuristic", "Monte Carlo", "Rollout"]

var team: PieceData.Team = PieceData.Team.BLUE
# Track enemy piece IDs that have moved at least once
var has_moved: Dictionary = {}

# Shared piece values for scoring
const PIECE_VALUES: Dictionary = {
	PieceData.Rank.FLAG: 0,
	PieceData.Rank.SPY: 7,
	PieceData.Rank.SCOUT: 2,
	PieceData.Rank.MINER: 8,
	PieceData.Rank.SERGEANT: 3,
	PieceData.Rank.LIEUTENANT: 4,
	PieceData.Rank.CAPTAIN: 5,
	PieceData.Rank.MAJOR: 6,
	PieceData.Rank.COLONEL: 7,
	PieceData.Rank.GENERAL: 9,
	PieceData.Rank.MARSHAL: 10,
	PieceData.Rank.BOMB: 4,
}


static func create(type_index: int, ai_team: PieceData.Team) -> AIBase:
	match type_index:
		1:
			return MonteCarloAI.new(ai_team)
		2:
			return RolloutAI.new(ai_team)
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
	return {}


# --- Shared utilities for Monte Carlo / Rollout AIs ---


func determinize(board_state: BoardState) -> BoardState:
	var world: BoardState = board_state.clone()
	var enemy: PieceData.Team = get_enemy_team()

	var unrevealed_ids: Array[int] = []
	for piece_id: int in world.pieces:
		var piece: Dictionary = world.pieces[piece_id]
		if piece["team"] == enemy and not piece["revealed"]:
			unrevealed_ids.append(piece_id)

	if unrevealed_ids.size() == 0:
		return world

	var accounted: Dictionary = {}
	for rank: int in PieceData.RANK_INFO:
		accounted[rank] = 0
	for piece_id: int in world.pieces:
		var piece: Dictionary = world.pieces[piece_id]
		if piece["team"] == enemy and piece["revealed"]:
			accounted[piece["rank"]] += 1
	var captured: Array = GameManager.captured_pieces[enemy]
	for rank: int in captured:
		accounted[rank] += 1

	var rank_pool: Array[int] = []
	for rank: int in PieceData.RANK_INFO:
		var total: int = PieceData.RANK_INFO[rank]["count"]
		var remaining: int = total - accounted[rank]
		for i: int in range(remaining):
			rank_pool.append(rank)

	var moved_ids: Array[int] = []
	var stationary_ids: Array[int] = []
	for pid: int in unrevealed_ids:
		if pid in has_moved:
			moved_ids.append(pid)
		else:
			stationary_ids.append(pid)

	var movable_ranks: Array[int] = []
	var immovable_ranks: Array[int] = []
	for rank: int in rank_pool:
		if rank == PieceData.Rank.BOMB or rank == PieceData.Rank.FLAG:
			immovable_ranks.append(rank)
		else:
			movable_ranks.append(rank)

	movable_ranks.shuffle()
	immovable_ranks.shuffle()

	var assignments: Dictionary = {}
	var movable_idx: int = 0
	for pid: int in moved_ids:
		if movable_idx < movable_ranks.size():
			assignments[pid] = movable_ranks[movable_idx]
			movable_idx += 1

	var stationary_pool: Array[int] = []
	for i: int in range(movable_idx, movable_ranks.size()):
		stationary_pool.append(movable_ranks[i])
	stationary_pool.append_array(immovable_ranks)
	stationary_pool.shuffle()

	var stat_idx: int = 0
	for pid: int in stationary_ids:
		if stat_idx < stationary_pool.size():
			assignments[pid] = stationary_pool[stat_idx]
			stat_idx += 1

	for pid: int in assignments:
		world.pieces[pid]["rank"] = assignments[pid]

	return world


func clone_caps() -> Dictionary:
	return {
		PieceData.Team.RED: GameManager.captured_pieces[PieceData.Team.RED].duplicate(),
		PieceData.Team.BLUE: GameManager.captured_pieces[PieceData.Team.BLUE].duplicate(),
	}


func clone_caps_from(caps: Dictionary) -> Dictionary:
	return {
		PieceData.Team.RED: caps[PieceData.Team.RED].duplicate(),
		PieceData.Team.BLUE: caps[PieceData.Team.BLUE].duplicate(),
	}


func score_position(bs: BoardState) -> float:
	var my_material: float = 0.0
	var enemy_material: float = 0.0
	var my_flag_pos: Vector2i = Vector2i(-1, -1)
	var my_miner_count: int = 0
	var enemy_miner_count: int = 0
	var enemy_bomb_count: int = 0
	var my_back_row: int = 9 if team == PieceData.Team.RED else 0

	for piece_id: int in bs.pieces:
		var piece: Dictionary = bs.pieces[piece_id]
		var rank: PieceData.Rank = piece["rank"]
		var value: float = PIECE_VALUES[rank]

		if piece["team"] == team:
			my_material += value
			if rank == PieceData.Rank.FLAG:
				my_flag_pos = piece["pos"]
			if rank == PieceData.Rank.MINER:
				my_miner_count += 1
			if PieceData.can_move(rank):
				var dist_from_back: int = abs(piece["pos"].y - my_back_row)
				my_material += dist_from_back * 0.1
		else:
			enemy_material += value
			if rank == PieceData.Rank.MINER:
				enemy_miner_count += 1
			if rank == PieceData.Rank.BOMB:
				enemy_bomb_count += 1

	var score: float = my_material - enemy_material

	if my_flag_pos != Vector2i(-1, -1):
		var directions: Array[Vector2i] = [
			Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0),
		]
		var adjacent_defenders: int = 0
		var adjacent_threats: int = 0
		for dir: Vector2i in directions:
			var adj: Vector2i = my_flag_pos + dir
			var adj_id: int = bs.get_piece_at(adj)
			if adj_id != -1:
				if bs.pieces[adj_id]["team"] == team:
					adjacent_defenders += 1
				else:
					adjacent_threats += 1
		score += adjacent_defenders * 2.0
		score -= adjacent_threats * 5.0

	if enemy_bomb_count > 0:
		score += my_miner_count * 3.0
		score -= enemy_miner_count * 3.0

	return score
