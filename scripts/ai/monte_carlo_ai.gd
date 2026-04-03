class_name MonteCarloAI
extends AIBase

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# Tuning parameters
var samples: int = 5
var search_depth: int = 2
var max_top_moves: int = 15
var max_inner_moves: int = 8


func _init(ai_team: PieceData.Team = PieceData.Team.BLUE) -> void:
	super(ai_team)
	_rng.randomize()


func choose_move(board_state: BoardState) -> Dictionary:
	var my_pieces: Array[int] = board_state.get_team_pieces(team)
	if my_pieces.size() == 0:
		return {}

	# Get all moves, ordered by priority
	var all_moves: Array[Dictionary] = _get_ordered_moves(board_state, team)
	if all_moves.size() == 0:
		return {}

	# Only evaluate the top candidates with expensive search
	var candidates: Array[Dictionary] = all_moves.slice(0, max_top_moves)

	var best_move: Dictionary = candidates[0]
	var best_score: float = -999999.0

	for move: Dictionary in candidates:
		var total_score: float = 0.0
		for s: int in range(samples):
			var world: BoardState = determinize(board_state)
			var caps: Dictionary = clone_caps()
			var move_result: Dictionary = GameManager.apply_move(move["from"], move["to"], world, caps)

			if move_result.get("flag_captured", false):
				if move_result["winner"] == team:
					total_score += 10000.0
				else:
					total_score -= 10000.0
				continue

			var ab_score: float = _alpha_beta(world, caps, search_depth - 1, -999999.0, 999999.0, false)
			total_score += ab_score

		var avg_score: float = total_score / samples
		if avg_score > best_score:
			best_score = avg_score
			best_move = move

	return best_move


func _alpha_beta(bs: BoardState, caps: Dictionary, depth: int, alpha: float, beta: float, maximizing: bool) -> float:
	if depth <= 0:
		return score_position(bs)

	var current_team: PieceData.Team = team if maximizing else get_enemy_team()
	var all_moves: Array[Dictionary] = _get_ordered_moves(bs, current_team)

	if all_moves.size() == 0:
		if maximizing:
			return -10000.0
		else:
			return 10000.0

	# At inner nodes, only consider top moves for speed
	var moves: Array[Dictionary] = all_moves.slice(0, max_inner_moves)

	if maximizing:
		var max_score: float = -999999.0
		for move: Dictionary in moves:
			var sim_bs: BoardState = bs.clone()
			var sim_caps: Dictionary = clone_caps_from(caps)
			var result: Dictionary = GameManager.apply_move(move["from"], move["to"], sim_bs, sim_caps)

			var move_score: float
			if result.get("flag_captured", false):
				move_score = 10000.0 if result["winner"] == team else -10000.0
			else:
				move_score = _alpha_beta(sim_bs, sim_caps, depth - 1, alpha, beta, false)

			max_score = max(max_score, move_score)
			alpha = max(alpha, move_score)
			if beta <= alpha:
				break
		return max_score
	else:
		var min_score: float = 999999.0
		for move: Dictionary in moves:
			var sim_bs: BoardState = bs.clone()
			var sim_caps: Dictionary = clone_caps_from(caps)
			var result: Dictionary = GameManager.apply_move(move["from"], move["to"], sim_bs, sim_caps)

			var move_score: float
			if result.get("flag_captured", false):
				move_score = 10000.0 if result["winner"] == team else -10000.0
			else:
				move_score = _alpha_beta(sim_bs, sim_caps, depth - 1, alpha, beta, true)

			min_score = min(min_score, move_score)
			beta = min(beta, move_score)
			if beta <= alpha:
				break
		return min_score


# Generate moves ordered by priority for better alpha-beta pruning
# Priority: flag captures > winning attacks > even attacks > forward moves > other
func _get_ordered_moves(bs: BoardState, move_team: PieceData.Team) -> Array[Dictionary]:
	var flag_captures: Array[Dictionary] = []
	var winning_attacks: Array[Dictionary] = []
	var even_attacks: Array[Dictionary] = []
	var losing_attacks: Array[Dictionary] = []
	var forward_moves: Array[Dictionary] = []
	var other_moves: Array[Dictionary] = []
	var forward_dir: int = -1 if move_team == PieceData.Team.RED else 1

	var pieces: Array[int] = bs.get_team_pieces(move_team)
	for piece_id: int in pieces:
		var piece: Dictionary = bs.pieces[piece_id]
		if not PieceData.can_move(piece["rank"]):
			continue
		var valid: Array[Vector2i] = bs.get_valid_moves(piece_id)
		for target_pos: Vector2i in valid:
			var move: Dictionary = { "from": piece["pos"], "to": target_pos }
			var target_id: int = bs.get_piece_at(target_pos)
			if target_id != -1:
				var target: Dictionary = bs.pieces[target_id]
				if target["rank"] == PieceData.Rank.FLAG:
					flag_captures.append(move)
				else:
					var result: Combat.Result = Combat.resolve(piece["rank"], target["rank"])
					if result == Combat.Result.ATTACKER_WINS:
						winning_attacks.append(move)
					elif result == Combat.Result.BOTH_DIE:
						even_attacks.append(move)
					else:
						losing_attacks.append(move)
			elif (target_pos.y - piece["pos"].y) * forward_dir > 0:
				forward_moves.append(move)
			else:
				other_moves.append(move)

	var ordered: Array[Dictionary] = []
	ordered.append_array(flag_captures)
	ordered.append_array(winning_attacks)
	ordered.append_array(even_attacks)
	ordered.append_array(forward_moves)
	ordered.append_array(other_moves)
	ordered.append_array(losing_attacks)
	return ordered
