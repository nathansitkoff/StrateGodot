extends Node

# Unified controller for all game modes. Owns piece selection state
# and click handling. Mode-specific behavior via callbacks.

var board: Control = null
var _selected_piece_id: int = -1
var _valid_moves: Array[Vector2i] = []

# Set by the mode to control behavior
var get_board_state: Callable  # () -> BoardState
var get_my_team: Callable  # () -> PieceData.Team
var is_my_turn: Callable  # () -> bool
var on_move: Callable  # (from: Vector2i, to: Vector2i) -> void


func setup(board_node: Control) -> void:
	board = board_node
	board.square_clicked.connect(_on_square_clicked)


func clear_selection() -> void:
	_selected_piece_id = -1
	_valid_moves.clear()
	if board != null:
		board.selected_piece_id = -1
		board.valid_moves.clear()
		board.queue_redraw()


func _on_square_clicked(pos: Vector2i) -> void:
	if not is_my_turn.call():
		return

	var bs: BoardState = get_board_state.call()
	var my_team: PieceData.Team = get_my_team.call()
	var clicked_id: int = bs.get_piece_at(pos)

	if _selected_piece_id != -1:
		var selected: Dictionary = bs.pieces.get(_selected_piece_id, {})

		# Clicking selected piece deselects
		if clicked_id == _selected_piece_id:
			clear_selection()
			return

		# Clicking a valid move target
		if pos in _valid_moves:
			var from: Vector2i = selected["pos"]
			clear_selection()
			on_move.call(from, pos)
			return

		# Clicking another friendly piece selects it
		if clicked_id != -1:
			var clicked: Dictionary = bs.pieces[clicked_id]
			if clicked["team"] == my_team and PieceData.can_move(clicked["rank"]):
				_select_piece(clicked_id, bs)
				return

		# Clicking anything else deselects
		clear_selection()
		return

	# No piece selected — try to select one
	if clicked_id != -1:
		var piece: Dictionary = bs.pieces[clicked_id]
		if piece["team"] == my_team and PieceData.can_move(piece["rank"]):
			_select_piece(clicked_id, bs)


func _select_piece(piece_id: int, bs: BoardState) -> void:
	_selected_piece_id = piece_id
	_valid_moves = bs.get_valid_moves(piece_id)
	# Update board visuals
	board.selected_piece_id = piece_id
	board.valid_moves = _valid_moves
	board.queue_redraw()
