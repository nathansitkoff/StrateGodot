class_name Placement
extends RefCounted

enum Strategy {
	CLUSTERED_DEFENSE,
	FRONT_AGGRESSION,
}

const STRATEGY_NAMES: Array[String] = ["Clustered Defense", "Front Aggression"]


static func place(strategy: Strategy, board_state: BoardState, ai_team: PieceData.Team) -> void:
	match strategy:
		Strategy.CLUSTERED_DEFENSE:
			_clustered_defense(board_state, ai_team)
		Strategy.FRONT_AGGRESSION:
			_front_aggression(board_state, ai_team)


static func _clustered_defense(board_state: BoardState, ai_team: PieceData.Team) -> void:
	var valid_rows: Array[int] = board_state.get_setup_rows(ai_team)
	var back_row: int = valid_rows[0]
	var second_row: int = valid_rows[1]
	var front_rows: Array[int] = [valid_rows[2], valid_rows[3]]

	var back_cells: Array[Vector2i] = []
	var second_cells: Array[Vector2i] = []
	var front_cells: Array[Vector2i] = []
	for col: int in range(BoardState.BOARD_SIZE):
		var pos_back: Vector2i = Vector2i(col, back_row)
		var pos_second: Vector2i = Vector2i(col, second_row)
		if board_state.is_valid_cell(pos_back):
			back_cells.append(pos_back)
		if board_state.is_valid_cell(pos_second):
			second_cells.append(pos_second)
		for row: int in front_rows:
			var pos_front: Vector2i = Vector2i(col, row)
			if board_state.is_valid_cell(pos_front):
				front_cells.append(pos_front)

	back_cells.shuffle()
	second_cells.shuffle()
	front_cells.shuffle()

	# Place flag in back row
	var flag_pos: Vector2i = back_cells.pop_back()
	board_state.add_piece(PieceData.Rank.FLAG, ai_team, flag_pos)

	# Place bombs around the flag
	var bomb_count: int = 0
	var bomb_positions: Array[Vector2i] = []
	for pos: Vector2i in back_cells.duplicate():
		if bomb_count >= 4 and abs(pos.x - flag_pos.x) > 1:
			continue
		if abs(pos.x - flag_pos.x) <= 1 and bomb_count < 6:
			bomb_positions.append(pos)
			back_cells.erase(pos)
			bomb_count += 1
	for pos: Vector2i in second_cells.duplicate():
		if bomb_count >= 6:
			break
		if abs(pos.x - flag_pos.x) <= 1:
			bomb_positions.append(pos)
			second_cells.erase(pos)
			bomb_count += 1
	var overflow_cells: Array[Vector2i] = back_cells.duplicate()
	overflow_cells.append_array(second_cells.duplicate())
	overflow_cells.shuffle()
	for pos: Vector2i in overflow_cells:
		if bomb_count >= 6:
			break
		if pos not in bomb_positions:
			bomb_positions.append(pos)
			if pos in back_cells:
				back_cells.erase(pos)
			elif pos in second_cells:
				second_cells.erase(pos)
			bomb_count += 1

	for pos: Vector2i in bomb_positions:
		board_state.add_piece(PieceData.Rank.BOMB, ai_team, pos)

	var remaining_cells: Array[Vector2i] = []
	remaining_cells.append_array(back_cells)
	remaining_cells.append_array(second_cells)
	remaining_cells.append_array(front_cells)
	remaining_cells.shuffle()

	# Marshal and General in back two rows
	var high_ranks: Array[int] = [PieceData.Rank.MARSHAL, PieceData.Rank.GENERAL]
	var back_and_second: Array[Vector2i] = []
	var other_cells: Array[Vector2i] = []
	for pos: Vector2i in remaining_cells:
		if pos.y == back_row or pos.y == second_row:
			back_and_second.append(pos)
		else:
			other_cells.append(pos)

	var cell_idx: int = 0
	for rank: int in high_ranks:
		if cell_idx < back_and_second.size():
			board_state.add_piece(rank, ai_team, back_and_second[cell_idx])
			cell_idx += 1

	# Scouts biased toward front rows
	var scout_cells: Array[Vector2i] = []
	scout_cells.append_array(other_cells)
	for i: int in range(cell_idx, back_and_second.size()):
		scout_cells.append(back_and_second[i])
	scout_cells.shuffle()
	var front_first: Array[Vector2i] = []
	var back_rest: Array[Vector2i] = []
	for pos: Vector2i in scout_cells:
		if pos.y in front_rows:
			front_first.append(pos)
		else:
			back_rest.append(pos)
	var ordered_cells: Array[Vector2i] = []
	ordered_cells.append_array(front_first)
	ordered_cells.append_array(back_rest)

	var placed: int = 0
	var scout_count: int = PieceData.get_count(PieceData.Rank.SCOUT)
	var used_positions: Array[Vector2i] = []
	for pos: Vector2i in ordered_cells:
		if placed >= scout_count:
			break
		board_state.add_piece(PieceData.Rank.SCOUT, ai_team, pos)
		used_positions.append(pos)
		placed += 1

	var final_cells: Array[Vector2i] = []
	for pos: Vector2i in ordered_cells:
		if pos not in used_positions:
			final_cells.append(pos)
	final_cells.shuffle()

	var remaining_ranks: Array[int] = [
		PieceData.Rank.SPY,
		PieceData.Rank.MINER, PieceData.Rank.MINER, PieceData.Rank.MINER, PieceData.Rank.MINER, PieceData.Rank.MINER,
		PieceData.Rank.SERGEANT, PieceData.Rank.SERGEANT, PieceData.Rank.SERGEANT, PieceData.Rank.SERGEANT,
		PieceData.Rank.LIEUTENANT, PieceData.Rank.LIEUTENANT, PieceData.Rank.LIEUTENANT, PieceData.Rank.LIEUTENANT,
		PieceData.Rank.CAPTAIN, PieceData.Rank.CAPTAIN, PieceData.Rank.CAPTAIN, PieceData.Rank.CAPTAIN,
		PieceData.Rank.MAJOR, PieceData.Rank.MAJOR, PieceData.Rank.MAJOR,
		PieceData.Rank.COLONEL, PieceData.Rank.COLONEL,
	]

	for i: int in range(min(remaining_ranks.size(), final_cells.size())):
		board_state.add_piece(remaining_ranks[i], ai_team, final_cells[i])


static func _front_aggression(board_state: BoardState, ai_team: PieceData.Team) -> void:
	var valid_rows: Array[int] = board_state.get_setup_rows(ai_team)
	var back_row: int = valid_rows[0]
	var second_row: int = valid_rows[1]
	var third_row: int = valid_rows[2]
	var front_row: int = valid_rows[3]

	var back_cells: Array[Vector2i] = []
	var second_cells: Array[Vector2i] = []
	var third_cells: Array[Vector2i] = []
	var front_cells: Array[Vector2i] = []
	for col: int in range(BoardState.BOARD_SIZE):
		for pos_data: Array in [[back_row, back_cells], [second_row, second_cells], [third_row, third_cells], [front_row, front_cells]]:
			var pos: Vector2i = Vector2i(col, pos_data[0])
			if board_state.is_valid_cell(pos):
				pos_data[1].append(pos)

	back_cells.shuffle()
	second_cells.shuffle()
	third_cells.shuffle()
	front_cells.shuffle()

	# Flag in back row with minimal bomb protection (3 bombs adjacent)
	var flag_pos: Vector2i = back_cells.pop_back()
	board_state.add_piece(PieceData.Rank.FLAG, ai_team, flag_pos)

	var bomb_count: int = 0
	var bomb_positions: Array[Vector2i] = []
	# Place 3 bombs near flag, remaining 3 scattered in back row
	for pos: Vector2i in back_cells.duplicate():
		if bomb_count >= 3:
			break
		if abs(pos.x - flag_pos.x) <= 1:
			bomb_positions.append(pos)
			back_cells.erase(pos)
			bomb_count += 1
	# Remaining bombs scattered in back/second row
	var scatter_cells: Array[Vector2i] = back_cells.duplicate()
	scatter_cells.append_array(second_cells.duplicate())
	scatter_cells.shuffle()
	for pos: Vector2i in scatter_cells:
		if bomb_count >= 6:
			break
		if pos not in bomb_positions:
			bomb_positions.append(pos)
			if pos in back_cells:
				back_cells.erase(pos)
			elif pos in second_cells:
				second_cells.erase(pos)
			bomb_count += 1

	for pos: Vector2i in bomb_positions:
		board_state.add_piece(PieceData.Rank.BOMB, ai_team, pos)

	# High-value pieces in third row for quick engagement
	var high_cells: Array[Vector2i] = third_cells.duplicate()
	high_cells.shuffle()
	var high_idx: int = 0
	for rank: int in [PieceData.Rank.MARSHAL, PieceData.Rank.GENERAL, PieceData.Rank.COLONEL, PieceData.Rank.COLONEL]:
		if high_idx < high_cells.size():
			board_state.add_piece(rank, ai_team, high_cells[high_idx])
			high_idx += 1

	# Remove used third_cells
	var used_third: Array[Vector2i] = []
	for i: int in range(high_idx):
		used_third.append(high_cells[i])
	for pos: Vector2i in used_third:
		third_cells.erase(pos)

	# Scouts on front line
	var scout_placed: int = 0
	var scout_count: int = PieceData.get_count(PieceData.Rank.SCOUT)
	var scout_positions: Array[Vector2i] = []
	for pos: Vector2i in front_cells.duplicate():
		if scout_placed >= scout_count:
			break
		board_state.add_piece(PieceData.Rank.SCOUT, ai_team, pos)
		scout_positions.append(pos)
		scout_placed += 1
	for pos: Vector2i in scout_positions:
		front_cells.erase(pos)
	# Overflow scouts to third row
	for pos: Vector2i in third_cells.duplicate():
		if scout_placed >= scout_count:
			break
		board_state.add_piece(PieceData.Rank.SCOUT, ai_team, pos)
		third_cells.erase(pos)
		scout_placed += 1

	# Miners in front/third rows
	var miner_cells: Array[Vector2i] = []
	miner_cells.append_array(front_cells)
	miner_cells.append_array(third_cells)
	miner_cells.shuffle()
	var miner_placed: int = 0
	var miner_positions: Array[Vector2i] = []
	for pos: Vector2i in miner_cells:
		if miner_placed >= PieceData.get_count(PieceData.Rank.MINER):
			break
		board_state.add_piece(PieceData.Rank.MINER, ai_team, pos)
		miner_positions.append(pos)
		miner_placed += 1
	for pos: Vector2i in miner_positions:
		if pos in front_cells:
			front_cells.erase(pos)
		elif pos in third_cells:
			third_cells.erase(pos)

	# Remaining pieces fill remaining cells
	var all_remaining: Array[Vector2i] = []
	all_remaining.append_array(front_cells)
	all_remaining.append_array(third_cells)
	all_remaining.append_array(second_cells)
	all_remaining.append_array(back_cells)
	all_remaining.shuffle()

	var remaining_ranks: Array[int] = [
		PieceData.Rank.SPY,
		PieceData.Rank.SERGEANT, PieceData.Rank.SERGEANT, PieceData.Rank.SERGEANT, PieceData.Rank.SERGEANT,
		PieceData.Rank.LIEUTENANT, PieceData.Rank.LIEUTENANT, PieceData.Rank.LIEUTENANT, PieceData.Rank.LIEUTENANT,
		PieceData.Rank.CAPTAIN, PieceData.Rank.CAPTAIN, PieceData.Rank.CAPTAIN, PieceData.Rank.CAPTAIN,
		PieceData.Rank.MAJOR, PieceData.Rank.MAJOR, PieceData.Rank.MAJOR,
	]

	for i: int in range(min(remaining_ranks.size(), all_remaining.size())):
		board_state.add_piece(remaining_ranks[i], ai_team, all_remaining[i])
