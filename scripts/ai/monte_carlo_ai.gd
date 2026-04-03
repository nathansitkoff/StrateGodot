class_name MonteCarloAI
extends SamplingAIBase

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# Tuning parameters
var samples: int = 5
var search_depth: int = 2
var max_top_moves: int = 15
var max_inner_moves: int = 8
var max_quiescence_depth: int = 4


func _init(ai_team: PieceData.Team = PieceData.Team.BLUE) -> void:
	super(ai_team)
	_rng.randomize()


func choose_move(board_state: BoardState) -> Dictionary:
	var all_moves: Array[Dictionary] = _get_ordered_moves(board_state, team)
	if all_moves.size() == 0:
		return {}

	var candidates: Array[Dictionary] = all_moves.slice(0, max_top_moves)
	return sample_best_move(board_state, candidates, samples, _evaluate_world)


func _evaluate_world(world: BoardState, caps: Dictionary) -> float:
	return _alpha_beta(world, caps, search_depth - 1, -999999.0, 999999.0, false)


func _alpha_beta(bs: BoardState, caps: Dictionary, depth: int, alpha: float, beta: float, maximizing: bool) -> float:
	if depth <= 0:
		return _quiescence(bs, caps, max_quiescence_depth, alpha, beta, maximizing)

	var current_team: PieceData.Team = team if maximizing else get_enemy_team()
	var all_moves: Array[Dictionary] = _get_ordered_moves(bs, current_team)

	if all_moves.size() == 0:
		return -10000.0 if maximizing else 10000.0

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


# Quiescence search: extend search at leaf nodes for capture moves only
# Ensures we don't evaluate in the middle of a tactical exchange
func _quiescence(bs: BoardState, caps: Dictionary, depth: int, alpha: float, beta: float, maximizing: bool) -> float:
	var stand_pat: float = score_position(bs)

	if depth <= 0:
		return stand_pat

	# Stand-pat: the side to move can choose not to capture
	if maximizing:
		if stand_pat >= beta:
			return beta
		alpha = max(alpha, stand_pat)
	else:
		if stand_pat <= alpha:
			return alpha
		beta = min(beta, stand_pat)

	var current_team: PieceData.Team = team if maximizing else get_enemy_team()
	var captures: Array[Dictionary] = _get_capture_moves(bs, current_team)

	if captures.size() == 0:
		return stand_pat

	if maximizing:
		for move: Dictionary in captures:
			var sim_bs: BoardState = bs.clone()
			var sim_caps: Dictionary = clone_caps_from(caps)
			var result: Dictionary = GameManager.apply_move(move["from"], move["to"], sim_bs, sim_caps)

			var move_score: float
			if result.get("flag_captured", false):
				move_score = 10000.0 if result["winner"] == team else -10000.0
			else:
				move_score = _quiescence(sim_bs, sim_caps, depth - 1, alpha, beta, false)

			alpha = max(alpha, move_score)
			if beta <= alpha:
				break
		return alpha
	else:
		for move: Dictionary in captures:
			var sim_bs: BoardState = bs.clone()
			var sim_caps: Dictionary = clone_caps_from(caps)
			var result: Dictionary = GameManager.apply_move(move["from"], move["to"], sim_bs, sim_caps)

			var move_score: float
			if result.get("flag_captured", false):
				move_score = 10000.0 if result["winner"] == team else -10000.0
			else:
				move_score = _quiescence(sim_bs, sim_caps, depth - 1, alpha, beta, true)

			beta = min(beta, move_score)
			if beta <= alpha:
				break
		return beta


# Get only capture moves for a team, ordered: flag captures > winning > even > losing
func _get_capture_moves(bs: BoardState, move_team: PieceData.Team) -> Array[Dictionary]:
	var flag_captures: Array[Dictionary] = []
	var winning: Array[Dictionary] = []
	var even: Array[Dictionary] = []
	var losing: Array[Dictionary] = []

	for piece_id: int in bs.get_team_pieces(move_team):
		var piece: Dictionary = bs.pieces[piece_id]
		if not PieceData.can_move(piece["rank"]):
			continue
		var valid: Array[Vector2i] = bs.get_valid_moves(piece_id)
		for target_pos: Vector2i in valid:
			var target_id: int = bs.get_piece_at(target_pos)
			if target_id == -1:
				continue
			var target: Dictionary = bs.pieces[target_id]
			var move: Dictionary = { "from": piece["pos"], "to": target_pos }
			if target["rank"] == PieceData.Rank.FLAG:
				flag_captures.append(move)
			else:
				var result: Combat.Result = Combat.resolve(piece["rank"], target["rank"])
				if result == Combat.Result.ATTACKER_WINS:
					winning.append(move)
				elif result == Combat.Result.BOTH_DIE:
					even.append(move)
				else:
					losing.append(move)

	var ordered: Array[Dictionary] = []
	ordered.append_array(flag_captures)
	ordered.append_array(winning)
	ordered.append_array(even)
	ordered.append_array(losing)
	return ordered


# Generate moves ordered by priority for better alpha-beta pruning
func _get_ordered_moves(bs: BoardState, move_team: PieceData.Team) -> Array[Dictionary]:
	var flag_captures: Array[Dictionary] = []
	var winning_attacks: Array[Dictionary] = []
	var even_attacks: Array[Dictionary] = []
	var losing_attacks: Array[Dictionary] = []
	var forward_moves: Array[Dictionary] = []
	var other_moves: Array[Dictionary] = []
	var forward_dir: int = -1 if move_team == PieceData.Team.RED else 1

	for piece_id: int in bs.get_team_pieces(move_team):
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
