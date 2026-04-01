class_name GreedyAI
extends AIBase

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _init(ai_team: PieceData.Team = PieceData.Team.BLUE) -> void:
	super(ai_team)
	_rng.randomize()


func generate_setup(board_state: BoardState) -> void:
	var rows: Array[int] = board_state.get_setup_rows(team)
	# rows[0] = back, rows[1] = second, rows[2] = third, rows[3] = front
	var back_rows: Array[int] = [rows[0], rows[1]]
	var front_rows: Array[int] = [rows[2], rows[3]]

	var back_cells: Array[Vector2i] = []
	var front_cells: Array[Vector2i] = []
	for col: int in range(BoardState.BOARD_SIZE):
		for row: int in back_rows:
			var pos: Vector2i = Vector2i(col, row)
			if board_state.is_valid_cell(pos) and board_state.get_piece_at(pos) == -1:
				back_cells.append(pos)
		for row: int in front_rows:
			var pos: Vector2i = Vector2i(col, row)
			if board_state.is_valid_cell(pos) and board_state.get_piece_at(pos) == -1:
				front_cells.append(pos)

	back_cells.shuffle()
	front_cells.shuffle()

	# Place flag and bombs in back rows
	var back_idx: int = 0
	board_state.add_piece(PieceData.Rank.FLAG, team, back_cells[back_idx])
	back_idx += 1
	for i: int in range(PieceData.get_count(PieceData.Rank.BOMB)):
		if back_idx < back_cells.size():
			board_state.add_piece(PieceData.Rank.BOMB, team, back_cells[back_idx])
			back_idx += 1

	# Remaining back cells get overflow movers
	var overflow_back: Array[Vector2i] = []
	for i: int in range(back_idx, back_cells.size()):
		overflow_back.append(back_cells[i])

	# Place all movable pieces in front rows first, overflow to back
	var mover_cells: Array[Vector2i] = []
	mover_cells.append_array(front_cells)
	mover_cells.append_array(overflow_back)

	var mover_ranks: Array[int] = []
	for rank: int in PieceData.RANK_INFO:
		if PieceData.can_move(rank):
			for i: int in range(PieceData.get_count(rank)):
				mover_ranks.append(rank)

	for i: int in range(min(mover_ranks.size(), mover_cells.size())):
		board_state.add_piece(mover_ranks[i], team, mover_cells[i])


func choose_move(board_state: BoardState) -> Dictionary:
	var enemy_team: PieceData.Team = get_enemy_team()
	var my_pieces: Array[int] = board_state.get_team_pieces(team)
	my_pieces.shuffle()

	# Sort weakest first for rules that prefer expendable pieces
	var pieces_weakest_first: Array[int] = my_pieces.duplicate()
	pieces_weakest_first.sort_custom(func(a: int, b: int) -> bool:
		return board_state.pieces[a]["rank"] < board_state.pieces[b]["rank"]
	)

	# 1. Capture adjacent flag
	var move: Dictionary = _find_adjacent_attack_by_rank(board_state, my_pieces, PieceData.Rank.FLAG)
	if move.size() > 0:
		return move

	# 2. Send spy to adjacent Marshal
	move = _find_specific_attacker(board_state, PieceData.Rank.SPY, PieceData.Rank.MARSHAL)
	if move.size() > 0:
		return move

	# 3. Send miner to adjacent Bomb
	move = _find_specific_attacker(board_state, PieceData.Rank.MINER, PieceData.Rank.BOMB)
	if move.size() > 0:
		return move

	# 4. Attack adjacent revealed enemies we beat or tie
	move = _find_favorable_attack(board_state, my_pieces)
	if move.size() > 0:
		return move

	# 5. Attack adjacent unrevealed enemies with expendable pieces (weakest first)
	move = _find_probe_attack(board_state, pieces_weakest_first, enemy_team)
	if move.size() > 0:
		return move

	# 6. Route closest miner toward known Bomb
	move = _route_toward_revealed(board_state, PieceData.Rank.MINER, PieceData.Rank.BOMB)
	if move.size() > 0:
		return move

	# 7. Route spy toward known Marshal
	move = _route_toward_revealed(board_state, PieceData.Rank.SPY, PieceData.Rank.MARSHAL)
	if move.size() > 0:
		return move

	# 8. Move toward nearest unrevealed enemy (weakest first)
	move = _move_toward_unrevealed(board_state, pieces_weakest_first, enemy_team)
	if move.size() > 0:
		return move

	# 9. Advance forward (weakest first)
	move = _advance_forward(board_state, pieces_weakest_first)
	if move.size() > 0:
		return move

	# 10. Any non-losing move
	move = _any_nonlosing_move(board_state, my_pieces)
	if move.size() > 0:
		return move

	return {}


func _get_forward_dir() -> int:
	return -1 if team == PieceData.Team.RED else 1


# Rule 1: Find any piece that can capture a revealed enemy of a specific rank
func _find_adjacent_attack_by_rank(board_state: BoardState, my_pieces: Array[int], target_rank: PieceData.Rank) -> Dictionary:
	for piece_id: int in my_pieces:
		var piece: Dictionary = board_state.pieces[piece_id]
		if not PieceData.can_move(piece["rank"]):
			continue
		var moves: Array[Vector2i] = board_state.get_valid_moves(piece_id)
		for target_pos: Vector2i in moves:
			var target_id: int = board_state.get_piece_at(target_pos)
			if target_id != -1:
				var target: Dictionary = board_state.pieces[target_id]
				if target["revealed"] and target["rank"] == target_rank:
					return { "from": piece["pos"], "to": target_pos }
	return {}


# Rules 2, 3: Send a specific rank to attack a specific revealed enemy rank
func _find_specific_attacker(board_state: BoardState, attacker_rank: PieceData.Rank, defender_rank: PieceData.Rank) -> Dictionary:
	for piece_id: int in board_state.get_team_pieces(team):
		var piece: Dictionary = board_state.pieces[piece_id]
		if piece["rank"] != attacker_rank:
			continue
		var moves: Array[Vector2i] = board_state.get_valid_moves(piece_id)
		for target_pos: Vector2i in moves:
			var target_id: int = board_state.get_piece_at(target_pos)
			if target_id != -1:
				var target: Dictionary = board_state.pieces[target_id]
				if target["revealed"] and target["rank"] == defender_rank:
					return { "from": piece["pos"], "to": target_pos }
	return {}


# Rule 4: Attack revealed enemies where we win or tie
func _find_favorable_attack(board_state: BoardState, my_pieces: Array[int]) -> Dictionary:
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
			if result == Combat.Result.ATTACKER_WINS or result == Combat.Result.BOTH_DIE:
				var value: int = target["rank"] as int
				if value > best_value:
					best_value = value
					best_move = { "from": piece["pos"], "to": target_pos }

	return best_move


# Rule 5: Attack unrevealed enemies with expendable pieces (weakest first)
func _find_probe_attack(board_state: BoardState, pieces_weakest_first: Array[int], enemy_team: PieceData.Team) -> Dictionary:
	for piece_id: int in pieces_weakest_first:
		var piece: Dictionary = board_state.pieces[piece_id]
		if not PieceData.can_move(piece["rank"]):
			continue
		# Don't send valuable pieces: Marshal, General, Colonel, Miner, Spy
		if piece["rank"] in [PieceData.Rank.MARSHAL, PieceData.Rank.GENERAL, PieceData.Rank.COLONEL, PieceData.Rank.MINER, PieceData.Rank.SPY]:
			continue
		var moves: Array[Vector2i] = board_state.get_valid_moves(piece_id)
		for target_pos: Vector2i in moves:
			var target_id: int = board_state.get_piece_at(target_pos)
			if target_id != -1:
				var target: Dictionary = board_state.pieces[target_id]
				if target["team"] == enemy_team and not target["revealed"]:
					return { "from": piece["pos"], "to": target_pos }
	return {}


# Rules 6, 7: Route a specific piece type toward a revealed enemy type
func _route_toward_revealed(board_state: BoardState, mover_rank: PieceData.Rank, target_rank: PieceData.Rank) -> Dictionary:
	# Find all revealed enemy pieces of target rank
	var enemy_team: PieceData.Team = get_enemy_team()
	var targets: Array[Vector2i] = []
	for piece_id: int in board_state.pieces:
		var piece: Dictionary = board_state.pieces[piece_id]
		if piece["team"] == enemy_team and piece["revealed"] and piece["rank"] == target_rank:
			targets.append(piece["pos"])

	if targets.size() == 0:
		return {}

	# Find the closest mover of the right rank
	var best_move: Dictionary = {}
	var best_dist: int = 999

	for piece_id: int in board_state.get_team_pieces(team):
		var piece: Dictionary = board_state.pieces[piece_id]
		if piece["rank"] != mover_rank:
			continue
		# Find closest target
		var closest_target: Vector2i = targets[0]
		var closest_dist: int = _manhattan(piece["pos"], targets[0])
		for t: Vector2i in targets:
			var d: int = _manhattan(piece["pos"], t)
			if d < closest_dist:
				closest_dist = d
				closest_target = t

		# Find the move that gets closest to the target
		var step: Dictionary = _step_toward(board_state, piece_id, closest_target)
		if step.size() > 0:
			var new_dist: int = _manhattan(step["to"], closest_target)
			if new_dist < closest_dist and new_dist < best_dist:
				best_dist = new_dist
				best_move = step

	return best_move


# Rule 8: Move toward nearest unrevealed enemy (weakest piece first)
func _move_toward_unrevealed(board_state: BoardState, pieces_weakest_first: Array[int], enemy_team: PieceData.Team) -> Dictionary:
	# Collect all unrevealed enemy positions
	var enemy_positions: Array[Vector2i] = []
	for piece_id: int in board_state.pieces:
		var piece: Dictionary = board_state.pieces[piece_id]
		if piece["team"] == enemy_team and not piece["revealed"]:
			enemy_positions.append(piece["pos"])

	if enemy_positions.size() == 0:
		return {}

	for piece_id: int in pieces_weakest_first:
		var piece: Dictionary = board_state.pieces[piece_id]
		if not PieceData.can_move(piece["rank"]):
			continue

		# Find closest unrevealed enemy
		var closest: Vector2i = enemy_positions[0]
		var closest_dist: int = _manhattan(piece["pos"], enemy_positions[0])
		for ep: Vector2i in enemy_positions:
			var d: int = _manhattan(piece["pos"], ep)
			if d < closest_dist:
				closest_dist = d
				closest = ep

		var step: Dictionary = _step_toward(board_state, piece_id, closest)
		if step.size() > 0:
			var new_dist: int = _manhattan(step["to"], closest)
			if new_dist < closest_dist:
				return step

	return {}


# Rule 9: Advance forward (weakest first)
func _advance_forward(board_state: BoardState, pieces_weakest_first: Array[int]) -> Dictionary:
	var forward: int = _get_forward_dir()
	for piece_id: int in pieces_weakest_first:
		var piece: Dictionary = board_state.pieces[piece_id]
		if not PieceData.can_move(piece["rank"]):
			continue
		var pos: Vector2i = piece["pos"]
		var forward_pos: Vector2i = Vector2i(pos.x, pos.y + forward)

		# Try forward
		if _is_valid_empty(board_state, forward_pos):
			return { "from": pos, "to": forward_pos }

		# Water deflection: try right, then left
		if board_state.is_in_bounds(forward_pos) and board_state.is_lake(forward_pos):
			var right: Vector2i = Vector2i(pos.x + 1, pos.y)
			if _is_valid_empty(board_state, right):
				return { "from": pos, "to": right }
			var left: Vector2i = Vector2i(pos.x - 1, pos.y)
			if _is_valid_empty(board_state, left):
				return { "from": pos, "to": left }

	return {}


# Rule 10: Any valid move that isn't a known loss
func _any_nonlosing_move(board_state: BoardState, my_pieces: Array[int]) -> Dictionary:
	var all_moves: Array[Dictionary] = []
	for piece_id: int in my_pieces:
		var piece: Dictionary = board_state.pieces[piece_id]
		if not PieceData.can_move(piece["rank"]):
			continue
		var moves: Array[Vector2i] = board_state.get_valid_moves(piece_id)
		for target_pos: Vector2i in moves:
			var target_id: int = board_state.get_piece_at(target_pos)
			if target_id != -1:
				var target: Dictionary = board_state.pieces[target_id]
				if target["revealed"]:
					var result: Combat.Result = Combat.resolve(piece["rank"], target["rank"])
					if result == Combat.Result.DEFENDER_WINS:
						continue
			all_moves.append({ "from": piece["pos"], "to": target_pos })

	if all_moves.size() > 0:
		return all_moves[_rng.randi_range(0, all_moves.size() - 1)]
	return {}


# --- Helpers ---


func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)


# Try to step toward a target: forward first, then water deflection
func _step_toward(board_state: BoardState, piece_id: int, target: Vector2i) -> Dictionary:
	var piece: Dictionary = board_state.pieces[piece_id]
	var pos: Vector2i = piece["pos"]
	var moves: Array[Vector2i] = board_state.get_valid_moves(piece_id)

	# Only consider non-combat moves
	var empty_moves: Array[Vector2i] = []
	for m: Vector2i in moves:
		if board_state.get_piece_at(m) == -1:
			empty_moves.append(m)

	if empty_moves.size() == 0:
		return {}

	# Pick the move that minimizes distance to target
	var best_pos: Vector2i = empty_moves[0]
	var best_dist: int = _manhattan(empty_moves[0], target)
	for m: Vector2i in empty_moves:
		var d: int = _manhattan(m, target)
		if d < best_dist:
			best_dist = d
			best_pos = m

	# Only return if it's strictly closer than current position
	if best_dist < _manhattan(pos, target):
		return { "from": pos, "to": best_pos }

	# Water deflection: if forward is water, try right then left
	var forward: int = _get_forward_dir()
	var forward_pos: Vector2i = Vector2i(pos.x, pos.y + forward)
	if board_state.is_in_bounds(forward_pos) and board_state.is_lake(forward_pos):
		var right: Vector2i = Vector2i(pos.x + 1, pos.y)
		if right in empty_moves:
			return { "from": pos, "to": right }
		var left: Vector2i = Vector2i(pos.x - 1, pos.y)
		if left in empty_moves:
			return { "from": pos, "to": left }

	return {}


func _is_valid_empty(board_state: BoardState, pos: Vector2i) -> bool:
	return board_state.is_valid_cell(pos) and board_state.get_piece_at(pos) == -1
