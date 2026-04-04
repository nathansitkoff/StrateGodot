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
	board.handle_click(pos, GameManager.board_state, GameManager.current_team, _do_move)


func _do_move(from: Vector2i, to: Vector2i) -> void:
	var piece_id: int = GameManager.board_state.get_piece_at(from)
	board.animate_move_with_combat(piece_id, from, to)


func _on_move_ready(from: Vector2i, to: Vector2i) -> void:
	if GameManager.current_phase != GameManager.GamePhase.PLAY:
		return
	GameManager.execute_move(from, to)
	board.refresh()
