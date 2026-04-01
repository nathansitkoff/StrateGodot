class_name GreedyAI
extends AIBase

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _init(ai_team: PieceData.Team = PieceData.Team.BLUE) -> void:
	super(ai_team)
	_rng.randomize()


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


# Rule 4: Attack revealed enemies where we win or tie, or guaranteed wins on unrevealed
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
			if target["team"] == team:
				continue

			if target["revealed"]:
				var result: Combat.Result = Combat.resolve(piece["rank"], target["rank"])
				if result == Combat.Result.ATTACKER_WINS or result == Combat.Result.BOTH_DIE:
					var value: int = target["rank"] as int
					if value > best_value:
						best_value = value
						best_move = { "from": piece["pos"], "to": target_pos }
			else:
				if is_guaranteed_win(piece["rank"], target_id, board_state):
					var max_rank: int = get_max_possible_rank(target_id, board_state)
					if max_rank > best_value:
						best_value = max_rank
						best_move = { "from": piece["pos"], "to": target_pos }

	return best_move


# Rule 5: Attack unrevealed enemies with expendable pieces (weakest first), skip guaranteed losses
func _find_probe_attack(board_state: BoardState, pieces_weakest_first: Array[int], enemy_team: PieceData.Team) -> Dictionary:
	for piece_id: int in pieces_weakest_first:
		var piece: Dictionary = board_state.pieces[piece_id]
		if not PieceData.can_move(piece["rank"]):
			continue
		if piece["rank"] in [PieceData.Rank.MARSHAL, PieceData.Rank.GENERAL, PieceData.Rank.COLONEL, PieceData.Rank.MINER, PieceData.Rank.SPY]:
			continue
		var moves: Array[Vector2i] = board_state.get_valid_moves(piece_id)
		for target_pos: Vector2i in moves:
			var target_id: int = board_state.get_piece_at(target_pos)
			if target_id != -1:
				var target: Dictionary = board_state.pieces[target_id]
				if target["team"] == enemy_team and not target["revealed"]:
					if not is_guaranteed_loss(piece["rank"], target_id, board_state):
						return { "from": piece["pos"], "to": target_pos }
	return {}


# Rules 6, 7: Route a specific piece type toward a revealed enemy type
func _route_toward_revealed(board_state: BoardState, mover_rank: PieceData.Rank, target_rank: PieceData.Rank) -> Dictionary:
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

		var step: Dictionary = _try_advance_toward(board_state, piece_id, closest_target)
		if step.size() > 0:
			var new_dist: int = _manhattan(step["to"], closest_target)
			if new_dist < best_dist:
				best_dist = new_dist
				best_move = step

	return best_move


# Rule 8: Move toward nearest unrevealed enemy (weakest piece first)
func _move_toward_unrevealed(board_state: BoardState, pieces_weakest_first: Array[int], enemy_team: PieceData.Team) -> Dictionary:
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

		var step: Dictionary = _try_advance_toward(board_state, piece_id, closest)
		if step.size() > 0:
			return step

	return {}


# Rule 9: Advance forward (weakest first)
func _advance_forward(board_state: BoardState, pieces_weakest_first: Array[int]) -> Dictionary:
	var forward: int = _get_forward_dir()
	for piece_id: int in pieces_weakest_first:
		var piece: Dictionary = board_state.pieces[piece_id]
		if not PieceData.can_move(piece["rank"]):
			continue
		# Use a far-away target straight ahead to drive forward movement
		var pos: Vector2i = piece["pos"]
		var target: Vector2i = Vector2i(pos.x, pos.y + forward * 20)
		var step: Dictionary = _try_advance_toward(board_state, piece_id, target)
		if step.size() > 0:
			return step

	return {}


# Rule 10: Any valid move that isn't a known or deduced loss
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
				elif is_guaranteed_loss(piece["rank"], target_id, board_state):
					continue
			all_moves.append({ "from": piece["pos"], "to": target_pos })

	if all_moves.size() > 0:
		return all_moves[_rng.randi_range(0, all_moves.size() - 1)]
	return {}


# --- Helpers ---


func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)


func _is_valid_empty(board_state: BoardState, pos: Vector2i) -> bool:
	return board_state.is_valid_cell(pos) and board_state.get_piece_at(pos) == -1


# Core movement helper: try to move piece toward target.
# 1. Try primary direction (toward target)
# 2. If blocked by empty/wall, try deflection (right then left with ahead check)
# 3. If blocked by friendly piece, try to nudge the blocker out of the way
# Uses get_valid_moves to ensure all game rules (including two-square) are respected.
func _try_advance_toward(board_state: BoardState, piece_id: int, target: Vector2i) -> Dictionary:
	var pos: Vector2i = board_state.pieces[piece_id]["pos"]
	var valid: Array[Vector2i] = board_state.get_valid_moves(piece_id)
	var dx: int = target.x - pos.x
	var dy: int = target.y - pos.y

	var primary: Vector2i
	if dy != 0:
		primary = Vector2i(0, 1 if dy > 0 else -1)
	elif dx != 0:
		primary = Vector2i(1 if dx > 0 else -1, 0)
	else:
		return {}

	var primary_pos: Vector2i = pos + primary

	# Try primary direction
	if primary_pos in valid and board_state.get_piece_at(primary_pos) == -1:
		return { "from": pos, "to": primary_pos }

	# Try deflection
	var ahead: Vector2i = primary

	var right: Vector2i = Vector2i(pos.x + 1, pos.y)
	var ahead_right: Vector2i = Vector2i(pos.x + 1, pos.y + ahead.y) if ahead.y != 0 else Vector2i(pos.x + 1 + ahead.x, pos.y)
	if right in valid and board_state.get_piece_at(right) == -1 and _is_valid_empty(board_state, ahead_right):
		return { "from": pos, "to": right }

	var left: Vector2i = Vector2i(pos.x - 1, pos.y)
	var ahead_left: Vector2i = Vector2i(pos.x - 1, pos.y + ahead.y) if ahead.y != 0 else Vector2i(pos.x - 1 + ahead.x, pos.y)
	if left in valid and board_state.get_piece_at(left) == -1 and _is_valid_empty(board_state, ahead_left):
		return { "from": pos, "to": left }

	# Primary blocked by friendly piece — try nudge
	if board_state.is_in_bounds(primary_pos) and not board_state.is_lake(primary_pos):
		var blocker_id: int = board_state.get_piece_at(primary_pos)
		if blocker_id != -1 and board_state.pieces[blocker_id]["team"] == team:
			var visited: Dictionary = { piece_id: true }
			var nudge: Dictionary = _try_nudge(board_state, blocker_id, primary, visited, 10)
			if nudge.size() > 0:
				return nudge

	return {}


# Recursively try to nudge a friendly piece out of the way.
# The piece should step sideways. If it can't, and it's blocked by another
# friendly piece in the push direction, recurse on that blocker.
# Returns a move for whichever piece at the end of the chain can actually move.
func _try_nudge(board_state: BoardState, blocker_id: int, push_dir: Vector2i, visited: Dictionary, depth: int) -> Dictionary:
	if depth <= 0:
		return {}
	if blocker_id in visited:
		return {}
	visited[blocker_id] = true

	var piece: Dictionary = board_state.pieces[blocker_id]
	if not PieceData.can_move(piece["rank"]):
		return {}

	var pos: Vector2i = piece["pos"]
	var valid: Array[Vector2i] = board_state.get_valid_moves(blocker_id)

	# Try stepping sideways (perpendicular to push direction)
	var sideways: Array[Vector2i] = []
	if push_dir.x == 0:
		# Pushing vertically, sidestep horizontally
		sideways = [Vector2i(pos.x + 1, pos.y), Vector2i(pos.x - 1, pos.y)]
	else:
		# Pushing horizontally, sidestep vertically
		sideways = [Vector2i(pos.x, pos.y + 1), Vector2i(pos.x, pos.y - 1)]

	for side: Vector2i in sideways:
		if side in valid and board_state.get_piece_at(side) == -1:
			return { "from": pos, "to": side }

	# Can't step aside — try pushing forward (same direction), maybe the next piece can move
	var forward_pos: Vector2i = pos + push_dir
	if board_state.is_in_bounds(forward_pos) and not board_state.is_lake(forward_pos):
		# If forward is empty, blocker can move forward
		if forward_pos in valid and board_state.get_piece_at(forward_pos) == -1:
			return { "from": pos, "to": forward_pos }
		# If forward is another friendly piece, recurse
		var next_blocker: int = board_state.get_piece_at(forward_pos)
		if next_blocker != -1 and board_state.pieces[next_blocker]["team"] == team:
			return _try_nudge(board_state, next_blocker, push_dir, visited, depth - 1)

	return {}
