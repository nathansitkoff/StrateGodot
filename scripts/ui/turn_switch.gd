extends ColorRect

signal acknowledged

@onready var label: Label = %TurnSwitchLabel


func show_turn(team: PieceData.Team, board_only: bool = false) -> void:
	var team_name: String = PieceData.get_team_name(team)
	label.text = "Player %s's Turn\n\nClick to Continue" % team_name
	if board_only:
		offset_left = VisualConfig.SIDEBAR_WIDTH
		offset_top = VisualConfig.TURN_BAR_HEIGHT
		offset_right = -VisualConfig.SIDEBAR_WIDTH
		offset_bottom = 0
	else:
		offset_left = 0
		offset_top = 0
		offset_right = 0
		offset_bottom = 0
	visible = true


func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			visible = false
			acknowledged.emit()
