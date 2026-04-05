class_name SamplingAIBase
extends AIBase

const WIN_SCORE: float = 10000.0

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


func _init(ai_team: PieceData.Team = PieceData.Team.BLUE) -> void:
	super(ai_team)


# Create a determinized copy: assign random ranks to unrevealed enemy pieces
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


# Run a sampling loop: for each candidate move, determinize N worlds,
# apply the move, and call score_fn with the resulting world and caps.
# Returns the best move based on average score across samples.
func sample_best_move(board_state: BoardState, candidates: Array[Dictionary], num_samples: int, score_fn: Callable) -> Dictionary:
	if candidates.size() == 0:
		return {}

	var best_move: Dictionary = candidates[0]
	var best_score: float = -999999.0

	for move: Dictionary in candidates:
		var total_score: float = 0.0
		for s: int in range(num_samples):
			var world: BoardState = determinize(board_state)
			var caps: Dictionary = clone_caps()
			var move_result: Dictionary = GameManager.apply_move(move["from"], move["to"], world, caps)

			if move_result.get("flag_captured", false):
				if move_result["winner"] == team:
					total_score += 10000.0
				else:
					total_score -= 10000.0
				continue

			total_score += score_fn.call(world, caps)

		var avg_score: float = total_score / num_samples
		if avg_score > best_score:
			best_score = avg_score
			best_move = move

	return best_move


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

		if not piece["revealed"]:
			value *= 1.3

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
