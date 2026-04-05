class_name GameState
extends RefCounted

# Pure game state and rules. No signals, no UI, no rendering.

var board_state: BoardState = BoardState.new()
var captured_pieces: Dictionary = {
	PieceData.Team.RED: [] as Array[PieceData.Rank],
	PieceData.Team.BLUE: [] as Array[PieceData.Rank],
}
var current_team: PieceData.Team = PieceData.Team.RED
var current_phase: int = 0  # Uses GameManager.GamePhase values
var game_mode: int = 0  # Uses GameManager.GameMode values
var first_team: PieceData.Team = PieceData.Team.RED
var winner: PieceData.Team = PieceData.Team.RED
var last_move_from: Vector2i = Vector2i(-1, -1)
var last_move_to: Vector2i = Vector2i(-1, -1)
var last_move_team: PieceData.Team = PieceData.Team.RED


func reset(mode: int, starting_team: PieceData.Team) -> void:
	game_mode = mode
	first_team = starting_team
	board_state.reset()
	captured_pieces[PieceData.Team.RED].clear()
	captured_pieces[PieceData.Team.BLUE].clear()
	last_move_from = Vector2i(-1, -1)
	last_move_to = Vector2i(-1, -1)
	current_team = PieceData.Team.RED


func register_unplaced_as_captured(team_to_check: PieceData.Team) -> void:
	var placed: Dictionary = {}
	for rank: int in PieceData.RANK_INFO:
		placed[rank] = 0
	for piece_id: int in board_state.pieces:
		var piece: Dictionary = board_state.pieces[piece_id]
		if piece["team"] == team_to_check:
			placed[piece["rank"]] += 1
	for rank: int in PieceData.RANK_INFO:
		var total: int = PieceData.RANK_INFO[rank]["count"]
		var missing: int = total - placed[rank]
		for i: int in range(missing):
			captured_pieces[team_to_check].append(rank)


static func validate_move(from: Vector2i, to: Vector2i, bs: BoardState) -> bool:
	var piece_id: int = bs.get_piece_at(from)
	if piece_id == -1:
		push_error("ILLEGAL MOVE: no piece at %s" % str(from))
		return false
	var valid_moves: Array[Vector2i] = bs.get_valid_moves(piece_id)
	if to not in valid_moves:
		var piece_info: Dictionary = bs.pieces[piece_id]
		push_error("ILLEGAL MOVE: piece %d (%s %s) at %s cannot move to %s. Valid: %s" % [
			piece_id,
			PieceData.get_team_name(piece_info["team"]),
			PieceData.get_rank_name(piece_info["rank"]),
			str(from), str(to), str(valid_moves)])
		return false
	return true


static func apply_move(from: Vector2i, to: Vector2i, bs: BoardState, caps: Dictionary) -> Dictionary:
	var piece_id: int = bs.get_piece_at(from)
	var result: Dictionary = { "combat": false, "flag_captured": false }

	# Reveal scouts that move more than one space
	var piece: Dictionary = bs.pieces[piece_id]
	var distance: int = abs(to.x - from.x) + abs(to.y - from.y)
	if piece["rank"] == PieceData.Rank.SCOUT and distance > 1:
		piece["revealed"] = true

	var target_id: int = bs.get_piece_at(to)

	if target_id == -1:
		bs.move_piece(piece_id, to)
	else:
		var attacker: Dictionary = bs.pieces[piece_id]
		var defender: Dictionary = bs.pieces[target_id]
		var atk_rank: PieceData.Rank = attacker["rank"]
		var def_rank: PieceData.Rank = defender["rank"]
		var atk_team: PieceData.Team = attacker["team"]
		var def_team: PieceData.Team = defender["team"]
		var combat_result: Combat.Result = Combat.resolve(atk_rank, def_rank)

		attacker["revealed"] = true
		defender["revealed"] = true

		match combat_result:
			Combat.Result.ATTACKER_WINS:
				caps[def_team].append(def_rank)
				bs.remove_piece(target_id)
				bs.move_piece(piece_id, to)
			Combat.Result.DEFENDER_WINS:
				caps[atk_team].append(atk_rank)
				bs.remove_piece(piece_id)
			Combat.Result.BOTH_DIE:
				caps[atk_team].append(atk_rank)
				caps[def_team].append(def_rank)
				bs.remove_piece(piece_id)
				bs.remove_piece(target_id)

		result["combat"] = true
		result["combat_info"] = {
			"atk_rank": atk_rank,
			"def_rank": def_rank,
			"atk_team": atk_team,
			"def_team": def_team,
			"result": combat_result,
			"pos": to,
		}

		if def_rank == PieceData.Rank.FLAG:
			result["flag_captured"] = true
			result["winner"] = atk_team

	return result


func next_team() -> PieceData.Team:
	if current_team == PieceData.Team.RED:
		return PieceData.Team.BLUE
	return PieceData.Team.RED
