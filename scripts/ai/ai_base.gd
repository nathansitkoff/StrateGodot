class_name AIBase
extends RefCounted

const AI_NAMES: Array[String] = ["Heuristic", "Monte Carlo", "Rollout", "Greedy"]

var team: PieceData.Team = PieceData.Team.BLUE
# Track enemy piece IDs that have moved at least once
var has_moved: Dictionary = {}

# Shared piece values for scoring
const PIECE_VALUES: Dictionary = {
	PieceData.Rank.FLAG: 0,
	PieceData.Rank.SPY: 7,
	PieceData.Rank.SCOUT: 2,
	PieceData.Rank.MINER: 8,
	PieceData.Rank.SERGEANT: 3,
	PieceData.Rank.LIEUTENANT: 4,
	PieceData.Rank.CAPTAIN: 5,
	PieceData.Rank.MAJOR: 6,
	PieceData.Rank.COLONEL: 7,
	PieceData.Rank.GENERAL: 9,
	PieceData.Rank.MARSHAL: 10,
	PieceData.Rank.BOMB: 4,
}


static func create(type_index: int, ai_team: PieceData.Team) -> AIBase:
	var script_path: String
	match type_index:
		1:
			script_path = "res://scripts/ai/monte_carlo_ai.gd"
		2:
			script_path = "res://scripts/ai/rollout_ai.gd"
		3:
			script_path = "res://scripts/ai/greedy_ai.gd"
		_:
			script_path = "res://scripts/ai/ai_player.gd"
	var ai: AIBase = load(script_path).new(ai_team)
	return ai


func _init(ai_team: PieceData.Team = PieceData.Team.BLUE) -> void:
	team = ai_team


func reset() -> void:
	has_moved.clear()


func notify_move(piece_id: int, piece_team: PieceData.Team) -> void:
	if piece_team != team:
		has_moved[piece_id] = true


func get_enemy_team() -> PieceData.Team:
	if team == PieceData.Team.BLUE:
		return PieceData.Team.RED
	return PieceData.Team.BLUE


func generate_setup(board_state: BoardState) -> void:
	var valid_rows: Array[int] = board_state.get_setup_rows(team)
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
	board_state.add_piece(PieceData.Rank.FLAG, team, flag_pos)

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
		board_state.add_piece(PieceData.Rank.BOMB, team, pos)

	var remaining_cells: Array[Vector2i] = []
	remaining_cells.append_array(back_cells)
	remaining_cells.append_array(second_cells)
	remaining_cells.append_array(front_cells)
	remaining_cells.shuffle()

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
		board_state.add_piece(PieceData.Rank.SCOUT, team, pos)
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
		board_state.add_piece(remaining_ranks[i], team, final_cells[i])


func choose_move(_board_state: BoardState) -> Dictionary:
	return {}


# --- Shared deduction utilities ---


func get_possible_ranks(piece_id: int, board_state: BoardState) -> Array[int]:
	var enemy_team: PieceData.Team = get_enemy_team()

	var accounted: Dictionary = {}
	for rank: int in PieceData.RANK_INFO:
		accounted[rank] = 0

	for pid: int in board_state.pieces:
		var p: Dictionary = board_state.pieces[pid]
		if p["team"] == enemy_team and p["revealed"]:
			accounted[p["rank"]] += 1

	var captured: Array = GameManager.captured_pieces[enemy_team]
	for rank: int in captured:
		accounted[rank] += 1

	var possible: Array[int] = []
	var piece_has_moved: bool = piece_id in has_moved

	for rank: int in PieceData.RANK_INFO:
		var total: int = PieceData.RANK_INFO[rank]["count"]
		if accounted[rank] >= total:
			continue
		if piece_has_moved and (rank == PieceData.Rank.BOMB or rank == PieceData.Rank.FLAG):
			continue
		possible.append(rank)

	return possible


func get_max_possible_rank(piece_id: int, board_state: BoardState) -> int:
	var possible: Array[int] = get_possible_ranks(piece_id, board_state)
	if possible.size() == 0:
		return PieceData.Rank.MARSHAL
	var max_rank: int = possible[0]
	for rank: int in possible:
		if rank > max_rank:
			max_rank = rank
	return max_rank


func is_guaranteed_win(our_rank: PieceData.Rank, enemy_piece_id: int, board_state: BoardState) -> bool:
	var possible: Array[int] = get_possible_ranks(enemy_piece_id, board_state)
	if possible.size() == 0:
		return false
	for rank: int in possible:
		var result: Combat.Result = Combat.resolve(our_rank, rank)
		if result != Combat.Result.ATTACKER_WINS:
			return false
	return true


func is_guaranteed_loss(our_rank: PieceData.Rank, enemy_piece_id: int, board_state: BoardState) -> bool:
	var possible: Array[int] = get_possible_ranks(enemy_piece_id, board_state)
	if possible.size() == 0:
		return false
	for rank: int in possible:
		var result: Combat.Result = Combat.resolve(our_rank, rank)
		if result == Combat.Result.ATTACKER_WINS:
			return false
	return true


# --- Shared utilities for Monte Carlo / Rollout AIs ---


func determinize(board_state: BoardState) -> BoardState:
	var world: BoardState = board_state.clone()
	var enemy: PieceData.Team = get_enemy_team()

	var unrevealed_ids: Array[int] = []
	for piece_id: int in world.pieces:
		var piece: Dictionary = world.pieces[piece_id]
		if piece["team"] == enemy and not piece["revealed"]:
			unrevealed_ids.append(piece_id)

	if unrevealed_ids.size() == 0:
		return world

	var accounted: Dictionary = {}
	for rank: int in PieceData.RANK_INFO:
		accounted[rank] = 0
	for piece_id: int in world.pieces:
		var piece: Dictionary = world.pieces[piece_id]
		if piece["team"] == enemy and piece["revealed"]:
			accounted[piece["rank"]] += 1
	var captured: Array = GameManager.captured_pieces[enemy]
	for rank: int in captured:
		accounted[rank] += 1

	var rank_pool: Array[int] = []
	for rank: int in PieceData.RANK_INFO:
		var total: int = PieceData.RANK_INFO[rank]["count"]
		var remaining: int = total - accounted[rank]
		for i: int in range(remaining):
			rank_pool.append(rank)

	var moved_ids: Array[int] = []
	var stationary_ids: Array[int] = []
	for pid: int in unrevealed_ids:
		if pid in has_moved:
			moved_ids.append(pid)
		else:
			stationary_ids.append(pid)

	var movable_ranks: Array[int] = []
	var immovable_ranks: Array[int] = []
	for rank: int in rank_pool:
		if rank == PieceData.Rank.BOMB or rank == PieceData.Rank.FLAG:
			immovable_ranks.append(rank)
		else:
			movable_ranks.append(rank)

	movable_ranks.shuffle()
	immovable_ranks.shuffle()

	var assignments: Dictionary = {}
	var movable_idx: int = 0
	for pid: int in moved_ids:
		if movable_idx < movable_ranks.size():
			assignments[pid] = movable_ranks[movable_idx]
			movable_idx += 1

	var stationary_pool: Array[int] = []
	for i: int in range(movable_idx, movable_ranks.size()):
		stationary_pool.append(movable_ranks[i])
	stationary_pool.append_array(immovable_ranks)
	stationary_pool.shuffle()

	var stat_idx: int = 0
	for pid: int in stationary_ids:
		if stat_idx < stationary_pool.size():
			assignments[pid] = stationary_pool[stat_idx]
			stat_idx += 1

	for pid: int in assignments:
		world.pieces[pid]["rank"] = assignments[pid]

	return world


func clone_caps() -> Dictionary:
	return {
		PieceData.Team.RED: GameManager.captured_pieces[PieceData.Team.RED].duplicate(),
		PieceData.Team.BLUE: GameManager.captured_pieces[PieceData.Team.BLUE].duplicate(),
	}


func clone_caps_from(caps: Dictionary) -> Dictionary:
	return {
		PieceData.Team.RED: caps[PieceData.Team.RED].duplicate(),
		PieceData.Team.BLUE: caps[PieceData.Team.BLUE].duplicate(),
	}


func score_position(bs: BoardState) -> float:
	var my_material: float = 0.0
	var enemy_material: float = 0.0
	var my_flag_pos: Vector2i = Vector2i(-1, -1)
	var my_miner_count: int = 0
	var enemy_miner_count: int = 0
	var enemy_bomb_count: int = 0
	var my_back_row: int = 9 if team == PieceData.Team.RED else 0

	for piece_id: int in bs.pieces:
		var piece: Dictionary = bs.pieces[piece_id]
		var rank: PieceData.Rank = piece["rank"]
		var value: float = PIECE_VALUES[rank]

		if piece["team"] == team:
			my_material += value
			if rank == PieceData.Rank.FLAG:
				my_flag_pos = piece["pos"]
			if rank == PieceData.Rank.MINER:
				my_miner_count += 1
			if PieceData.can_move(rank):
				var dist_from_back: int = abs(piece["pos"].y - my_back_row)
				my_material += dist_from_back * 0.1
		else:
			enemy_material += value
			if rank == PieceData.Rank.MINER:
				enemy_miner_count += 1
			if rank == PieceData.Rank.BOMB:
				enemy_bomb_count += 1

	var score: float = my_material - enemy_material

	if my_flag_pos != Vector2i(-1, -1):
		var directions: Array[Vector2i] = [
			Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0),
		]
		var adjacent_defenders: int = 0
		var adjacent_threats: int = 0
		for dir: Vector2i in directions:
			var adj: Vector2i = my_flag_pos + dir
			var adj_id: int = bs.get_piece_at(adj)
			if adj_id != -1:
				if bs.pieces[adj_id]["team"] == team:
					adjacent_defenders += 1
				else:
					adjacent_threats += 1
		score += adjacent_defenders * 2.0
		score -= adjacent_threats * 5.0

	if enemy_bomb_count > 0:
		score += my_miner_count * 3.0
		score -= enemy_miner_count * 3.0

	return score
