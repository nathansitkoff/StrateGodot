class_name AIPlayer
extends RefCounted

var team: PieceData.Team = PieceData.Team.BLUE
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()


func generate_setup(board_state: BoardState) -> void:
	var valid_rows: Array[int] = board_state.get_setup_rows(team)
	var back_row: int = valid_rows[0]
	var second_row: int = valid_rows[1]
	var front_rows: Array[int] = [valid_rows[2], valid_rows[3]]

	# Collect all cells by row category
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
	board_state.add_piece(PieceData.Rank.FLAG, team, flag_pos)

	# Place bombs around the flag (adjacent cells in back row + second row)
	var bomb_count: int = 0
	var bomb_positions: Array[Vector2i] = []
	for pos: Vector2i in back_cells.duplicate():
		if bomb_count >= 4 and abs(pos.x - flag_pos.x) > 1:
			continue
		if abs(pos.x - flag_pos.x) <= 1 and bomb_count < 6:
			bomb_positions.append(pos)
			back_cells.erase(pos)
			bomb_count += 1
	# Place remaining bombs in second row near flag
	for pos: Vector2i in second_cells.duplicate():
		if bomb_count >= 6:
			break
		if abs(pos.x - flag_pos.x) <= 1:
			bomb_positions.append(pos)
			second_cells.erase(pos)
			bomb_count += 1
	# Fill remaining bombs anywhere in back/second
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
		board_state.add_piece(PieceData.Rank.BOMB, team, pos)

	# Remaining cells pool: back + second + front
	var remaining_cells: Array[Vector2i] = []
	remaining_cells.append_array(back_cells)
	remaining_cells.append_array(second_cells)
	remaining_cells.append_array(front_cells)
	remaining_cells.shuffle()

	# Place high-value pieces in back two rows
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
			board_state.add_piece(rank, team, back_and_second[cell_idx])
			cell_idx += 1

	# Scouts biased toward front rows
	var scout_cells: Array[Vector2i] = []
	scout_cells.append_array(other_cells)
	for i: int in range(cell_idx, back_and_second.size()):
		scout_cells.append(back_and_second[i])
	scout_cells.shuffle()
	# Move front cells to the beginning for scouts
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

	# Place scouts first (8 of them, preferring front)
	var placed: int = 0
	var scout_count: int = PieceData.get_count(PieceData.Rank.SCOUT)
	var used_positions: Array[Vector2i] = []
	for pos: Vector2i in ordered_cells:
		if placed >= scout_count:
			break
		board_state.add_piece(PieceData.Rank.SCOUT, team, pos)
		used_positions.append(pos)
		placed += 1

	# Remaining pieces in remaining cells
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
		board_state.add_piece(remaining_ranks[i], team, final_cells[i])


func choose_move(board_state: BoardState) -> Dictionary:
	# Returns { "from": Vector2i, "to": Vector2i }
	var my_pieces: Array[int] = board_state.get_team_pieces(team)
	var enemy_team: PieceData.Team = PieceData.Team.RED if team == PieceData.Team.BLUE else PieceData.Team.BLUE

	# 1. Capture known flag
	var flag_move: Dictionary = _find_flag_capture(board_state, my_pieces)
	if flag_move.size() > 0:
		return flag_move

	# 2. Win obvious attacks against revealed enemies
	var winning_attack: Dictionary = _find_winning_attack(board_state, my_pieces)
	if winning_attack.size() > 0:
		return winning_attack

	# 3. Retreat revealed pieces from danger
	var retreat: Dictionary = _find_retreat(board_state, my_pieces, enemy_team)
	if retreat.size() > 0:
		return retreat

	# 4. Probe with scouts
	var probe: Dictionary = _find_scout_probe(board_state, my_pieces, enemy_team)
	if probe.size() > 0:
		return probe

	# 5. Advance forward
	var advance: Dictionary = _find_advance(board_state, my_pieces)
	if advance.size() > 0:
		return advance

	# 6. Random fallback
	return _find_random_move(board_state, my_pieces)


func _find_flag_capture(board_state: BoardState, my_pieces: Array[int]) -> Dictionary:
	for piece_id: int in my_pieces:
		var piece: Dictionary = board_state.pieces[piece_id]
		if not PieceData.can_move(piece["rank"]):
			continue
		var moves: Array[Vector2i] = board_state.get_valid_moves(piece_id)
		for target_pos: Vector2i in moves:
			var target_id: int = board_state.get_piece_at(target_pos)
			if target_id != -1:
				var target: Dictionary = board_state.pieces[target_id]
				if target["revealed"] and target["rank"] == PieceData.Rank.FLAG:
					return { "from": piece["pos"], "to": target_pos }
	return {}


func _find_winning_attack(board_state: BoardState, my_pieces: Array[int]) -> Dictionary:
	var best_move: Dictionary = {}
	var best_value: int = -1

	for piece_id: int in my_pieces:
		var piece: Dictionary = board_state.pieces[piece_id]
		if not PieceData.can_move(piece["rank"]):
			continue
		var moves: Array[Vector2i] = board_state.get_valid_moves(piece_id)
		for target_pos: Vector2i in moves:
			var target_id: int = board_state.get_piece_at(target_pos)
			if target_id == -1:
				continue
			var target: Dictionary = board_state.pieces[target_id]
			if not target["revealed"]:
				continue
			var result: Combat.Result = Combat.resolve(piece["rank"], target["rank"])
			if result == Combat.Result.ATTACKER_WINS:
				# Prefer capturing higher-value targets
				var value: int = target["rank"] as int
				if value > best_value:
					best_value = value
					best_move = { "from": piece["pos"], "to": target_pos }

	return best_move


func _find_retreat(board_state: BoardState, my_pieces: Array[int], enemy_team: PieceData.Team) -> Dictionary:
	var directions: Array[Vector2i] = [
		Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0),
	]

	for piece_id: int in my_pieces:
		var piece: Dictionary = board_state.pieces[piece_id]
		if not piece["revealed"] or not PieceData.can_move(piece["rank"]):
			continue
		# Check if threatened by adjacent stronger revealed enemy
		var threatened: bool = false
		for dir: Vector2i in directions:
			var adj: Vector2i = piece["pos"] + dir
			var adj_id: int = board_state.get_piece_at(adj)
			if adj_id != -1:
				var adj_piece: Dictionary = board_state.pieces[adj_id]
				if adj_piece["team"] == enemy_team and adj_piece["revealed"]:
					var result: Combat.Result = Combat.resolve(adj_piece["rank"], piece["rank"])
					if result == Combat.Result.ATTACKER_WINS:
						threatened = true
						break

		if threatened:
			var moves: Array[Vector2i] = board_state.get_valid_moves(piece_id)
			# Find a safe retreat square
			for move: Vector2i in moves:
				if board_state.get_piece_at(move) != -1:
					continue
				var safe: bool = true
				for dir: Vector2i in directions:
					var check: Vector2i = move + dir
					var check_id: int = board_state.get_piece_at(check)
					if check_id != -1:
						var check_piece: Dictionary = board_state.pieces[check_id]
						if check_piece["team"] == enemy_team and check_piece["revealed"]:
							var result: Combat.Result = Combat.resolve(check_piece["rank"], piece["rank"])
							if result == Combat.Result.ATTACKER_WINS:
								safe = false
								break
				if safe:
					return { "from": piece["pos"], "to": move }

	return {}


func _find_scout_probe(board_state: BoardState, my_pieces: Array[int], enemy_team: PieceData.Team) -> Dictionary:
	var forward_dir: int = 1 if team == PieceData.Team.BLUE else -1
	var candidates: Array[Dictionary] = []

	for piece_id: int in my_pieces:
		var piece: Dictionary = board_state.pieces[piece_id]
		if piece["rank"] != PieceData.Rank.SCOUT:
			continue
		var moves: Array[Vector2i] = board_state.get_valid_moves(piece_id)
		for target_pos: Vector2i in moves:
			var target_id: int = board_state.get_piece_at(target_pos)
			# Attack unrevealed enemies
			if target_id != -1:
				var target: Dictionary = board_state.pieces[target_id]
				if target["team"] == enemy_team and not target["revealed"]:
					candidates.append({ "from": piece["pos"], "to": target_pos, "priority": 2 })
			# Or move forward
			elif (target_pos.y - piece["pos"].y) * forward_dir > 0:
				candidates.append({ "from": piece["pos"], "to": target_pos, "priority": 1 })

	if candidates.size() > 0:
		# Prefer attacking over just moving
		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["priority"] > b["priority"])
		return { "from": candidates[0]["from"], "to": candidates[0]["to"] }

	return {}


func _find_advance(board_state: BoardState, my_pieces: Array[int]) -> Dictionary:
	var forward_dir: int = 1 if team == PieceData.Team.BLUE else -1
	var candidates: Array[Dictionary] = []

	for piece_id: int in my_pieces:
		var piece: Dictionary = board_state.pieces[piece_id]
		if not PieceData.can_move(piece["rank"]):
			continue
		# Skip high-value pieces from advancing aggressively
		if piece["rank"] == PieceData.Rank.MARSHAL or piece["rank"] == PieceData.Rank.GENERAL:
			continue
		var moves: Array[Vector2i] = board_state.get_valid_moves(piece_id)
		for target_pos: Vector2i in moves:
			if board_state.get_piece_at(target_pos) != -1:
				continue
			if (target_pos.y - piece["pos"].y) * forward_dir > 0:
				candidates.append({ "from": piece["pos"], "to": target_pos })

	if candidates.size() > 0:
		return candidates[_rng.randi_range(0, candidates.size() - 1)]

	return {}


func _find_random_move(board_state: BoardState, my_pieces: Array[int]) -> Dictionary:
	var all_moves: Array[Dictionary] = []
	for piece_id: int in my_pieces:
		var piece: Dictionary = board_state.pieces[piece_id]
		if not PieceData.can_move(piece["rank"]):
			continue
		var moves: Array[Vector2i] = board_state.get_valid_moves(piece_id)
		for target_pos: Vector2i in moves:
			all_moves.append({ "from": piece["pos"], "to": target_pos })

	if all_moves.size() > 0:
		return all_moves[_rng.randi_range(0, all_moves.size() - 1)]

	return {}
