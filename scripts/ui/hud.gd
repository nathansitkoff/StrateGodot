extends PanelContainer

@onready var turn_label: Label = %TurnLabel
@onready var combat_container: VBoxContainer = %CombatContainer
@onready var combat_label_1: Label = %CombatLabel1
@onready var combat_label_2: Label = %CombatLabel2
@onready var red_captured_label: Label = %RedCapturedLabel
@onready var red_captured_list: Label = %RedCapturedList
@onready var blue_captured_label: Label = %BlueCapturedLabel
@onready var blue_captured_list: Label = %BlueCapturedList

var _last_combat_text: String = ""


func _ready() -> void:
	combat_container.visible = false


func update_turn(team: PieceData.Team) -> void:
	var team_name: String = "RED" if team == PieceData.Team.RED else "BLUE"
	var color: Color = Color(0.9, 0.3, 0.3) if team == PieceData.Team.RED else Color(0.3, 0.4, 0.9)
	turn_label.text = "%s's Turn" % team_name
	turn_label.add_theme_color_override("font_color", color)


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


func update_captured() -> void:
	var red_lost: Array = GameManager.captured_pieces[PieceData.Team.RED]
	var blue_lost: Array = GameManager.captured_pieces[PieceData.Team.BLUE]

	red_captured_label.text = "Red Lost (%d):" % red_lost.size()
	red_captured_list.text = _format_captured(red_lost)

	blue_captured_label.text = "Blue Lost (%d):" % blue_lost.size()
	blue_captured_list.text = _format_captured(blue_lost)


func _format_captured(pieces: Array) -> String:
	if pieces.size() == 0:
		return "  None"

	var counts: Dictionary = {}
	for rank: int in pieces:
		if rank not in counts:
			counts[rank] = 0
		counts[rank] += 1

	var sorted_ranks: Array = counts.keys()
	sorted_ranks.sort()
	sorted_ranks.reverse()

	var lines: Array[String] = []
	for rank: int in sorted_ranks:
		var display: String = PieceData.get_rank_display(rank)
		var name: String = PieceData.get_rank_name(rank)
		if counts[rank] > 1:
			lines.append("  %s (%s) x%d" % [name, display, counts[rank]])
		else:
			lines.append("  %s (%s)" % [name, display])

	return "\n".join(lines)
