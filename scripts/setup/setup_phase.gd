extends Control

signal setup_complete(team: PieceData.Team)
signal quit_pressed

@onready var board: Control = %Board
@onready var piece_tray: VBoxContainer = %PieceTray
@onready var ready_button: Button = %ReadyButton
@onready var randomize_button: Button = %RandomizeButton
@onready var reset_button: Button = %ResetButton
@onready var placement_buttons: VBoxContainer = %PlacementButtons
@onready var setup_quit_button: Button = %SetupQuitButton
@onready var team_label: Label = %SetupTeamLabel

var current_team: PieceData.Team = PieceData.Team.RED
var selected_rank: int = -1
var placed_counts: Dictionary = {}
var _test_mode: bool = false


func _ready() -> void:
	ready_button.pressed.connect(_on_ready_pressed)
	randomize_button.pressed.connect(_on_randomize_pressed)
	reset_button.pressed.connect(_on_reset_pressed)
	setup_quit_button.pressed.connect(func() -> void: quit_pressed.emit())
	board.square_clicked.connect(_on_square_clicked)


func start_setup(team: PieceData.Team, test_mode: bool = false) -> void:
	current_team = team
	selected_rank = -1
	_test_mode = test_mode
	placed_counts.clear()
	for rank: int in PieceData.RANK_INFO:
		placed_counts[rank] = 0

	# Count any pieces already placed for this team
	for piece_id: int in GameManager.board_state.pieces:
		var piece: Dictionary = GameManager.board_state.pieces[piece_id]
		if piece["team"] == current_team:
			placed_counts[piece["rank"]] += 1

	var team_name: String = PieceData.get_team_name(team)
	if _test_mode:
		team_label.text = "AI Test — %s Setup" % team_name
		# All rows valid in test mode
		board.setup_valid_rows = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
	else:
		team_label.text = "Player %s — Place Your Pieces" % team_name
		board.setup_valid_rows = GameManager.board_state.get_setup_rows(team)

	ready_button.disabled = true
	_build_tray()
	_build_placement_buttons()
	board.set_game_layout()
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


func _build_placement_buttons() -> void:
	for child: Node in placement_buttons.get_children():
		child.queue_free()

	placement_buttons.visible = true
	for i: int in range(Placement.STRATEGY_NAMES.size()):
		var btn: Button = Button.new()
		btn.text = Placement.STRATEGY_NAMES[i]
		btn.pressed.connect(_on_placement_strategy_pressed.bind(i))
		placement_buttons.add_child(btn)


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
	if _test_mode:
		var red_in_blue_territory: bool = _has_enemy_in_territory()
		if current_team == PieceData.Team.BLUE:
			randomize_button.disabled = red_in_blue_territory
			for btn: Node in placement_buttons.get_children():
				(btn as Button).disabled = red_in_blue_territory
		else:
			randomize_button.disabled = false
	else:
		randomize_button.disabled = false


func _has_enemy_in_territory() -> bool:
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

	if board.setup_valid_rows.size() > 0 and pos.y not in board.setup_valid_rows:
		return

	var existing: int = GameManager.board_state.get_piece_at(pos)

	if existing != -1:
		var piece: Dictionary = GameManager.board_state.pieces[existing]
		if piece["team"] == current_team:
			placed_counts[piece["rank"]] -= 1
			GameManager.board_state.remove_piece(existing)
			board.refresh()
			_refresh_tray()
		return

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
	board.setup_valid_rows.clear()
	board.refresh()
	setup_complete.emit(current_team)


func _on_randomize_pressed() -> void:
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


func _on_reset_pressed() -> void:
	var to_remove: Array[int] = []
	for piece_id: int in GameManager.board_state.pieces:
		if GameManager.board_state.pieces[piece_id]["team"] == current_team:
			to_remove.append(piece_id)
	for piece_id: int in to_remove:
		GameManager.board_state.remove_piece(piece_id)

	placed_counts.clear()
	for rank: int in PieceData.RANK_INFO:
		placed_counts[rank] = 0

	selected_rank = -1
	board.refresh()
	_refresh_tray()


func _on_placement_strategy_pressed(strategy_index: int) -> void:
	# Remove existing pieces for this team
	var to_remove: Array[int] = []
	for piece_id: int in GameManager.board_state.pieces:
		if GameManager.board_state.pieces[piece_id]["team"] == current_team:
			to_remove.append(piece_id)
	for piece_id: int in to_remove:
		GameManager.board_state.remove_piece(piece_id)

	# Apply the selected strategy
	Placement.place(strategy_index as Placement.Strategy, GameManager.board_state, current_team)

	# Recount placed pieces
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
