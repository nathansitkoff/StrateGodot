class_name Combat
extends RefCounted

enum Result {
	ATTACKER_WINS,
	DEFENDER_WINS,
	BOTH_DIE,
}

static func resolve(attacker_rank: PieceData.Rank, defender_rank: PieceData.Rank) -> Result:
	# Attacking the flag is always a win
	if defender_rank == PieceData.Rank.FLAG:
		return Result.ATTACKER_WINS

	# Spy beats Marshal when attacking
	if attacker_rank == PieceData.Rank.SPY and defender_rank == PieceData.Rank.MARSHAL:
		return Result.ATTACKER_WINS

	# Miner defuses Bomb
	if attacker_rank == PieceData.Rank.MINER and defender_rank == PieceData.Rank.BOMB:
		return Result.ATTACKER_WINS

	# Non-miner vs Bomb loses
	if defender_rank == PieceData.Rank.BOMB:
		return Result.DEFENDER_WINS

	# Equal ranks: both die
	if attacker_rank == defender_rank:
		return Result.BOTH_DIE

	# Higher rank wins (enum values map to strength)
	if attacker_rank > defender_rank:
		return Result.ATTACKER_WINS
	else:
		return Result.DEFENDER_WINS
