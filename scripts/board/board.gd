extends Control

signal square_clicked(pos: Vector2i)

const BOARD_SIZE: int = 10
const BOARD_COLORS: Dictionary = {
	"light": Color(0.82, 0.76, 0.62),
	"dark": Color(0.55, 0.48, 0.36),
	"lake_light": Color(0.25, 0.45, 0.7),
	"lake_dark": Color(0.18, 0.35, 0.58),
	"board_border": Color(0.25, 0.2, 0.15),
	"grid": Color(0.4, 0.35, 0.28, 0.4),
	"highlight": Color(0.3, 0.75, 0.3, 0.45),
	"selected": Color(1.0, 0.9, 0.2, 0.45),
	"red_piece": Color(0.8, 0.2, 0.2),
	"blue_piece": Color(0.2, 0.3, 0.8),
	"hidden_piece": Color(0.5, 0.5, 0.5),
	"last_move": Color(1.0, 0.5, 0.0),
}

var cell_size: float = 60.0
var board_offset: Vector2 = Vector2.ZERO
var selected_piece_id: int = -1
var valid_moves: Array[Vector2i] = []
var last_enemy_move: Vector2i = Vector2i(-1, -1)


func _ready() -> void:
	_calculate_layout()


func _calculate_layout() -> void:
	var available: Vector2 = size
	cell_size = min(available.x, available.y) / BOARD_SIZE
	board_offset = Vector2(
		(available.x - cell_size * BOARD_SIZE) / 2.0,
		(available.y - cell_size * BOARD_SIZE) / 2.0,
	)


func _draw() -> void:
	_calculate_layout()

	# Draw board border
	var board_rect: Rect2 = Rect2(
		board_offset - Vector2(3, 3),
		Vector2(cell_size * BOARD_SIZE + 6, cell_size * BOARD_SIZE + 6),
	)
	draw_rect(board_rect, BOARD_COLORS["board_border"])

	# Draw board squares
	for col: int in range(BOARD_SIZE):
		for row: int in range(BOARD_SIZE):
			var pos: Vector2i = Vector2i(col, row)
			var rect: Rect2 = _get_cell_rect(pos)

			# Cell color
			if GameManager.board_state.is_lake(pos):
				# Lake gradient: lighter at top, darker at bottom
				var t: float = float(row - 4) / 1.0  # 0.0 for row 4, 1.0 for row 5
				var lake_color: Color = BOARD_COLORS["lake_light"].lerp(BOARD_COLORS["lake_dark"], clamp(t, 0.0, 1.0))
				draw_rect(rect, lake_color)
				# Wave lines on lake
				var wave_y1: float = rect.position.y + rect.size.y * 0.35
				var wave_y2: float = rect.position.y + rect.size.y * 0.65
				var wave_color: Color = Color(1.0, 1.0, 1.0, 0.12)
				draw_line(Vector2(rect.position.x + 4, wave_y1), Vector2(rect.position.x + rect.size.x - 4, wave_y1), wave_color, 1.0)
				draw_line(Vector2(rect.position.x + 4, wave_y2), Vector2(rect.position.x + rect.size.x - 4, wave_y2), wave_color, 1.0)
			else:
				var base: Color
				if (col + row) % 2 == 0:
					base = BOARD_COLORS["light"]
				else:
					base = BOARD_COLORS["dark"]
				draw_rect(rect, base)

			# Highlight selected piece
			if selected_piece_id != -1:
				var sel_piece: Dictionary = GameManager.board_state.pieces.get(selected_piece_id, {})
				if sel_piece.get("pos") == pos:
					draw_rect(rect, BOARD_COLORS["selected"])

			# Highlight valid moves
			if pos in valid_moves:
				draw_rect(rect, BOARD_COLORS["highlight"])

			# Highlight last enemy move
			if pos == last_enemy_move:
				draw_rect(rect.grow(-4.0), BOARD_COLORS["last_move"], false, 8.0)

			# Subtle grid lines
			draw_rect(rect, BOARD_COLORS["grid"], false, 1.0)

	# Draw pieces
	_draw_pieces()


func _get_viewing_team() -> PieceData.Team:
	match GameManager.current_phase:
		GameManager.GamePhase.SETUP_RED:
			return PieceData.Team.RED
		GameManager.GamePhase.SETUP_BLUE:
			return PieceData.Team.BLUE
		_:
			# In AI modes, human is always Red
			if GameManager.game_mode == GameManager.GameMode.VS_AI or GameManager.game_mode == GameManager.GameMode.AI_TEST:
				return PieceData.Team.RED
			return GameManager.current_team


func _draw_pieces() -> void:
	var viewing_team: PieceData.Team = _get_viewing_team()
	var board: BoardState = GameManager.board_state
	var see_all: bool = GameManager.game_mode == GameManager.GameMode.AI_TEST or GameManager.game_mode == GameManager.GameMode.AI_VS_AI

	for piece_id: int in board.pieces:
		var piece: Dictionary = board.pieces[piece_id]
		var pos: Vector2i = piece["pos"]
		var rect: Rect2 = _get_cell_rect(pos)
		var piece_rect: Rect2 = rect.grow(-4.0)

		var is_own: bool = piece["team"] == viewing_team or see_all
		var is_revealed: bool = piece["revealed"]

		# Piece background color
		var bg_color: Color
		if piece["team"] == PieceData.Team.RED:
			bg_color = BOARD_COLORS["red_piece"]
		elif piece["team"] == PieceData.Team.BLUE:
			if is_own or is_revealed:
				bg_color = BOARD_COLORS["blue_piece"]
			else:
				bg_color = BOARD_COLORS["hidden_piece"]
		else:
			bg_color = BOARD_COLORS["hidden_piece"]

		# Draw piece rectangle
		draw_rect(piece_rect, bg_color)
		draw_rect(piece_rect, Color(0.1, 0.1, 0.1), false, 2.0)
		# Revealed indicator: yellow circle in top-right corner
		if is_own and is_revealed:
			var marker_radius: float = cell_size * 0.12
			var marker_pos: Vector2 = Vector2(
				piece_rect.position.x + piece_rect.size.x - marker_radius - 2.0,
				piece_rect.position.y + marker_radius + 2.0,
			)
			draw_circle(marker_pos, marker_radius, Color(1.0, 0.85, 0.0))

		# Draw rank text if visible
		if is_own or is_revealed:
			var rank_text: String = PieceData.get_rank_display(piece["rank"])
			var font: Font = ThemeDB.fallback_font
			var font_size: int = int(cell_size * 0.4)
			var text_size: Vector2 = font.get_string_size(rank_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
			var text_pos: Vector2 = Vector2(
				piece_rect.position.x + (piece_rect.size.x - text_size.x) / 2.0,
				piece_rect.position.y + (piece_rect.size.y + text_size.y) / 2.0 - 2.0,
			)
			draw_string(font, text_pos, rank_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)


func _get_cell_rect(pos: Vector2i) -> Rect2:
	return Rect2(
		board_offset + Vector2(pos.x * cell_size, pos.y * cell_size),
		Vector2(cell_size, cell_size),
	)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var pos: Vector2i = _pixel_to_cell(mb.position)
			if GameManager.board_state.is_in_bounds(pos):
				square_clicked.emit(pos)


func _pixel_to_cell(pixel: Vector2) -> Vector2i:
	var local: Vector2 = pixel - board_offset
	return Vector2i(int(local.x / cell_size), int(local.y / cell_size))


func select_piece(piece_id: int) -> void:
	selected_piece_id = piece_id
	if piece_id != -1:
		valid_moves = GameManager.board_state.get_valid_moves(piece_id)
	else:
		valid_moves.clear()
	queue_redraw()


func clear_selection() -> void:
	selected_piece_id = -1
	valid_moves.clear()
	queue_redraw()


func refresh() -> void:
	# Show last enemy move highlight if the last move was from the other team
	var viewing: PieceData.Team = _get_viewing_team()
	if GameManager.last_move_team != viewing and GameManager.last_move_to != Vector2i(-1, -1):
		last_enemy_move = GameManager.last_move_to
	else:
		last_enemy_move = Vector2i(-1, -1)
	queue_redraw()
