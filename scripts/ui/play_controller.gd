extends Node

var board: Control
var _pending_from: Vector2i = Vector2i.ZERO
var _pending_to: Vector2i = Vector2i.ZERO


func setup(board_node: Control) -> void:
	board = board_node
	board.square_clicked.connect(_on_square_clicked)
	board.animation_finished.connect(_on_animation_finished)
	GameManager.turn_changed.connect(_on_turn_changed)


func _on_turn_changed(_team: PieceData.Team) -> void:
	board.clear_selection()


func _on_square_clicked(pos: Vector2i) -> void:
	if GameManager.current_phase != GameManager.GamePhase.PLAY:
		return

	var clicked_id: int = GameManager.board_state.get_piece_at(pos)

	# If a piece is already selected
	if board.selected_piece_id != -1:
		var selected_piece: Dictionary = GameManager.board_state.pieces.get(board.selected_piece_id, {})

		# Clicking the same piece deselects
		if clicked_id == board.selected_piece_id:
			board.clear_selection()
			return

		# Clicking a valid move target — animate then execute
		if pos in board.valid_moves:
			var from: Vector2i = selected_piece["pos"]
			var piece_id: int = board.selected_piece_id
			board.clear_selection()
			_pending_from = from
			_pending_to = pos
			board.animate_move(piece_id, from, pos)
			return

		# Clicking another friendly piece selects it instead
		if clicked_id != -1:
			var clicked_piece: Dictionary = GameManager.board_state.pieces[clicked_id]
			if clicked_piece["team"] == GameManager.current_team and PieceData.can_move(clicked_piece["rank"]):
				board.select_piece(clicked_id)
				return

		# Clicking anything else deselects
		board.clear_selection()
		return

	# No piece selected — try to select one
	if clicked_id != -1:
		var piece: Dictionary = GameManager.board_state.pieces[clicked_id]
		if piece["team"] == GameManager.current_team and PieceData.can_move(piece["rank"]):
			board.select_piece(clicked_id)


func _on_animation_finished() -> void:
	if _pending_from != _pending_to:
		GameManager.execute_move(_pending_from, _pending_to)
		board.refresh()
		_pending_from = Vector2i.ZERO
		_pending_to = Vector2i.ZERO
