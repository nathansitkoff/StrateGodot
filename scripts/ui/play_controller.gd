extends Node

var board: Control
var _pending_from: Vector2i = Vector2i.ZERO
var _pending_to: Vector2i = Vector2i.ZERO


func setup(board_node: Control) -> void:
	board = board_node
	board.square_clicked.connect(_on_square_clicked)
	board.animation_finished.connect(_on_animation_finished)
	board.combat_animation_finished.connect(_on_combat_animation_finished)
	GameManager.turn_changed.connect(_on_turn_changed)


func _on_turn_changed(_team: PieceData.Team) -> void:
	board.clear_selection()


func _on_square_clicked(pos: Vector2i) -> void:
	if GameManager.current_phase != GameManager.GamePhase.PLAY:
		return

	var clicked_id: int = GameManager.board_state.get_piece_at(pos)

	if board.selected_piece_id != -1:
		var selected_piece: Dictionary = GameManager.board_state.pieces.get(board.selected_piece_id, {})

		if clicked_id == board.selected_piece_id:
			board.clear_selection()
			return

		if pos in board.valid_moves:
			var from: Vector2i = selected_piece["pos"]
			var piece_id: int = board.selected_piece_id
			board.clear_selection()
			_pending_from = from
			_pending_to = pos
			board.animate_move(piece_id, from, pos)
			return

		if clicked_id != -1:
			var clicked_piece: Dictionary = GameManager.board_state.pieces[clicked_id]
			if clicked_piece["team"] == GameManager.current_team and PieceData.can_move(clicked_piece["rank"]):
				board.select_piece(clicked_id)
				return

		board.clear_selection()
		return

	if clicked_id != -1:
		var piece: Dictionary = GameManager.board_state.pieces[clicked_id]
		if piece["team"] == GameManager.current_team and PieceData.can_move(piece["rank"]):
			board.select_piece(clicked_id)


func _on_animation_finished() -> void:
	if _pending_from == _pending_to:
		return
	if not _is_human_turn():
		return
	_try_execute_or_animate_combat()


func _on_combat_animation_finished() -> void:
	if _pending_from == _pending_to:
		return
	if not _is_human_turn():
		return
	GameManager.execute_move(_pending_from, _pending_to)
	board.refresh()
	_pending_from = Vector2i.ZERO
	_pending_to = Vector2i.ZERO


func _try_execute_or_animate_combat() -> void:
	var target_id: int = GameManager.board_state.get_piece_at(_pending_to)
	if target_id != -1:
		# Combat will happen — pre-calculate result and animate
		var attacker_id: int = GameManager.board_state.get_piece_at(_pending_from)
		var atk_rank: PieceData.Rank = GameManager.board_state.pieces[attacker_id]["rank"]
		var def_rank: PieceData.Rank = GameManager.board_state.pieces[target_id]["rank"]
		var result: Combat.Result = Combat.resolve(atk_rank, def_rank)

		var loser1: int = -1
		var loser2: int = -1
		match result:
			Combat.Result.ATTACKER_WINS:
				loser1 = target_id
			Combat.Result.DEFENDER_WINS:
				loser1 = attacker_id
			Combat.Result.BOTH_DIE:
				loser1 = target_id
				loser2 = attacker_id

		board.start_combat_animation(_pending_to, loser1, loser2)
	else:
		# No combat — execute immediately
		GameManager.execute_move(_pending_from, _pending_to)
		board.refresh()
		_pending_from = Vector2i.ZERO
		_pending_to = Vector2i.ZERO


func _is_human_turn() -> bool:
	# Check if current turn belongs to a human (not AI)
	return GameManager.current_phase == GameManager.GamePhase.PLAY
