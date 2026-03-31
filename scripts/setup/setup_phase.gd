extends Control

signal setup_complete(team: PieceData.Team)
signal ai_place_requested(team: PieceData.Team)

@onready var board: Control = %Board
@onready var piece_tray: VBoxContainer = %PieceTray
@onready var ready_button: Button = %ReadyButton
@onready var randomize_button: Button = %RandomizeButton
@onready var ai_place_button: Button = %AIPlaceButton
@onready var team_label: Label = %SetupTeamLabel

var current_team: PieceData.Team = PieceData.Team.RED
var selected_rank: int = -1
var placed_counts: Dictionary = {}
var _test_mode: bool = false


func _ready() -> void:
	ready_button.pressed.connect(_on_ready_pressed)
	randomize_button.pressed.connect(_on_randomize_pressed)
	ai_place_button.pressed.connect(_on_ai_place_pressed)
	board.square_clicked.connect(_on_square_clicked)


func start_setup(team: PieceData.Team, test_mode: bool = false) -> void:
	current_team = team
	selected_rank = -1
	_test_mode = test_mode
	placed_counts.clear()
	for rank: int in PieceData.RANK_INFO:
		placed_counts[rank] = 0

	# Count any pieces already placed for this team (e.g. from prior placement)
	for piece_id: int in GameManager.board_state.pieces:
		var piece: Dictionary = GameManager.board_state.pieces[piece_id]
		if piece["team"] == current_team:
			placed_counts[piece["rank"]] += 1

	var team_name: String = PieceData.get_team_name(team)
	if _test_mode:
		team_label.text = "AI Test — %s Setup" % team_name
	else:
		team_label.text = "Player %s — Place Your Pieces" % team_name

	ready_button.disabled = true
	_update_special_buttons()
	_build_tray()
	visible = true
	board.refresh()


func _build_tray() -> void:
	for child: Node in piece_tray.get_children():
		child.queue_free()

	for rank: int in PieceData.RANK_INFO:
		var btn: Button = Button.new()
		btn.custom_minimum_size = Vector2(180, 36)
		_update_tray_button(btn, rank)
		btn.pressed.connect(_on_rank_selected.bind(rank))
		piece_tray.add_child(btn)


func _update_tray_button(btn: Button, rank: int) -> void:
	var info: Dictionary = PieceData.RANK_INFO[rank]
	var remaining: int = info["count"] - placed_counts.get(rank, 0)
	btn.text = "%s (%s) x%d" % [info["name"], info["display"], remaining]
	btn.disabled = remaining <= 0
	if rank == selected_rank and remaining > 0:
		btn.add_theme_color_override("font_color", Color.YELLOW)
	else:
		btn.remove_theme_color_override("font_color")


func _refresh_tray() -> void:
	var buttons: Array[Node] = piece_tray.get_children()
	var ranks: Array = PieceData.RANK_INFO.keys()
	for i: int in range(min(buttons.size(), ranks.size())):
		_update_tray_button(buttons[i] as Button, ranks[i])

	if _test_mode:
		# Ready if flag + at least 1 movable piece placed
		var has_flag: bool = placed_counts.get(PieceData.Rank.FLAG, 0) > 0
		var has_mover: bool = false
		for rank: int in placed_counts:
			if placed_counts[rank] > 0 and PieceData.can_move(rank):
				has_mover = true
				break
		ready_button.disabled = not (has_flag and has_mover)
	else:
		var total_placed: int = 0
		for rank: int in placed_counts:
			total_placed += placed_counts[rank]
		ready_button.disabled = total_placed < PieceData.get_total_pieces()

	_update_special_buttons()


func _update_special_buttons() -> void:
	# AI place button only in test mode for blue
	ai_place_button.visible = _test_mode and current_team == PieceData.Team.BLUE

	if _test_mode:
		var red_in_blue_territory: bool = _has_enemy_in_territory()
		if current_team == PieceData.Team.BLUE:
			randomize_button.disabled = red_in_blue_territory
			ai_place_button.disabled = red_in_blue_territory
		else:
			randomize_button.disabled = false
	else:
		ai_place_button.visible = false
		randomize_button.disabled = false


func _has_enemy_in_territory() -> bool:
	# Check if red pieces are in blue's starting rows
	var blue_rows: Array[int] = GameManager.board_state.get_setup_rows(PieceData.Team.BLUE)
	for piece_id: int in GameManager.board_state.pieces:
		var piece: Dictionary = GameManager.board_state.pieces[piece_id]
		if piece["team"] == PieceData.Team.RED and piece["pos"].y in blue_rows:
			return true
	return false


func _on_rank_selected(rank: int) -> void:
	if selected_rank == rank:
		selected_rank = -1
	else:
		selected_rank = rank
	_refresh_tray()


func _on_square_clicked(pos: Vector2i) -> void:
	if not visible:
		return

	if not GameManager.board_state.is_valid_cell(pos):
		return

	# In normal mode, restrict to setup rows
	if not _test_mode:
		var valid_rows: Array[int] = GameManager.board_state.get_setup_rows(current_team)
		if pos.y not in valid_rows:
			return

	var existing: int = GameManager.board_state.get_piece_at(pos)

	# If clicking an occupied cell, remove the piece (only own team)
	if existing != -1:
		var piece: Dictionary = GameManager.board_state.pieces[existing]
		if piece["team"] == current_team:
			placed_counts[piece["rank"]] -= 1
			GameManager.board_state.remove_piece(existing)
			board.refresh()
			_refresh_tray()
		return

	# Place selected rank
	if selected_rank == -1:
		return

	if placed_counts[selected_rank] >= PieceData.RANK_INFO[selected_rank]["count"]:
		return

	GameManager.board_state.add_piece(selected_rank, current_team, pos)
	placed_counts[selected_rank] += 1

	if placed_counts[selected_rank] >= PieceData.RANK_INFO[selected_rank]["count"]:
		selected_rank = -1

	board.refresh()
	_refresh_tray()


func _on_ready_pressed() -> void:
	visible = false
	setup_complete.emit(current_team)


func _on_randomize_pressed() -> void:
	# Collect empty cells in valid rows
	var valid_rows: Array[int] = GameManager.board_state.get_setup_rows(current_team)
	var empty_cells: Array[Vector2i] = []
	for col: int in range(BoardState.BOARD_SIZE):
		for row: int in valid_rows:
			var pos: Vector2i = Vector2i(col, row)
			if GameManager.board_state.is_valid_cell(pos) and GameManager.board_state.get_piece_at(pos) == -1:
				empty_cells.append(pos)

	empty_cells.shuffle()

	var to_place: Array[int] = []
	for rank: int in PieceData.RANK_INFO:
		var remaining: int = PieceData.RANK_INFO[rank]["count"] - placed_counts.get(rank, 0)
		for i: int in range(remaining):
			to_place.append(rank)

	for i: int in range(min(to_place.size(), empty_cells.size())):
		var rank: int = to_place[i]
		GameManager.board_state.add_piece(rank, current_team, empty_cells[i])
		placed_counts[rank] += 1

	selected_rank = -1
	board.refresh()
	_refresh_tray()


func _on_ai_place_pressed() -> void:
	ai_place_requested.emit(current_team)
	# Recount placed pieces after AI placement
	placed_counts.clear()
	for rank: int in PieceData.RANK_INFO:
		placed_counts[rank] = 0
	for piece_id: int in GameManager.board_state.pieces:
		var piece: Dictionary = GameManager.board_state.pieces[piece_id]
		if piece["team"] == current_team:
			placed_counts[piece["rank"]] += 1
	selected_rank = -1
	board.refresh()
	_refresh_tray()
