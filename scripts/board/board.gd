extends Control

signal square_clicked(pos: Vector2i)

const BOARD_SIZE: int = 10
# Board colors are read from VisualConfig autoload

var cell_size: float = 60.0
var board_offset: Vector2 = Vector2.ZERO
var selected_piece_id: int = -1
var valid_moves: Array[Vector2i] = []
var last_enemy_move: Vector2i = Vector2i(-1, -1)
var setup_valid_rows: Array[int] = []  # Highlighted during piece placement
var flag_capture_pos: Vector2i = Vector2i(-1, -1)  # Position where flag was captured

# Animation state
var _anim_piece_id: int = -1
var _anim_from: Vector2i = Vector2i.ZERO
var _anim_to: Vector2i = Vector2i.ZERO
var _anim_progress: float = 1.0
const ANIM_DURATION: float = 0.15

# Combat animation
enum CombatAnimState { NONE, FLASH_LOSER, FADE_LOSER, FLASH_LOSER2, FADE_LOSER2 }
var _combat_anim_state: CombatAnimState = CombatAnimState.NONE
var _combat_anim_pos: Vector2i = Vector2i(-1, -1)
var _combat_anim_timer: float = 0.0
var _combat_loser1_id: int = -1
var _combat_loser2_id: int = -1  # -1 if only one dies
var _combat_fade_alpha: float = 1.0  # for fading out pieces
const COMBAT_FLASH_TIME: float = 0.15
const COMBAT_FADE_TIME: float = 0.2

# Cell flash overlay
var _combat_flash_pos: Vector2i = Vector2i(-1, -1)
var _combat_flash_alpha: float = 0.0

# Last move pulse
var _last_move_pulse_time: float = 0.0

signal animation_finished
signal combat_animation_finished
# Fires when slide + any combat animation is complete and the move can be executed
signal move_ready(from: Vector2i, to: Vector2i)

var _move_from: Vector2i = Vector2i.ZERO
var _move_to: Vector2i = Vector2i.ZERO


func _ready() -> void:
	_calculate_layout()
	animation_finished.connect(_on_slide_finished)
	combat_animation_finished.connect(_on_combat_finished)


func _process(delta: float) -> void:
	var needs_redraw: bool = false

	if _anim_progress < 1.0:
		_anim_progress += delta / ANIM_DURATION
		if _anim_progress >= 1.0:
			_anim_progress = 1.0
			animation_finished.emit()
		needs_redraw = true

	if _combat_flash_alpha > 0.0:
		_combat_flash_alpha -= delta / 0.3
		if _combat_flash_alpha < 0.0:
			_combat_flash_alpha = 0.0
		needs_redraw = true

	if _combat_anim_state != CombatAnimState.NONE:
		_combat_anim_timer += delta
		needs_redraw = true
		match _combat_anim_state:
			CombatAnimState.FLASH_LOSER:
				if _combat_anim_timer >= COMBAT_FLASH_TIME:
					_combat_anim_state = CombatAnimState.FADE_LOSER
					_combat_anim_timer = 0.0
					_combat_fade_alpha = 1.0
			CombatAnimState.FADE_LOSER:
				_combat_fade_alpha = 1.0 - (_combat_anim_timer / COMBAT_FADE_TIME)
				if _combat_anim_timer >= COMBAT_FADE_TIME:
					_combat_fade_alpha = 0.0
					if _combat_loser2_id != -1:
						_combat_anim_state = CombatAnimState.FLASH_LOSER2
						_combat_anim_timer = 0.0
					else:
						_combat_anim_state = CombatAnimState.NONE
						combat_animation_finished.emit()
			CombatAnimState.FLASH_LOSER2:
				if _combat_anim_timer >= COMBAT_FLASH_TIME:
					_combat_anim_state = CombatAnimState.FADE_LOSER2
					_combat_anim_timer = 0.0
					_combat_fade_alpha = 1.0
			CombatAnimState.FADE_LOSER2:
				_combat_fade_alpha = 1.0 - (_combat_anim_timer / COMBAT_FADE_TIME)
				if _combat_anim_timer >= COMBAT_FADE_TIME:
					_combat_fade_alpha = 0.0
					_combat_anim_state = CombatAnimState.NONE
					combat_animation_finished.emit()

	if last_enemy_move != Vector2i(-1, -1):
		_last_move_pulse_time += delta
		needs_redraw = true

	if needs_redraw:
		queue_redraw()


func flash_combat(pos: Vector2i) -> void:
	_combat_flash_pos = pos
	_combat_flash_alpha = 1.0
	queue_redraw()


func start_combat_animation(pos: Vector2i, loser1_id: int, loser2_id: int) -> void:
	_combat_anim_pos = pos
	_combat_loser1_id = loser1_id
	_combat_loser2_id = loser2_id
	_combat_anim_state = CombatAnimState.FLASH_LOSER
	_combat_anim_timer = 0.0
	_combat_fade_alpha = 1.0
	_combat_flash_pos = pos
	_combat_flash_alpha = 1.0
	queue_redraw()


func animate_move(piece_id: int, from: Vector2i, to: Vector2i) -> void:
	_anim_piece_id = piece_id
	_anim_from = from
	_anim_to = to
	_anim_progress = 0.0
	set_process(true)
	queue_redraw()


# Animate a move with automatic combat handling. Emits move_ready when done.
func animate_move_with_combat(piece_id: int, from: Vector2i, to: Vector2i) -> void:
	_move_from = from
	_move_to = to
	animate_move(piece_id, from, to)


func _on_slide_finished() -> void:
	# Called when slide animation ends — check for combat
	if _move_from == Vector2i.ZERO and _move_to == Vector2i.ZERO:
		return
	var target_id: int = GameManager.board_state.get_piece_at(_move_to)
	if target_id != -1:
		var attacker_id: int = GameManager.board_state.get_piece_at(_move_from)
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
		start_combat_animation(_move_to, loser1, loser2)
	else:
		_emit_move_ready()


func _on_combat_finished() -> void:
	_emit_move_ready()


func _emit_move_ready() -> void:
	var from: Vector2i = _move_from
	var to: Vector2i = _move_to
	_move_from = Vector2i.ZERO
	_move_to = Vector2i.ZERO
	move_ready.emit(from, to)


func _calculate_layout() -> void:
	var available: Vector2 = size
	# Reserve space for frame border
	var frame_margin: float = min(available.x, available.y) * 0.015 + 4
	var usable: Vector2 = available - Vector2(frame_margin * 2, frame_margin * 2)
	cell_size = min(usable.x, usable.y) / BOARD_SIZE
	board_offset = Vector2(
		(available.x - cell_size * BOARD_SIZE) / 2.0,
		(available.y - cell_size * BOARD_SIZE) / 2.0,
	)


func _draw() -> void:
	_calculate_layout()

	# Draw wooden frame border
	var frame_width: float = cell_size * 0.15
	var inner_rect: Rect2 = Rect2(
		board_offset,
		Vector2(cell_size * BOARD_SIZE, cell_size * BOARD_SIZE),
	)
	# Outer dark edge
	draw_rect(inner_rect.grow(frame_width + 2), VisualConfig.FRAME_OUTER)
	draw_rect(inner_rect.grow(frame_width), VisualConfig.FRAME_MAIN)
	draw_rect(inner_rect.grow(frame_width * 0.6), VisualConfig.FRAME_INNER)
	draw_rect(inner_rect.grow(2), VisualConfig.FRAME_BEVEL)
	# Subtle highlight on top and left of frame
	var outer: Rect2 = inner_rect.grow(frame_width)
	draw_line(Vector2(outer.position.x, outer.position.y), Vector2(outer.position.x + outer.size.x, outer.position.y), Color(1.0, 1.0, 1.0, 0.08), 2.0)
	draw_line(Vector2(outer.position.x, outer.position.y), Vector2(outer.position.x, outer.position.y + outer.size.y), Color(1.0, 1.0, 1.0, 0.06), 2.0)
	# Shadow on bottom and right of frame
	draw_line(Vector2(outer.position.x, outer.position.y + outer.size.y), Vector2(outer.position.x + outer.size.x, outer.position.y + outer.size.y), Color(0.0, 0.0, 0.0, 0.15), 2.0)
	draw_line(Vector2(outer.position.x + outer.size.x, outer.position.y), Vector2(outer.position.x + outer.size.x, outer.position.y + outer.size.y), Color(0.0, 0.0, 0.0, 0.12), 2.0)

	# Draw board squares
	for col: int in range(BOARD_SIZE):
		for row: int in range(BOARD_SIZE):
			var pos: Vector2i = Vector2i(col, row)
			var rect: Rect2 = _get_cell_rect(pos)

			# Cell color
			if GameManager.board_state.is_lake(pos):
				# Lake gradient: lighter at top, darker at bottom
				var t: float = float(row - 4) / 1.0  # 0.0 for row 4, 1.0 for row 5
				var lake_color: Color = VisualConfig.LAKE_LIGHT.lerp(VisualConfig.LAKE_DARK, clamp(t, 0.0, 1.0))
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
					base = VisualConfig.BOARD_LIGHT
				else:
					base = VisualConfig.BOARD_DARK
				draw_rect(rect, base)

			# Dim invalid setup rows (not in valid rows, not lakes)
			if setup_valid_rows.size() > 0 and row not in setup_valid_rows and not GameManager.board_state.is_lake(pos):
				draw_rect(rect, VisualConfig.INVALID_ROW_DIM)

			# Highlight selected piece
			if selected_piece_id != -1:
				var sel_piece: Dictionary = GameManager.board_state.pieces.get(selected_piece_id, {})
				if sel_piece.get("pos") == pos:
					draw_rect(rect, VisualConfig.SELECTED_HIGHLIGHT)

			# Highlight valid moves
			if pos in valid_moves:
				draw_rect(rect, VisualConfig.MOVE_HIGHLIGHT)

			# Pulsing last enemy move indicator
			if pos == last_enemy_move:
				var pulse: float = (sin(_last_move_pulse_time * 3.0) + 1.0) / 2.0
				var glow_alpha: float = 0.15 + pulse * 0.2
				var glow_color: Color = VisualConfig.get_last_move_color(GameManager.last_move_team)
				glow_color.a = glow_alpha
				draw_rect(rect, glow_color)

			# Combat flash
			if pos == _combat_flash_pos and _combat_flash_alpha > 0.0:
				draw_rect(rect, Color(1.0, 1.0, 1.0, _combat_flash_alpha * 0.7))

			# Subtle grid lines
			draw_rect(rect, VisualConfig.GRID_LINE, false, 1.0)

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
		var rect: Rect2
		# Animate the moving piece
		if piece_id == _anim_piece_id and _anim_progress < 1.0:
			var from_rect: Rect2 = _get_cell_rect(_anim_from)
			var to_rect: Rect2 = _get_cell_rect(_anim_to)
			var t: float = _anim_progress * _anim_progress * (3.0 - 2.0 * _anim_progress)  # smoothstep
			rect = Rect2(
				from_rect.position.lerp(to_rect.position, t),
				from_rect.size,
			)
		elif piece_id == _anim_piece_id and _combat_anim_state != CombatAnimState.NONE:
			# During combat animation, keep attacker drawn at combat position
			rect = _get_cell_rect(_anim_to)
		else:
			rect = _get_cell_rect(pos)
		var piece_rect: Rect2 = rect.grow(-3.0)
		var radius: float = cell_size * 0.12

		var is_own: bool = piece["team"] == viewing_team or see_all
		var is_revealed: bool = piece["revealed"]
		var rank: PieceData.Rank = piece["rank"]

		# Piece background
		var bg_color: Color
		var border_color: Color
		if piece["team"] == PieceData.Team.RED and (is_own or is_revealed):
			bg_color = VisualConfig.RED_PIECE
			border_color = VisualConfig.RED_PIECE_BORDER
		elif piece["team"] == PieceData.Team.BLUE and (is_own or is_revealed):
			bg_color = VisualConfig.BLUE_PIECE
			border_color = VisualConfig.BLUE_PIECE_BORDER
		else:
			bg_color = VisualConfig.HIDDEN_PIECE
			border_color = VisualConfig.HIDDEN_PIECE_BORDER

		# Combat animation: flash and fade losing pieces
		var piece_alpha: float = 1.0
		if _combat_anim_state != CombatAnimState.NONE:
			var is_loser1: bool = piece_id == _combat_loser1_id
			var is_loser2: bool = piece_id == _combat_loser2_id
			if is_loser1 and (_combat_anim_state == CombatAnimState.FLASH_LOSER or _combat_anim_state == CombatAnimState.FADE_LOSER):
				if _combat_anim_state == CombatAnimState.FLASH_LOSER:
					bg_color = bg_color.lerp(Color.WHITE, 0.8)
				else:
					piece_alpha = _combat_fade_alpha
			elif is_loser2 and (_combat_anim_state == CombatAnimState.FLASH_LOSER2 or _combat_anim_state == CombatAnimState.FADE_LOSER2):
				if _combat_anim_state == CombatAnimState.FLASH_LOSER2:
					bg_color = bg_color.lerp(Color.WHITE, 0.8)
				else:
					piece_alpha = _combat_fade_alpha
			# Already faded loser1 — hide it during loser2 animation
			if is_loser1 and (_combat_anim_state == CombatAnimState.FLASH_LOSER2 or _combat_anim_state == CombatAnimState.FADE_LOSER2):
				piece_alpha = 0.0

		if piece_alpha <= 0.01:
			continue

		bg_color.a = piece_alpha
		border_color.a = piece_alpha

		# Rounded rectangle background
		_draw_rounded_rect(piece_rect, bg_color, radius)
		# Border
		_draw_rounded_rect_outline(piece_rect, border_color, radius, 2.0)

		# Revealed indicator: yellow eye in upper-left corner
		if is_own and is_revealed:
			var eye_cx: float = piece_rect.position.x + cell_size * 0.17
			var eye_cy: float = piece_rect.position.y + cell_size * 0.15
			var eye_s: float = cell_size * 0.75
			_draw_revealed_eye(eye_cx, eye_cy, eye_s)

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

		# Draw small captured flag icon in bottom-right corner
		if flag_capture_pos != Vector2i(-1, -1) and pos == flag_capture_pos:
			var flag_cx: float = piece_rect.position.x + piece_rect.size.x - cell_size * 0.18
			var flag_cy: float = piece_rect.position.y + piece_rect.size.y - cell_size * 0.18
			_draw_flag_icon(flag_cx, flag_cy, cell_size * 0.5)


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


func _draw_revealed_eye(cx: float, cy: float, s: float) -> void:
	var w: float = s * 0.12
	var h: float = s * 0.06
	var yellow: Color = Color(1.0, 0.85, 0.0)
	# Eye outline arcs
	var segments: int = 6
	var top_points: PackedVector2Array = PackedVector2Array()
	var bot_points: PackedVector2Array = PackedVector2Array()
	for i: int in range(segments + 1):
		var t: float = float(i) / float(segments)
		var x: float = cx - w + t * w * 2
		top_points.append(Vector2(x, cy - sin(t * PI) * h))
		bot_points.append(Vector2(x, cy + sin(t * PI) * h))
	# Outline
	for i: int in range(top_points.size() - 1):
		draw_line(top_points[i], top_points[i + 1], yellow, 1.5)
		draw_line(bot_points[i], bot_points[i + 1], yellow, 1.5)
	# Pupil
	draw_circle(Vector2(cx, cy), s * 0.03, yellow)


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


func set_game_layout() -> void:
	offset_left = VisualConfig.SIDEBAR_WIDTH
	offset_right = -VisualConfig.SIDEBAR_WIDTH
	offset_top = VisualConfig.TURN_BAR_HEIGHT
	offset_bottom = 0


func reset_layout() -> void:
	offset_left = 0
	offset_right = 0
	offset_top = 0
	offset_bottom = 0


func refresh() -> void:
	# Show last enemy move highlight if the last move was from the other team
	var viewing: PieceData.Team = _get_viewing_team()
	var new_last_move: Vector2i
	if GameManager.last_move_team != viewing and GameManager.last_move_to != Vector2i(-1, -1):
		new_last_move = GameManager.last_move_to
	else:
		new_last_move = Vector2i(-1, -1)
	if new_last_move != last_enemy_move:
		last_enemy_move = new_last_move
		_last_move_pulse_time = 0.0
	queue_redraw()


# Shared click-to-select-and-move logic.
# bs: the board state to read from
# my_team: the player's team (for filtering selectable pieces)
# move_fn: called with (from, to) when a move is selected
func handle_click(pos: Vector2i, bs: BoardState, my_team: PieceData.Team, move_fn: Callable) -> void:
	var clicked_id: int = bs.get_piece_at(pos)

	if selected_piece_id != -1:
		var selected: Dictionary = bs.pieces.get(selected_piece_id, {})

		if clicked_id == selected_piece_id:
			clear_selection()
			return

		if pos in valid_moves:
			var from: Vector2i = selected["pos"]
			clear_selection()
			move_fn.call(from, pos)
			return

		if clicked_id != -1:
			var clicked: Dictionary = bs.pieces[clicked_id]
			if clicked["team"] == my_team and PieceData.can_move(clicked["rank"]):
				select_piece(clicked_id)
				return

		clear_selection()
		return

	if clicked_id != -1:
		var piece: Dictionary = bs.pieces[clicked_id]
		if piece["team"] == my_team and PieceData.can_move(piece["rank"]):
			select_piece(clicked_id)
