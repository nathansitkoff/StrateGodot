class_name MonteCarloAI
extends AIBase

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# Tuning parameters
var samples: int = 20
var max_opponent_moves: int = 5

# Custom piece values for scoring (not the same as rank enum values)
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
	_rng.randomize()


# Use HeuristicAI's placement strategy
func generate_setup(board_state: BoardState) -> void:
	var helper: HeuristicAI = HeuristicAI.new(team)
	helper.generate_setup(board_state)


func choose_move(board_state: BoardState) -> Dictionary:
	var my_pieces: Array[int] = board_state.get_team_pieces(team)
	if my_pieces.size() == 0:
		return {}

	# Collect all legal moves
	var candidate_moves: Array[Dictionary] = []
	for piece_id: int in my_pieces:
		var piece: Dictionary = board_state.pieces[piece_id]
		if not PieceData.can_move(piece["rank"]):
			continue
		var moves: Array[Vector2i] = board_state.get_valid_moves(piece_id)
		for target_pos: Vector2i in moves:
			candidate_moves.append({ "from": piece["pos"], "to": target_pos })

	if candidate_moves.size() == 0:
		return {}

	# Score each candidate move across multiple sampled worlds
	var best_move: Dictionary = candidate_moves[0]
	var best_score: float = -999999.0

	for move: Dictionary in candidate_moves:
		var total_score: float = 0.0
		for s: int in range(samples):
			var world: BoardState = _determinize(board_state)
			var caps: Dictionary = _clone_caps()
			var move_result: Dictionary = GameManager.apply_move(move["from"], move["to"], world, caps)

			if move_result.get("flag_captured", false):
				if move_result["winner"] == team:
					total_score += 10000.0
				else:
					total_score -= 10000.0
				continue

			# Opponent's best response (1-ply for opponent)
			var opp_score: float = _evaluate_opponent_response(world, caps)
			total_score += opp_score

		var avg_score: float = total_score / samples
		if avg_score > best_score:
			best_score = avg_score
			best_move = move

	return best_move


func _evaluate_opponent_response(world: BoardState, caps: Dictionary) -> float:
	var enemy: PieceData.Team = get_enemy_team()
	var enemy_pieces: Array[int] = world.get_team_pieces(enemy)
	if enemy_pieces.size() == 0:
		return 10000.0

	# Collect opponent moves, sample a subset
	var opp_moves: Array[Dictionary] = []
	for piece_id: int in enemy_pieces:
		var piece: Dictionary = world.pieces[piece_id]
		if not PieceData.can_move(piece["rank"]):
			continue
		var moves: Array[Vector2i] = world.get_valid_moves(piece_id)
		for target_pos: Vector2i in moves:
			opp_moves.append({ "from": piece["pos"], "to": target_pos })

	if opp_moves.size() == 0:
		return 10000.0

	# Sample a subset of opponent moves to keep it fast
	opp_moves.shuffle()
	var moves_to_check: int = min(opp_moves.size(), max_opponent_moves)

	# Find opponent's best move (worst for us)
	var worst_for_us: float = 999999.0
	for i: int in range(moves_to_check):
		var opp_move: Dictionary = opp_moves[i]
		var sim_world: BoardState = world.clone()
		var sim_caps: Dictionary = _clone_caps_from(caps)
		var result: Dictionary = GameManager.apply_move(opp_move["from"], opp_move["to"], sim_world, sim_caps)

		if result.get("flag_captured", false):
			if result["winner"] == team:
				worst_for_us = min(worst_for_us, 10000.0)
			else:
				worst_for_us = min(worst_for_us, -10000.0)
			continue

		var score: float = _score_position(sim_world, sim_caps)
		worst_for_us = min(worst_for_us, score)

	return worst_for_us


func _score_position(bs: BoardState, _caps: Dictionary) -> float:
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
			# Advancement bonus for movable pieces
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

	# Flag safety: penalize if enemy pieces are near our flag
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

	# Miner advantage: valuable if enemy still has bombs
	if enemy_bomb_count > 0:
		score += my_miner_count * 3.0
		score -= enemy_miner_count * 3.0

	return score


# Create a determinized copy: assign random ranks to unrevealed enemy pieces
func _determinize(board_state: BoardState) -> BoardState:
	var world: BoardState = board_state.clone()
	var enemy: PieceData.Team = get_enemy_team()

	# Collect unrevealed enemy piece IDs
	var unrevealed_ids: Array[int] = []
	for piece_id: int in world.pieces:
		var piece: Dictionary = world.pieces[piece_id]
		if piece["team"] == enemy and not piece["revealed"]:
			unrevealed_ids.append(piece_id)

	if unrevealed_ids.size() == 0:
		return world

	# Count which enemy ranks are unaccounted for (not revealed, not captured)
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

	# Build pool of available ranks
	var rank_pool: Array[int] = []
	for rank: int in PieceData.RANK_INFO:
		var total: int = PieceData.RANK_INFO[rank]["count"]
		var remaining: int = total - accounted[rank]
		for i: int in range(remaining):
			rank_pool.append(rank)

	# Filter pool per piece based on movement constraints
	# First, assign ranks that are forced by constraints
	var assignments: Dictionary = {}  # piece_id -> rank
	var remaining_pool: Array[int] = rank_pool.duplicate()
	remaining_pool.shuffle()

	# Separate pieces that have moved (can't be bomb/flag) vs haven't
	var moved_ids: Array[int] = []
	var stationary_ids: Array[int] = []
	for pid: int in unrevealed_ids:
		if pid in _has_moved:
			moved_ids.append(pid)
		else:
			stationary_ids.append(pid)

	# Separate movable and immovable ranks in the pool
	var movable_ranks: Array[int] = []
	var immovable_ranks: Array[int] = []
	for rank: int in remaining_pool:
		if rank == PieceData.Rank.BOMB or rank == PieceData.Rank.FLAG:
			immovable_ranks.append(rank)
		else:
			movable_ranks.append(rank)

	movable_ranks.shuffle()
	immovable_ranks.shuffle()

	# Assign movable ranks to moved pieces
	var movable_idx: int = 0
	for pid: int in moved_ids:
		if movable_idx < movable_ranks.size():
			assignments[pid] = movable_ranks[movable_idx]
			movable_idx += 1

	# Remaining movable ranks + all immovable ranks go to stationary pieces
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

	# Apply assignments
	for pid: int in assignments:
		world.pieces[pid]["rank"] = assignments[pid]

	return world


func _clone_caps() -> Dictionary:
	return {
		PieceData.Team.RED: GameManager.captured_pieces[PieceData.Team.RED].duplicate(),
		PieceData.Team.BLUE: GameManager.captured_pieces[PieceData.Team.BLUE].duplicate(),
	}


func _clone_caps_from(caps: Dictionary) -> Dictionary:
	return {
		PieceData.Team.RED: caps[PieceData.Team.RED].duplicate(),
		PieceData.Team.BLUE: caps[PieceData.Team.BLUE].duplicate(),
	}
