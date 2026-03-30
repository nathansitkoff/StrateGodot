extends PanelContainer

@onready var remaining_label: Label = %LeftRemainingLabel
@onready var remaining_list: Label = %LeftRemainingList


func update_remaining(team: PieceData.Team) -> void:
	var team_name: String = "RED" if team == PieceData.Team.RED else "BLUE"
	remaining_label.text = "%s Remaining:" % team_name

	var lost: Array = GameManager.captured_pieces[team]
	var lost_counts: Dictionary = {}
	for rank: int in lost:
		if rank not in lost_counts:
			lost_counts[rank] = 0
		lost_counts[rank] += 1

	var lines: Array[String] = []
	var ranks: Array = PieceData.RANK_INFO.keys()
	ranks.sort()
	ranks.reverse()

	for rank: int in ranks:
		var info: Dictionary = PieceData.RANK_INFO[rank]
		var total: int = info["count"]
		var dead: int = lost_counts.get(rank, 0)
		var alive: int = total - dead
		var display: String = info["display"]
		var rank_name: String = info["name"]
		if alive > 0:
			lines.append("  %s (%s): %d/%d" % [rank_name, display, alive, total])
		else:
			lines.append("  %s (%s): 0/%d" % [rank_name, display, total])

	remaining_list.text = "\n".join(lines)
