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
}

signal phase_changed(phase: GamePhase)
signal turn_changed(team: PieceData.Team)
signal combat_occurred(attacker_id: int, defender_id: int, result: Combat.Result, pos: Vector2i)
signal game_ended(winner: PieceData.Team)

var current_phase: GamePhase = GamePhase.MENU
var current_team: PieceData.Team = PieceData.Team.RED
var game_mode: GameMode = GameMode.LOCAL_2P
var board_state: BoardState = BoardState.new()
var winner: PieceData.Team = PieceData.Team.RED
var captured_pieces: Dictionary = {
	PieceData.Team.RED: [] as Array[PieceData.Rank],
	PieceData.Team.BLUE: [] as Array[PieceData.Rank],
}


func start_game(mode: GameMode) -> void:
	game_mode = mode
	board_state.reset()
	captured_pieces[PieceData.Team.RED].clear()
	captured_pieces[PieceData.Team.BLUE].clear()
	current_team = PieceData.Team.RED
	_set_phase(GamePhase.SETUP_RED)


func finish_setup(team: PieceData.Team) -> void:
	if team == PieceData.Team.RED:
		_set_phase(GamePhase.SETUP_BLUE)
	else:
		current_team = PieceData.Team.RED
		_set_phase(GamePhase.PLAY)
		turn_changed.emit(current_team)


func execute_move(from: Vector2i, to: Vector2i) -> void:
	var piece_id: int = board_state.get_piece_at(from)
	if piece_id == -1:
		return

	var target_id: int = board_state.get_piece_at(to)

	if target_id == -1:
		# Simple move
		board_state.move_piece(piece_id, to)
	else:
		# Combat
		var attacker: Dictionary = board_state.pieces[piece_id]
		var defender: Dictionary = board_state.pieces[target_id]
		var result: Combat.Result = Combat.resolve(attacker["rank"], defender["rank"])

		# Reveal both pieces involved in combat
		attacker["revealed"] = true
		defender["revealed"] = true

		match result:
			Combat.Result.ATTACKER_WINS:
				captured_pieces[defender["team"]].append(defender["rank"])
				board_state.remove_piece(target_id)
				board_state.move_piece(piece_id, to)
			Combat.Result.DEFENDER_WINS:
				captured_pieces[attacker["team"]].append(attacker["rank"])
				board_state.remove_piece(piece_id)
			Combat.Result.BOTH_DIE:
				captured_pieces[attacker["team"]].append(attacker["rank"])
				captured_pieces[defender["team"]].append(defender["rank"])
				board_state.remove_piece(piece_id)
				board_state.remove_piece(target_id)

		combat_occurred.emit(piece_id, target_id, result, to)

		# Check if flag was captured
		if defender["rank"] == PieceData.Rank.FLAG:
			_end_game(attacker["team"])
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
