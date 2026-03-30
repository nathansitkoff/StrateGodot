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
var captured_pieces: Dictionary = {
	PieceData.Team.RED: [] as Array[PieceData.Rank],
	PieceData.Team.BLUE: [] as Array[PieceData.Rank],
}


func start_game(mode: GameMode) -> void:
	game_mode = mode
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
		# In AI_TEST mode, treat unplaced pieces as captured
		if game_mode == GameMode.AI_TEST:
			_register_unplaced_as_captured(PieceData.Team.RED)
			_register_unplaced_as_captured(PieceData.Team.BLUE)
		current_team = PieceData.Team.RED
		_set_phase(GamePhase.PLAY)
		turn_changed.emit(current_team)


func _register_unplaced_as_captured(team_to_check: PieceData.Team) -> void:
	# Count placed pieces per rank
	var placed: Dictionary = {}
	for rank: int in PieceData.RANK_INFO:
		placed[rank] = 0
	for piece_id: int in board_state.pieces:
		var piece: Dictionary = board_state.pieces[piece_id]
		if piece["team"] == team_to_check:
			placed[piece["rank"]] += 1
	# Add unplaced as captured
	for rank: int in PieceData.RANK_INFO:
		var total: int = PieceData.RANK_INFO[rank]["count"]
		var missing: int = total - placed[rank]
		for i: int in range(missing):
			captured_pieces[team_to_check].append(rank)


func execute_move(from: Vector2i, to: Vector2i) -> void:
	var piece_id: int = board_state.get_piece_at(from)
	if piece_id == -1:
		return

	last_move_from = from
	last_move_to = to
	last_move_team = current_team

	# Reveal scouts that move more than one space
	var piece: Dictionary = board_state.pieces[piece_id]
	var distance: int = abs(to.x - from.x) + abs(to.y - from.y)
	if piece["rank"] == PieceData.Rank.SCOUT and distance > 1:
		piece["revealed"] = true

	var target_id: int = board_state.get_piece_at(to)

	if target_id == -1:
		# Simple move
		board_state.move_piece(piece_id, to)
	else:
		# Combat — capture info before pieces are removed
		var attacker: Dictionary = board_state.pieces[piece_id]
		var defender: Dictionary = board_state.pieces[target_id]
		var atk_rank: PieceData.Rank = attacker["rank"]
		var def_rank: PieceData.Rank = defender["rank"]
		var atk_team: PieceData.Team = attacker["team"]
		var def_team: PieceData.Team = defender["team"]
		var result: Combat.Result = Combat.resolve(atk_rank, def_rank)

		# Reveal both pieces involved in combat
		attacker["revealed"] = true
		defender["revealed"] = true

		match result:
			Combat.Result.ATTACKER_WINS:
				captured_pieces[def_team].append(def_rank)
				board_state.remove_piece(target_id)
				board_state.move_piece(piece_id, to)
			Combat.Result.DEFENDER_WINS:
				captured_pieces[atk_team].append(atk_rank)
				board_state.remove_piece(piece_id)
			Combat.Result.BOTH_DIE:
				captured_pieces[atk_team].append(atk_rank)
				captured_pieces[def_team].append(def_rank)
				board_state.remove_piece(piece_id)
				board_state.remove_piece(target_id)

		var combat_info: Dictionary = {
			"atk_rank": atk_rank,
			"def_rank": def_rank,
			"atk_team": atk_team,
			"def_team": def_team,
			"result": result,
			"pos": to,
		}
		combat_occurred.emit(combat_info)

		# Check if flag was captured
		if def_rank == PieceData.Rank.FLAG:
			_end_game(atk_team)
			return

	end_turn()


func end_turn() -> void:
	var next_team: PieceData.Team
	if current_team == PieceData.Team.RED:
		next_team = PieceData.Team.BLUE
	else:
		next_team = PieceData.Team.RED

	# Check if next player can move
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


# Run a complete game headlessly. Returns the winning team.
# Uses separate board state to avoid disturbing the main state.
func run_headless_game(ai_red: AIPlayer, ai_blue: AIPlayer) -> PieceData.Team:
	var bs: BoardState = BoardState.new()
	var caps: Dictionary = {
		PieceData.Team.RED: [] as Array[PieceData.Rank],
		PieceData.Team.BLUE: [] as Array[PieceData.Rank],
	}

	# Temporarily swap in headless state
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

	# Setup
	ai_red.generate_setup(bs)
	ai_blue.generate_setup(bs)

	current_team = PieceData.Team.RED
	current_phase = GamePhase.PLAY

	# Play up to 2000 turns to prevent infinite games
	var result_winner: PieceData.Team = PieceData.Team.RED
	var game_over_flag: bool = false
	for turn: int in range(2000):
		var ai: AIPlayer = ai_red if current_team == PieceData.Team.RED else ai_blue
		var move: Dictionary = ai.choose_move(bs)
		if move.size() == 0:
			# Current player can't move, opponent wins
			result_winner = PieceData.Team.BLUE if current_team == PieceData.Team.RED else PieceData.Team.RED
			game_over_flag = true
			break

		var from: Vector2i = move["from"]
		var to: Vector2i = move["to"]
		var piece_id: int = bs.get_piece_at(from)

		last_move_from = from
		last_move_to = to
		last_move_team = current_team

		# Reveal scouts moving multiple squares
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

			if def_rank == PieceData.Rank.FLAG:
				result_winner = atk_team
				game_over_flag = true
				break

		# Notify opponent AI of the move
		var moved_piece_id: int = bs.get_piece_at(to)
		if moved_piece_id != -1:
			if current_team == PieceData.Team.RED:
				ai_blue.notify_move(moved_piece_id, PieceData.Team.RED)
			else:
				ai_red.notify_move(moved_piece_id, PieceData.Team.BLUE)

		# Switch turn
		var next: PieceData.Team = PieceData.Team.BLUE if current_team == PieceData.Team.RED else PieceData.Team.RED
		if not bs.has_movable_pieces(next):
			result_winner = current_team
			game_over_flag = true
			break
		current_team = next

	if not game_over_flag:
		# Draw after 2000 turns — call it a red win by default
		result_winner = PieceData.Team.RED

	# Restore original state
	board_state = old_bs
	captured_pieces = old_caps
	current_phase = old_phase
	current_team = old_team
	game_mode = old_mode
	last_move_from = old_from
	last_move_to = old_to
	last_move_team = old_move_team

	return result_winner
