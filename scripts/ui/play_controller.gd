extends Node

var board: Control


func setup(board_node: Control) -> void:
	board = board_node
	board.square_clicked.connect(_on_square_clicked)
	board.move_ready.connect(_on_move_ready)
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
			board.animate_move_with_combat(piece_id, from, pos)
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


func _on_move_ready(from: Vector2i, to: Vector2i) -> void:
	if GameManager.current_phase != GameManager.GamePhase.PLAY:
		return
	GameManager.execute_move(from, to)
	board.refresh()
