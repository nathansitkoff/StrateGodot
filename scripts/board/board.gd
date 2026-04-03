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
	var bs: BoardState = GameManager.board_state
	var see_all: bool = GameManager.game_mode == GameManager.GameMode.AI_TEST or GameManager.game_mode == GameManager.GameMode.AI_VS_AI

	for piece_id: int in bs.pieces:
		var piece: Dictionary = bs.pieces[piece_id]
		var pos: Vector2i = piece["pos"]
		var rect: Rect2 = _get_cell_rect(pos)
		var piece_rect: Rect2 = rect.grow(-3.0)
		var radius: float = cell_size * 0.12

		var is_own: bool = piece["team"] == viewing_team or see_all
		var is_revealed: bool = piece["revealed"]
		var rank: PieceData.Rank = piece["rank"]

		# Piece background
		var bg_color: Color
		var border_color: Color
		if piece["team"] == PieceData.Team.RED and (is_own or is_revealed):
			bg_color = BOARD_COLORS["red_piece"]
			border_color = Color(0.5, 0.1, 0.1)
		elif piece["team"] == PieceData.Team.BLUE and (is_own or is_revealed):
			bg_color = BOARD_COLORS["blue_piece"]
			border_color = Color(0.1, 0.15, 0.5)
		else:
			bg_color = BOARD_COLORS["hidden_piece"]
			border_color = Color(0.3, 0.3, 0.3)

		# Rounded rectangle background
		_draw_rounded_rect(piece_rect, bg_color, radius)
		# Border
		_draw_rounded_rect_outline(piece_rect, border_color, radius, 2.0)

		# Revealed indicator
		if is_own and is_revealed:
			var marker_radius: float = cell_size * 0.1
			var marker_pos: Vector2 = Vector2(
				piece_rect.position.x + piece_rect.size.x - marker_radius - 3.0,
				piece_rect.position.y + marker_radius + 3.0,
			)
			draw_circle(marker_pos, marker_radius + 1.0, Color(0.2, 0.2, 0.2))
			draw_circle(marker_pos, marker_radius, Color(1.0, 0.85, 0.0))

		# Draw rank content if visible
		if is_own or is_revealed:
			var s: float = cell_size
			var icon_cx: float = piece_rect.position.x + piece_rect.size.x * 0.45
			var icon_cy: float = piece_rect.position.y + piece_rect.size.y * 0.55

			# Rank number in top-right corner (except Flag and Bomb)
			if rank != PieceData.Rank.FLAG and rank != PieceData.Rank.BOMB:
				var rank_text: String = PieceData.get_rank_display(rank)
				var font: Font = ThemeDB.fallback_font
				var fs: int = int(s * 0.22)
				# Shadow
				draw_string(font, Vector2(piece_rect.position.x + piece_rect.size.x - s * 0.28 + 1, piece_rect.position.y + s * 0.2 + 1), rank_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.5))
				# Text
				draw_string(font, Vector2(piece_rect.position.x + piece_rect.size.x - s * 0.28, piece_rect.position.y + s * 0.2), rank_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)

			# Centered icon
			match rank:
				PieceData.Rank.FLAG:
					_draw_flag_icon(icon_cx, icon_cy, s)
				PieceData.Rank.BOMB:
					_draw_bomb_icon(icon_cx, icon_cy, s)
				PieceData.Rank.SPY:
					_draw_spy_icon(icon_cx, icon_cy, s)
				PieceData.Rank.SCOUT:
					_draw_scout_icon(icon_cx, icon_cy, s)
				PieceData.Rank.MINER:
					_draw_miner_icon(icon_cx, icon_cy, s)
				PieceData.Rank.SERGEANT:
					_draw_sergeant_icon(icon_cx, icon_cy, s)
				PieceData.Rank.LIEUTENANT:
					_draw_lieutenant_icon(icon_cx, icon_cy, s)
				PieceData.Rank.CAPTAIN:
					_draw_captain_icon(icon_cx, icon_cy, s)
				PieceData.Rank.MAJOR:
					_draw_major_icon(icon_cx, icon_cy, s)
				PieceData.Rank.COLONEL:
					_draw_colonel_icon(icon_cx, icon_cy, s)
				PieceData.Rank.GENERAL:
					_draw_general_icon(icon_cx, icon_cy, s)
				PieceData.Rank.MARSHAL:
					_draw_marshal_icon(icon_cx, icon_cy, s)


# --- Icons ---


func _draw_flag_icon(cx: float, cy: float, s: float) -> void:
	# Pole
	var pole_top: Vector2 = Vector2(cx - s * 0.1, cy - s * 0.18)
	var pole_bottom: Vector2 = Vector2(cx - s * 0.1, cy + s * 0.18)
	draw_line(pole_top, pole_bottom, Color.WHITE, 2.0)
	# Pennant triangle
	var p1: Vector2 = pole_top
	var p2: Vector2 = Vector2(cx + s * 0.15, cy - s * 0.1)
	var p3: Vector2 = Vector2(cx - s * 0.1, cy - s * 0.02)
	draw_colored_polygon(PackedVector2Array([p1, p2, p3]), Color(1.0, 0.9, 0.3))


func _draw_bomb_icon(cx: float, cy: float, s: float) -> void:
	# Body circle
	var r: float = s * 0.14
	draw_circle(Vector2(cx, cy + s * 0.02), r, Color(0.9, 0.85, 0.7))
	draw_circle(Vector2(cx, cy + s * 0.02), r, Color.WHITE, false, 1.5)
	# Fuse lines radiating from top
	var fuse_len: float = s * 0.08
	for angle: float in [-0.5, 0.0, 0.5]:
		var dir: Vector2 = Vector2(sin(angle), -cos(angle))
		var start: Vector2 = Vector2(cx, cy + s * 0.02) + dir * r
		var end: Vector2 = start + dir * fuse_len
		draw_line(start, end, Color(1.0, 0.7, 0.2), 1.5)


func _draw_spy_icon(cx: float, cy: float, s: float) -> void:
	# Eye shape: oval outline + pupil
	var w: float = s * 0.16
	var h: float = s * 0.08
	# Draw eye outline using two arcs approximated as polygons
	var top_points: PackedVector2Array = PackedVector2Array()
	var bot_points: PackedVector2Array = PackedVector2Array()
	var segments: int = 8
	for i: int in range(segments + 1):
		var t: float = float(i) / float(segments)
		var x: float = cx - w + t * w * 2
		top_points.append(Vector2(x, cy - sin(t * PI) * h))
		bot_points.append(Vector2(x, cy + sin(t * PI) * h))
	# Draw filled eye
	var eye_points: PackedVector2Array = PackedVector2Array()
	eye_points.append_array(top_points)
	var reversed_bot: PackedVector2Array = PackedVector2Array()
	for i: int in range(bot_points.size() - 1, -1, -1):
		reversed_bot.append(bot_points[i])
	eye_points.append_array(reversed_bot)
	draw_colored_polygon(eye_points, Color(1.0, 1.0, 1.0, 0.3))
	# Outline
	for i: int in range(top_points.size() - 1):
		draw_line(top_points[i], top_points[i + 1], Color.WHITE, 1.5)
		draw_line(bot_points[i], bot_points[i + 1], Color.WHITE, 1.5)
	# Pupil
	draw_circle(Vector2(cx, cy), s * 0.04, Color.WHITE)


func _draw_scout_icon(cx: float, cy: float, s: float) -> void:
	# Arrow pointing up (forward)
	var h: float = s * 0.12
	var w: float = s * 0.08
	draw_line(Vector2(cx, cy - h), Vector2(cx, cy + h), Color.WHITE, 2.0)
	draw_line(Vector2(cx, cy - h), Vector2(cx - w, cy - h + w), Color.WHITE, 2.0)
	draw_line(Vector2(cx, cy - h), Vector2(cx + w, cy - h + w), Color.WHITE, 2.0)


func _draw_miner_icon(cx: float, cy: float, s: float) -> void:
	# Pickaxe: longer handle + larger head
	var handle_len: float = s * 0.18
	draw_line(Vector2(cx - handle_len * 0.6, cy + handle_len * 0.6), Vector2(cx + handle_len * 0.5, cy - handle_len * 0.5), Color.WHITE, 2.0)
	# Head — wider curved blade
	draw_line(Vector2(cx + handle_len * 0.1, cy - handle_len * 0.7), Vector2(cx + handle_len * 0.5, cy - handle_len * 0.5), Color.WHITE, 2.5)
	draw_line(Vector2(cx + handle_len * 0.5, cy - handle_len * 0.5), Vector2(cx + handle_len * 0.8, cy - handle_len * 0.05), Color.WHITE, 2.5)


func _draw_sergeant_icon(cx: float, cy: float, s: float) -> void:
	# Single chevron (V shape)
	var w: float = s * 0.1
	var h: float = s * 0.07
	draw_line(Vector2(cx - w, cy - h), Vector2(cx, cy + h), Color.WHITE, 2.0)
	draw_line(Vector2(cx, cy + h), Vector2(cx + w, cy - h), Color.WHITE, 2.0)


func _draw_lieutenant_icon(cx: float, cy: float, s: float) -> void:
	# Double chevron
	var w: float = s * 0.1
	var h: float = s * 0.06
	var gap: float = s * 0.06
	draw_line(Vector2(cx - w, cy - gap - h), Vector2(cx, cy - gap + h), Color.WHITE, 2.0)
	draw_line(Vector2(cx, cy - gap + h), Vector2(cx + w, cy - gap - h), Color.WHITE, 2.0)
	draw_line(Vector2(cx - w, cy + gap - h), Vector2(cx, cy + gap + h), Color.WHITE, 2.0)
	draw_line(Vector2(cx, cy + gap + h), Vector2(cx + w, cy + gap - h), Color.WHITE, 2.0)


func _draw_captain_icon(cx: float, cy: float, s: float) -> void:
	# Three horizontal bars
	var w: float = s * 0.12
	var gap: float = s * 0.06
	var bar_h: float = s * 0.03
	for i: int in range(3):
		var y: float = cy + (i - 1) * gap
		draw_rect(Rect2(cx - w, y - bar_h / 2.0, w * 2, bar_h), Color.WHITE)


func _draw_major_icon(cx: float, cy: float, s: float) -> void:
	# Single diamond
	var d: float = s * 0.16
	var points: PackedVector2Array = PackedVector2Array([
		Vector2(cx, cy - d),
		Vector2(cx + d, cy),
		Vector2(cx, cy + d),
		Vector2(cx - d, cy),
	])
	draw_colored_polygon(points, Color(1.0, 1.0, 1.0, 0.8))


func _draw_colonel_icon(cx: float, cy: float, s: float) -> void:
	# Two separated diamonds
	var d: float = s * 0.11
	var offset: float = s * 0.13
	for ox: float in [-offset, offset]:
		var points: PackedVector2Array = PackedVector2Array([
			Vector2(cx + ox, cy - d),
			Vector2(cx + ox + d, cy),
			Vector2(cx + ox, cy + d),
			Vector2(cx + ox - d, cy),
		])
		draw_colored_polygon(points, Color(1.0, 1.0, 1.0, 0.8))


func _draw_general_icon(cx: float, cy: float, s: float) -> void:
	# Two stars side by side
	var offset: float = s * 0.11
	for ox: float in [-offset, offset]:
		_draw_small_star(cx + ox, cy, s * 0.09)


func _draw_marshal_icon(cx: float, cy: float, s: float) -> void:
	# Large 5-pointed star
	_draw_small_star(cx, cy, s * 0.16)


func _draw_small_star(cx: float, cy: float, outer_r: float) -> void:
	var inner_r: float = outer_r * 0.4
	var points: PackedVector2Array = PackedVector2Array()
	for i: int in range(10):
		var angle: float = (PI / 2.0) + (i * PI / 5.0)
		var r: float = outer_r if i % 2 == 0 else inner_r
		points.append(Vector2(cx + cos(angle) * r, cy - sin(angle) * r))
	draw_colored_polygon(points, Color(1.0, 0.85, 0.2))


# --- Rounded rect helpers ---


func _draw_rounded_rect(rect: Rect2, color: Color, radius: float) -> void:
	# Approximate rounded rect with a filled rect + corner circles
	draw_rect(Rect2(rect.position + Vector2(radius, 0), rect.size - Vector2(radius * 2, 0)), color)
	draw_rect(Rect2(rect.position + Vector2(0, radius), rect.size - Vector2(0, radius * 2)), color)
	draw_circle(rect.position + Vector2(radius, radius), radius, color)
	draw_circle(rect.position + Vector2(rect.size.x - radius, radius), radius, color)
	draw_circle(rect.position + Vector2(radius, rect.size.y - radius), radius, color)
	draw_circle(rect.position + Vector2(rect.size.x - radius, rect.size.y - radius), radius, color)


func _draw_rounded_rect_outline(rect: Rect2, color: Color, radius: float, width: float) -> void:
	# Top and bottom edges
	draw_line(rect.position + Vector2(radius, 0), rect.position + Vector2(rect.size.x - radius, 0), color, width)
	draw_line(rect.position + Vector2(radius, rect.size.y), rect.position + Vector2(rect.size.x - radius, rect.size.y), color, width)
	# Left and right edges
	draw_line(rect.position + Vector2(0, radius), rect.position + Vector2(0, rect.size.y - radius), color, width)
	draw_line(rect.position + Vector2(rect.size.x, radius), rect.position + Vector2(rect.size.x, rect.size.y - radius), color, width)
	# Corner arcs (approximated with short line segments)
	_draw_corner_arc(rect.position + Vector2(radius, radius), radius, PI, PI * 1.5, color, width)
	_draw_corner_arc(rect.position + Vector2(rect.size.x - radius, radius), radius, PI * 1.5, PI * 2.0, color, width)
	_draw_corner_arc(rect.position + Vector2(radius, rect.size.y - radius), radius, PI * 0.5, PI, color, width)
	_draw_corner_arc(rect.position + Vector2(rect.size.x - radius, rect.size.y - radius), radius, 0, PI * 0.5, color, width)


func _draw_corner_arc(center: Vector2, radius: float, start_angle: float, end_angle: float, color: Color, width: float) -> void:
	var segments: int = 4
	var prev: Vector2 = center + Vector2(cos(start_angle), sin(start_angle)) * radius
	for i: int in range(1, segments + 1):
		var angle: float = start_angle + (end_angle - start_angle) * float(i) / float(segments)
		var point: Vector2 = center + Vector2(cos(angle), sin(angle)) * radius
		draw_line(prev, point, color, width)
		prev = point


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
