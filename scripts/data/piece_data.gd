class_name PieceData
extends RefCounted

enum Rank {
	FLAG,
	SPY,
	SCOUT,
	MINER,
	SERGEANT,
	LIEUTENANT,
	CAPTAIN,
	MAJOR,
	COLONEL,
	GENERAL,
	MARSHAL,
	BOMB,
}

enum Team {
	RED,
	BLUE,
}

const RANK_INFO: Dictionary = {
	Rank.FLAG: { "name": "Flag", "display": "F", "count": 1, "can_move": false, "move_range": 0 },
	Rank.SPY: { "name": "Spy", "display": "1", "count": 1, "can_move": true, "move_range": 1 },
	Rank.SCOUT: { "name": "Scout", "display": "2", "count": 8, "can_move": true, "move_range": 10 },
	Rank.MINER: { "name": "Miner", "display": "3", "count": 5, "can_move": true, "move_range": 1 },
	Rank.SERGEANT: { "name": "Sergeant", "display": "4", "count": 4, "can_move": true, "move_range": 1 },
	Rank.LIEUTENANT: { "name": "Lieutenant", "display": "5", "count": 4, "can_move": true, "move_range": 1 },
	Rank.CAPTAIN: { "name": "Captain", "display": "6", "count": 4, "can_move": true, "move_range": 1 },
	Rank.MAJOR: { "name": "Major", "display": "7", "count": 3, "can_move": true, "move_range": 1 },
	Rank.COLONEL: { "name": "Colonel", "display": "8", "count": 2, "can_move": true, "move_range": 1 },
	Rank.GENERAL: { "name": "General", "display": "9", "count": 1, "can_move": true, "move_range": 1 },
	Rank.MARSHAL: { "name": "Marshal", "display": "10", "count": 1, "can_move": true, "move_range": 1 },
	Rank.BOMB: { "name": "Bomb", "display": "B", "count": 6, "can_move": false, "move_range": 0 },
}

static func get_total_pieces() -> int:
	var total: int = 0
	for rank: int in RANK_INFO:
		total += RANK_INFO[rank]["count"]
	return total

static func get_rank_name(rank: Rank) -> String:
	return RANK_INFO[rank]["name"]

static func get_rank_display(rank: Rank) -> String:
	return RANK_INFO[rank]["display"]

static func can_move(rank: Rank) -> bool:
	return RANK_INFO[rank]["can_move"]

static func get_move_range(rank: Rank) -> int:
	return RANK_INFO[rank]["move_range"]

static func get_count(rank: Rank) -> int:
	return RANK_INFO[rank]["count"]


static func format_remaining(team: Team) -> String:
	var lost: Array = GameManager.captured_pieces[team]
	var lost_counts: Dictionary = {}
	for rank: int in lost:
		if rank not in lost_counts:
			lost_counts[rank] = 0
		lost_counts[rank] += 1

	var lines: Array[String] = []
	var ranks: Array = RANK_INFO.keys()
	ranks.sort()
	ranks.reverse()

	for rank: int in ranks:
		var info: Dictionary = RANK_INFO[rank]
		var total: int = info["count"]
		var dead: int = lost_counts.get(rank, 0)
		var alive: int = total - dead
		lines.append("  %s (%s): %d/%d" % [info["name"], info["display"], alive, total])

	return "\n".join(lines)


static func get_team_name(team: Team) -> String:
	return "RED" if team == Team.RED else "BLUE"
