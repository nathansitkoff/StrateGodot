extends Node

const GameStateClass: GDScript = preload("res://scripts/data/game_state.gd")

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

var state: RefCounted = GameStateClass.new()
var recorder: GameRecorder = null

# Proxy properties for backward compatibility
var current_phase: GamePhase:
	get: return state.current_phase as GamePhase
	set(v): state.current_phase = v
var current_team: PieceData.Team:
	get: return state.current_team
	set(v): state.current_team = v
var game_mode: GameMode:
	get: return state.game_mode as GameMode
	set(v): state.game_mode = v
var board_state: BoardState:
	get: return state.board_state
	set(v): state.board_state = v
var winner: PieceData.Team:
	get: return state.winner
	set(v): state.winner = v
var last_move_from: Vector2i:
	get: return state.last_move_from
	set(v): state.last_move_from = v
var last_move_to: Vector2i:
	get: return state.last_move_to
	set(v): state.last_move_to = v
var last_move_team: PieceData.Team:
	get: return state.last_move_team
	set(v): state.last_move_team = v
var first_team: PieceData.Team:
	get: return state.first_team
	set(v): state.first_team = v
var captured_pieces: Dictionary:
	get: return state.captured_pieces
	set(v): state.captured_pieces = v


func start_game(mode: GameMode, starting_team: PieceData.Team = PieceData.Team.RED) -> void:
	state.reset(mode, starting_team)
	_set_phase(GamePhase.SETUP_RED)


func finish_setup(team: PieceData.Team) -> void:
	if team == PieceData.Team.RED:
		_set_phase(GamePhase.SETUP_BLUE)
	else:
		if game_mode == GameMode.AI_TEST:
			state.register_unplaced_as_captured(PieceData.Team.RED)
			state.register_unplaced_as_captured(PieceData.Team.BLUE)
		current_team = first_team
		_set_phase(GamePhase.PLAY)
		turn_changed.emit(current_team)


func validate_move(from: Vector2i, to: Vector2i, bs: BoardState) -> bool:
	return GameStateClass.validate_move(from, to, bs)


func apply_move(from: Vector2i, to: Vector2i, bs: BoardState, caps: Dictionary) -> Dictionary:
	return GameStateClass.apply_move(from, to, bs, caps)


func execute_move(from: Vector2i, to: Vector2i) -> void:
	if not validate_move(from, to, board_state):
		return

	last_move_from = from
	last_move_to = to
	last_move_team = current_team

	if recorder != null:
		recorder.record_move(from, to)

	var move_result: Dictionary = apply_move(from, to, board_state, captured_pieces)

	if recorder != null:
		recorder.record_checksum(board_state)

	if move_result["combat"]:
		combat_occurred.emit(move_result["combat_info"])

	if move_result["flag_captured"]:
		_end_game(move_result["winner"])
		return

	end_turn()


func end_turn() -> void:
	var next: PieceData.Team = state.next_team()

	if not board_state.has_movable_pieces(next):
		_end_game(current_team)
		return

	current_team = next
	turn_changed.emit(current_team)


func _set_phase(phase: GamePhase) -> void:
	current_phase = phase
	phase_changed.emit(phase)


func _end_game(winning_team: PieceData.Team) -> void:
	winner = winning_team
	_set_phase(GamePhase.GAME_OVER)
	game_ended.emit(winner)


# Run a complete game headlessly. Returns a result dictionary.
func run_headless_game(ai_red: AIBase, ai_blue: AIBase, starting_team: PieceData.Team = PieceData.Team.RED, game_recorder: GameRecorder = null) -> Dictionary:
	# Save current state
	var old_state: RefCounted = state

	# Create fresh state for headless game
	state = GameStateClass.new()
	state.reset(GameMode.AI_HEADLESS, starting_team)

	ai_red.reset()
	ai_blue.reset()

	ai_red.generate_setup(board_state)
	ai_blue.generate_setup(board_state)

	if game_recorder != null:
		game_recorder.record_placements_from_board(board_state)
		game_recorder.record_checksum(board_state)

	current_team = starting_team
	current_phase = GamePhase.PLAY

	var result_winner: int = -1
	var result_reason: String = "timeout"
	var turn_count: int = 0
	var game_over_flag: bool = false

	for turn: int in range(2000):
		turn_count = turn
		var ai: AIBase = ai_red if current_team == PieceData.Team.RED else ai_blue
		var move: Dictionary = ai.choose_move(board_state)
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

		if not validate_move(from, to, board_state):
			result_reason = "illegal_move"
			game_over_flag = true
			break

		if game_recorder != null:
			game_recorder.record_move(from, to)

		var move_result: Dictionary = apply_move(from, to, board_state, captured_pieces)

		if game_recorder != null:
			game_recorder.record_checksum(board_state)

		if move_result["flag_captured"]:
			result_winner = move_result["winner"]
			result_reason = "flag_captured"
			game_over_flag = true
			break

		var moved_piece_id: int = board_state.get_piece_at(to)
		if moved_piece_id != -1 and board_state.pieces[moved_piece_id]["team"] == current_team:
			if current_team == PieceData.Team.RED:
				ai_blue.notify_move(moved_piece_id, PieceData.Team.RED)
			else:
				ai_red.notify_move(moved_piece_id, PieceData.Team.BLUE)

		var next: PieceData.Team = state.next_team()
		if not board_state.has_movable_pieces(next):
			result_winner = current_team
			result_reason = "opponent_stuck"
			game_over_flag = true
			break
		current_team = next

	if not game_over_flag:
		result_reason = "timeout"

	var result_last_team: PieceData.Team = last_move_team

	# Restore original state
	state = old_state

	return {
		"winner": result_winner,
		"reason": result_reason,
		"turns": turn_count,
		"last_team": result_last_team,
	}
