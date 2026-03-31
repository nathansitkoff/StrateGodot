extends Node

enum GamePhase {
	MENU,
	SETUP_RED,
	SETUP_BLUE,
	PLAY,
	GAME_OVER,
}

enum GameMode {
	LOCAL_2P,
	VS_AI,
	AI_TEST,
	AI_VS_AI,
	AI_HEADLESS,
}

signal phase_changed(phase: GamePhase)
signal turn_changed(team: PieceData.Team)
signal combat_occurred(combat_info: Dictionary)
signal game_ended(winner: PieceData.Team)

var current_phase: GamePhase = GamePhase.MENU
var current_team: PieceData.Team = PieceData.Team.RED
var game_mode: GameMode = GameMode.LOCAL_2P
var board_state: BoardState = BoardState.new()
var winner: PieceData.Team = PieceData.Team.RED
var last_move_from: Vector2i = Vector2i(-1, -1)
var last_move_to: Vector2i = Vector2i(-1, -1)
var last_move_team: PieceData.Team = PieceData.Team.RED
var first_team: PieceData.Team = PieceData.Team.RED
var captured_pieces: Dictionary = {
	PieceData.Team.RED: [] as Array[PieceData.Rank],
	PieceData.Team.BLUE: [] as Array[PieceData.Rank],
}


func start_game(mode: GameMode, starting_team: PieceData.Team = PieceData.Team.RED) -> void:
	game_mode = mode
	first_team = starting_team
	board_state.reset()
	captured_pieces[PieceData.Team.RED].clear()
	captured_pieces[PieceData.Team.BLUE].clear()
	last_move_from = Vector2i(-1, -1)
	last_move_to = Vector2i(-1, -1)
	current_team = PieceData.Team.RED
	_set_phase(GamePhase.SETUP_RED)


func finish_setup(team: PieceData.Team) -> void:
	if team == PieceData.Team.RED:
		_set_phase(GamePhase.SETUP_BLUE)
	else:
		if game_mode == GameMode.AI_TEST:
			_register_unplaced_as_captured(PieceData.Team.RED)
			_register_unplaced_as_captured(PieceData.Team.BLUE)
		current_team = first_team
		_set_phase(GamePhase.PLAY)
		turn_changed.emit(current_team)


func _register_unplaced_as_captured(team_to_check: PieceData.Team) -> void:
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


# Apply a move on a given board state and captured pieces dict.
# Returns a result dict: { "combat": bool, "combat_info": Dictionary, "flag_captured": bool, "winner": Team }
# This is the single source of truth for move/combat logic.
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


func execute_move(from: Vector2i, to: Vector2i) -> void:
	var piece_id: int = board_state.get_piece_at(from)
	if piece_id == -1:
		return

	last_move_from = from
	last_move_to = to
	last_move_team = current_team

	var move_result: Dictionary = apply_move(from, to, board_state, captured_pieces)

	if move_result["combat"]:
		combat_occurred.emit(move_result["combat_info"])

	if move_result["flag_captured"]:
		_end_game(move_result["winner"])
		return

	end_turn()


func end_turn() -> void:
	var next_team: PieceData.Team
	if current_team == PieceData.Team.RED:
		next_team = PieceData.Team.BLUE
	else:
		next_team = PieceData.Team.RED

	if not board_state.has_movable_pieces(next_team):
		_end_game(current_team)
		return

	current_team = next_team
	turn_changed.emit(current_team)


func _set_phase(phase: GamePhase) -> void:
	current_phase = phase
	phase_changed.emit(phase)


func _end_game(winning_team: PieceData.Team) -> void:
	winner = winning_team
	_set_phase(GamePhase.GAME_OVER)
	game_ended.emit(winner)


# Run a complete game headlessly. Returns a result dictionary.
func run_headless_game(ai_red: AIBase, ai_blue: AIBase, starting_team: PieceData.Team = PieceData.Team.RED) -> Dictionary:
	var bs: BoardState = BoardState.new()
	var caps: Dictionary = {
		PieceData.Team.RED: [] as Array[PieceData.Rank],
		PieceData.Team.BLUE: [] as Array[PieceData.Rank],
	}

	# Temporarily swap in headless state (needed for AI deduction reading GameManager.captured_pieces)
	var old_bs: BoardState = board_state
	var old_caps: Dictionary = captured_pieces
	var old_phase: GamePhase = current_phase
	var old_team: PieceData.Team = current_team
	var old_mode: GameMode = game_mode
	var old_from: Vector2i = last_move_from
	var old_to: Vector2i = last_move_to
	var old_move_team: PieceData.Team = last_move_team

	board_state = bs
	captured_pieces = caps
	game_mode = GameMode.AI_HEADLESS
	last_move_from = Vector2i(-1, -1)
	last_move_to = Vector2i(-1, -1)

	ai_red.reset()
	ai_blue.reset()

	# Setup — each AI uses its own placement strategy
	ai_red.generate_setup(bs)
	ai_blue.generate_setup(bs)

	current_team = starting_team
	current_phase = GamePhase.PLAY

	var result_winner: int = -1
	var result_reason: String = "timeout"
	var turn_count: int = 0
	var game_over_flag: bool = false

	for turn: int in range(2000):
		turn_count = turn
		var ai: AIBase = ai_red if current_team == PieceData.Team.RED else ai_blue
		var move: Dictionary = ai.choose_move(bs)
		if move.size() == 0:
			result_winner = PieceData.Team.BLUE if current_team == PieceData.Team.RED else PieceData.Team.RED
			result_reason = "no_moves"
			game_over_flag = true
			break

		var from: Vector2i = move["from"]
		var to: Vector2i = move["to"]

		last_move_from = from
		last_move_to = to
		last_move_team = current_team

		var move_result: Dictionary = apply_move(from, to, bs, caps)

		if move_result["flag_captured"]:
			result_winner = move_result["winner"]
			result_reason = "flag_captured"
			game_over_flag = true
			break

		# Notify opponent AI of the move (only if mover survived)
		var moved_piece_id: int = bs.get_piece_at(to)
		if moved_piece_id != -1 and bs.pieces[moved_piece_id]["team"] == current_team:
			if current_team == PieceData.Team.RED:
				ai_blue.notify_move(moved_piece_id, PieceData.Team.RED)
			else:
				ai_red.notify_move(moved_piece_id, PieceData.Team.BLUE)

		# Switch turn
		var next: PieceData.Team = PieceData.Team.BLUE if current_team == PieceData.Team.RED else PieceData.Team.RED
		if not bs.has_movable_pieces(next):
			result_winner = current_team
			result_reason = "opponent_stuck"
			game_over_flag = true
			break
		current_team = next

	if not game_over_flag:
		result_reason = "timeout"

	# Restore original state
	board_state = old_bs
	captured_pieces = old_caps
	current_phase = old_phase
	current_team = old_team
	game_mode = old_mode
	last_move_from = old_from
	last_move_to = old_to
	last_move_team = old_move_team

	return {
		"winner": result_winner,
		"reason": result_reason,
		"turns": turn_count,
	}
