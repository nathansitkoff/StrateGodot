class_name RolloutAI
extends AIBase

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# Tuning parameters
var samples: int = 10
var rollout_depth: int = 20


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

			# Apply our candidate move
			var move_result: Dictionary = GameManager.apply_move(move["from"], move["to"], world, caps)

			if move_result.get("flag_captured", false):
				if move_result["winner"] == team:
					total_score += 10000.0
				else:
					total_score -= 10000.0
				continue

			# Run a rollout: both sides play using HeuristicAI for N turns
			var rollout_score: float = _run_rollout(world, caps)
			total_score += rollout_score

		var avg_score: float = total_score / samples
		if avg_score > best_score:
			best_score = avg_score
			best_move = move

	return best_move


func _run_rollout(world: BoardState, caps: Dictionary) -> float:
	# Create temporary GreedyAI players for the rollout
	var sim_red: GreedyAI = GreedyAI.new(PieceData.Team.RED)
	var sim_blue: GreedyAI = GreedyAI.new(PieceData.Team.BLUE)

	# The opponent just played (we applied our move), so it's opponent's turn next
	var current: PieceData.Team = get_enemy_team()

	for turn: int in range(rollout_depth):
		var sim_ai: GreedyAI = sim_red if current == PieceData.Team.RED else sim_blue
		var move: Dictionary = sim_ai.choose_move(world)
		if move.size() == 0:
			# Current player can't move — opponent wins
			if current == team:
				return -10000.0
			else:
				return 10000.0

		var result: Dictionary = GameManager.apply_move(move["from"], move["to"], world, caps)

		if result.get("flag_captured", false):
			if result["winner"] == team:
				return 10000.0
			else:
				return -10000.0

		# Check if next player can move
		var next: PieceData.Team = PieceData.Team.BLUE if current == PieceData.Team.RED else PieceData.Team.RED
		if not world.has_movable_pieces(next):
			if current == team:
				return 10000.0
			else:
				return -10000.0
		current = next

	# Rollout didn't end — evaluate the position
	return score_position(world)
