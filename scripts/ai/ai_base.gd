class_name AIBase
extends RefCounted

const AI_NAMES: Array[String] = ["Heuristic", "Monte Carlo", "Rollout", "Greedy"]

var team: PieceData.Team = PieceData.Team.BLUE
var placement_strategy: Placement.Strategy = Placement.Strategy.CLUSTERED_DEFENSE
# Track enemy piece IDs that have moved at least once
var has_moved: Dictionary = {}


static func create(type_index: int, ai_team: PieceData.Team) -> AIBase:
	var script_path: String
	match type_index:
		1:
			script_path = "res://scripts/ai/monte_carlo_ai.gd"
		2:
			script_path = "res://scripts/ai/rollout_ai.gd"
		3:
			script_path = "res://scripts/ai/greedy_ai.gd"
		_:
			script_path = "res://scripts/ai/ai_player.gd"
	var ai: AIBase = load(script_path).new(ai_team)
	return ai


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
	Placement.place(placement_strategy, board_state, team)


func choose_move(_board_state: BoardState) -> Dictionary:
	return {}


# --- Shared deduction utilities ---


func get_possible_ranks(piece_id: int, board_state: BoardState) -> Array[int]:
	var enemy_team: PieceData.Team = get_enemy_team()

	var accounted: Dictionary = {}
	for rank: int in PieceData.RANK_INFO:
		accounted[rank] = 0

	for pid: int in board_state.pieces:
		var p: Dictionary = board_state.pieces[pid]
		if p["team"] == enemy_team and p["revealed"]:
			accounted[p["rank"]] += 1

	var captured: Array = GameManager.captured_pieces[enemy_team]
	for rank: int in captured:
		accounted[rank] += 1

	var possible: Array[int] = []
	var piece_has_moved: bool = piece_id in has_moved

	for rank: int in PieceData.RANK_INFO:
		var total: int = PieceData.RANK_INFO[rank]["count"]
		if accounted[rank] >= total:
			continue
		if piece_has_moved and (rank == PieceData.Rank.BOMB or rank == PieceData.Rank.FLAG):
			continue
		possible.append(rank)

	return possible


func get_max_possible_rank(piece_id: int, board_state: BoardState) -> int:
	var possible: Array[int] = get_possible_ranks(piece_id, board_state)
	if possible.size() == 0:
		return PieceData.Rank.MARSHAL
	var max_rank: int = possible[0]
	for rank: int in possible:
		if rank > max_rank:
			max_rank = rank
	return max_rank


func is_guaranteed_win(our_rank: PieceData.Rank, enemy_piece_id: int, board_state: BoardState) -> bool:
	var possible: Array[int] = get_possible_ranks(enemy_piece_id, board_state)
	if possible.size() == 0:
		return false
	for rank: int in possible:
		var result: Combat.Result = Combat.resolve(our_rank, rank)
		if result != Combat.Result.ATTACKER_WINS:
			return false
	return true


func is_guaranteed_loss(our_rank: PieceData.Rank, enemy_piece_id: int, board_state: BoardState) -> bool:
	var possible: Array[int] = get_possible_ranks(enemy_piece_id, board_state)
	if possible.size() == 0:
		return false
	for rank: int in possible:
		var result: Combat.Result = Combat.resolve(our_rank, rank)
		if result == Combat.Result.ATTACKER_WINS:
			return false
	return true


# Get all valid moves for a team as an array of {from, to} dicts
func get_all_moves(bs: BoardState, move_team: PieceData.Team) -> Array[Dictionary]:
	var all_moves: Array[Dictionary] = []
	for piece_id: int in bs.get_team_pieces(move_team):
		var piece: Dictionary = bs.pieces[piece_id]
		if not PieceData.can_move(piece["rank"]):
			continue
		var moves: Array[Vector2i] = bs.get_valid_moves(piece_id)
		for target_pos: Vector2i in moves:
			all_moves.append({ "from": piece["pos"], "to": target_pos })
	return all_moves
