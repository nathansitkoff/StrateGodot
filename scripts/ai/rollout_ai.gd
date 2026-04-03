class_name RolloutAI
extends SamplingAIBase

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# Tuning parameters
var samples: int = 10
var rollout_depth: int = 20


func _init(ai_team: PieceData.Team = PieceData.Team.BLUE) -> void:
	super(ai_team)
	_rng.randomize()


func choose_move(board_state: BoardState) -> Dictionary:
	var candidates: Array[Dictionary] = get_all_moves(board_state, team)
	if candidates.size() == 0:
		return {}

	return sample_best_move(board_state, candidates, samples, _run_rollout)


func _run_rollout(world: BoardState, caps: Dictionary) -> float:
	var sim_red: GreedyAI = GreedyAI.new(PieceData.Team.RED)
	var sim_blue: GreedyAI = GreedyAI.new(PieceData.Team.BLUE)

	var current: PieceData.Team = get_enemy_team()

	for turn: int in range(rollout_depth):
		var sim_ai: GreedyAI = sim_red if current == PieceData.Team.RED else sim_blue
		var move: Dictionary = sim_ai.choose_move(world)
		if move.size() == 0:
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

		var next: PieceData.Team = PieceData.Team.BLUE if current == PieceData.Team.RED else PieceData.Team.RED
		if not world.has_movable_pieces(next):
			if current == team:
				return 10000.0
			else:
				return -10000.0
		current = next

	return score_position(world)
