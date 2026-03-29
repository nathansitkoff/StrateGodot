extends PanelContainer

@onready var turn_label: Label = %TurnLabel
@onready var enemy_remaining_label: Label = %EnemyRemainingLabel
@onready var enemy_remaining_list: Label = %EnemyRemainingList
@onready var combat_container: VBoxContainer = %CombatContainer
@onready var combat_label_1: Label = %CombatLabel1
@onready var combat_label_2: Label = %CombatLabel2

var _last_combat_text: String = ""


func _ready() -> void:
	combat_container.visible = false


func update_turn(team: PieceData.Team) -> void:
	var team_name: String = "RED" if team == PieceData.Team.RED else "BLUE"
	var color: Color = Color(0.9, 0.3, 0.3) if team == PieceData.Team.RED else Color(0.3, 0.4, 0.9)
	turn_label.text = "%s's Turn" % team_name
	turn_label.add_theme_color_override("font_color", color)


func update_enemy_remaining(viewing_team: PieceData.Team) -> void:
	var enemy_team: PieceData.Team
	if viewing_team == PieceData.Team.RED:
		enemy_team = PieceData.Team.BLUE
	else:
		enemy_team = PieceData.Team.RED

	var enemy_name: String = "RED" if enemy_team == PieceData.Team.RED else "BLUE"
	enemy_remaining_label.text = "%s Remaining:" % enemy_name

	# Start with full counts, subtract captured
	var lost: Array = GameManager.captured_pieces[enemy_team]
	var lost_counts: Dictionary = {}
	for rank: int in lost:
		if rank not in lost_counts:
			lost_counts[rank] = 0
		lost_counts[rank] += 1

	var lines: Array[String] = []
	# Sort ranks descending (highest first)
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

	enemy_remaining_list.text = "\n".join(lines)


func show_combat_result(atk_rank: PieceData.Rank, def_rank: PieceData.Rank, atk_team: PieceData.Team, result: Combat.Result) -> void:
	var atk_name: String = PieceData.get_rank_name(atk_rank)
	var atk_display: String = PieceData.get_rank_display(atk_rank)
	var def_name: String = PieceData.get_rank_name(def_rank)
	var def_display: String = PieceData.get_rank_display(def_rank)

	var result_text: String
	match result:
		Combat.Result.ATTACKER_WINS:
			result_text = "Attacker wins!"
		Combat.Result.DEFENDER_WINS:
			result_text = "Defender wins!"
		Combat.Result.BOTH_DIE:
			result_text = "Both destroyed!"

	var new_text: String = "%s (%s) vs %s (%s)\n%s" % [atk_name, atk_display, def_name, def_display, result_text]

	# Shift current to previous
	combat_label_2.text = _last_combat_text
	combat_label_2.visible = _last_combat_text != ""
	combat_label_1.text = new_text
	_last_combat_text = new_text

	combat_container.visible = true


func clear_combat() -> void:
	combat_container.visible = false
	combat_label_1.text = ""
	combat_label_2.text = ""
	combat_label_2.visible = false
	_last_combat_text = ""
