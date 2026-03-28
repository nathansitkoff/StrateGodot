extends ColorRect

signal acknowledged

@onready var label: Label = %TurnSwitchLabel


func show_turn(team: PieceData.Team) -> void:
	var team_name: String = "RED" if team == PieceData.Team.RED else "BLUE"
	label.text = "Player %s's Turn\n\nClick to Continue" % team_name
	visible = true


func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			visible = false
			acknowledged.emit()
