class_name MonteCarloAI
extends AIBase

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# Tuning parameters
var samples: int = 20
var max_opponent_moves: int = 5


func _init(ai_team: PieceData.Team = PieceData.Team.BLUE) -> void:
	super(ai_team)
	_rng.randomize()


func choose_move(board_state: BoardState) -> Dictionary:
	var my_pieces: Array[int] = board_state.get_team_pieces(team)
	if my_pieces.size() == 0:
		return {}

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

	var best_move: Dictionary = candidate_moves[0]
	var best_score: float = -999999.0

	for move: Dictionary in candidate_moves:
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

	opp_moves.shuffle()
	var moves_to_check: int = min(opp_moves.size(), max_opponent_moves)

	var worst_for_us: float = 999999.0
	for i: int in range(moves_to_check):
		var opp_move: Dictionary = opp_moves[i]
		var sim_world: BoardState = world.clone()
		var sim_caps: Dictionary = clone_caps_from(caps)
		var result: Dictionary = GameManager.apply_move(opp_move["from"], opp_move["to"], sim_world, sim_caps)

		if result.get("flag_captured", false):
			if result["winner"] == team:
				worst_for_us = min(worst_for_us, 10000.0)
			else:
				worst_for_us = min(worst_for_us, -10000.0)
			continue

		var score: float = score_position(sim_world)
		worst_for_us = min(worst_for_us, score)

	return worst_for_us
