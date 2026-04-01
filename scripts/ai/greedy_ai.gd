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

		var step: Dictionary = _try_advance_toward(board_state, piece["pos"], closest_target)
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

		var step: Dictionary = _try_advance_toward(board_state, piece["pos"], closest)
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
		var pos: Vector2i = piece["pos"]
		# Use a far-away target straight ahead to drive forward movement
		var target: Vector2i = Vector2i(pos.x, pos.y + forward * 20)
		var step: Dictionary = _try_advance_toward(board_state, pos, target)
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


# Core movement helper: try to move from pos toward target.
# 1. Determine the best cardinal direction toward the target
# 2. If that cell is free, go there
# 3. If blocked, deflect: try right if right and ahead-right are free, else left if left and ahead-left are free
# 4. If no deflection works, return empty (this piece can't advance)
func _try_advance_toward(board_state: BoardState, pos: Vector2i, target: Vector2i) -> Dictionary:
	var forward: int = _get_forward_dir()
	var dx: int = target.x - pos.x
	var dy: int = target.y - pos.y

	# Determine primary direction: prefer vertical (forward/backward) unless target is purely lateral
	var primary: Vector2i
	if dy != 0:
		# Move vertically toward target
		primary = Vector2i(0, 1 if dy > 0 else -1)
	elif dx != 0:
		# Target is on same row, move horizontally
		primary = Vector2i(1 if dx > 0 else -1, 0)
	else:
		# Already at target
		return {}

	var primary_pos: Vector2i = pos + primary

	# Try primary direction
	if _is_valid_empty(board_state, primary_pos):
		return { "from": pos, "to": primary_pos }

	# Primary blocked — try deflection
	# Determine "ahead" direction for deflection check (the direction we want to go)
	var ahead: Vector2i = primary

	# Try right deflection: right cell free AND ahead-right cell free
	var right: Vector2i = Vector2i(pos.x + 1, pos.y)
	var ahead_right: Vector2i = Vector2i(pos.x + 1, pos.y + ahead.y) if ahead.y != 0 else Vector2i(pos.x + 1 + ahead.x, pos.y)
	if _is_valid_empty(board_state, right) and _is_valid_empty(board_state, ahead_right):
		return { "from": pos, "to": right }

	# Try left deflection: left cell free AND ahead-left cell free
	var left: Vector2i = Vector2i(pos.x - 1, pos.y)
	var ahead_left: Vector2i = Vector2i(pos.x - 1, pos.y + ahead.y) if ahead.y != 0 else Vector2i(pos.x - 1 + ahead.x, pos.y)
	if _is_valid_empty(board_state, left) and _is_valid_empty(board_state, ahead_left):
		return { "from": pos, "to": left }

	return {}
