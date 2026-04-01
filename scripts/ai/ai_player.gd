class_name HeuristicAI
extends AIBase

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _init(ai_team: PieceData.Team = PieceData.Team.BLUE) -> void:
	super(ai_team)
	_rng.randomize()


func choose_move(board_state: BoardState) -> Dictionary:
	var my_pieces: Array[int] = board_state.get_team_pieces(team)
	var shuffled_pieces: Array[int] = my_pieces.duplicate()
	shuffled_pieces.shuffle()
	var enemy_team: PieceData.Team = get_enemy_team()

	var flag_move: Dictionary = _find_flag_capture(board_state, shuffled_pieces)
	if flag_move.size() > 0:
		return flag_move

	var winning_attack: Dictionary = _find_winning_attack(board_state, shuffled_pieces)
	if winning_attack.size() > 0:
		return winning_attack

	var retreat: Dictionary = _find_retreat(board_state, shuffled_pieces, enemy_team)
	if retreat.size() > 0:
		return retreat

	var probe: Dictionary = _find_scout_probe(board_state, shuffled_pieces, enemy_team)
	if probe.size() > 0:
		return probe

	var advance: Dictionary = _find_advance(board_state, shuffled_pieces)
	if advance.size() > 0:
		return advance

	var random: Dictionary = _find_random_move(board_state, shuffled_pieces)
	if random.size() > 0:
		return random

	return _find_any_move(board_state, shuffled_pieces)


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
			if target["team"] == team:
				continue

			if target["revealed"]:
				var result: Combat.Result = Combat.resolve(piece["rank"], target["rank"])
				if result == Combat.Result.ATTACKER_WINS:
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


func _find_retreat(board_state: BoardState, my_pieces: Array[int], enemy_team: PieceData.Team) -> Dictionary:
	var directions: Array[Vector2i] = [
		Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0),
	]

	for piece_id: int in my_pieces:
		var piece: Dictionary = board_state.pieces[piece_id]
		if not piece["revealed"] or not PieceData.can_move(piece["rank"]):
			continue
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
			if target_id != -1:
				var target: Dictionary = board_state.pieces[target_id]
				if target["team"] == enemy_team and not target["revealed"]:
					if not is_guaranteed_loss(piece["rank"], target_id, board_state):
						candidates.append({ "from": piece["pos"], "to": target_pos, "priority": 2 })
			elif (target_pos.y - piece["pos"].y) * forward_dir > 0:
				candidates.append({ "from": piece["pos"], "to": target_pos, "priority": 1 })

	if candidates.size() > 0:
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
			var target_id: int = board_state.get_piece_at(target_pos)
			if target_id != -1:
				var target: Dictionary = board_state.pieces[target_id]
				if target["revealed"]:
					var result: Combat.Result = Combat.resolve(piece["rank"], target["rank"])
					if result != Combat.Result.ATTACKER_WINS:
						continue
				elif is_guaranteed_loss(piece["rank"], target_id, board_state):
					continue
			all_moves.append({ "from": piece["pos"], "to": target_pos })

	if all_moves.size() > 0:
		return all_moves[_rng.randi_range(0, all_moves.size() - 1)]

	return {}


func _find_any_move(board_state: BoardState, my_pieces: Array[int]) -> Dictionary:
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
