extends ColorRect

signal closed

@onready var label: Label = %CombatLabel

var _auto_close_timer: float = 0.0


func show_result(attacker_rank: PieceData.Rank, defender_rank: PieceData.Rank, attacker_team: PieceData.Team, result: Combat.Result) -> void:
	var atk_name: String = PieceData.get_rank_name(attacker_rank)
	var atk_display: String = PieceData.get_rank_display(attacker_rank)
	var def_name: String = PieceData.get_rank_name(defender_rank)
	var def_display: String = PieceData.get_rank_display(defender_rank)
	var atk_team: String = "RED" if attacker_team == PieceData.Team.RED else "BLUE"

	var result_text: String
	match result:
		Combat.Result.ATTACKER_WINS:
			result_text = "%s wins!" % atk_team
		Combat.Result.DEFENDER_WINS:
			var def_team: String = "BLUE" if attacker_team == PieceData.Team.RED else "RED"
			result_text = "%s wins!" % def_team
		Combat.Result.BOTH_DIE:
			result_text = "Both destroyed!"

	label.text = "%s (%s) vs %s (%s)\n%s\n\nClick to continue" % [atk_name, atk_display, def_name, def_display, result_text]
	visible = true


func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			visible = false
			closed.emit()
