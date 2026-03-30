extends ColorRect

signal options_confirmed(first_team: PieceData.Team)

@onready var red_first_button: Button = %RedFirstButton
@onready var blue_first_button: Button = %BlueFirstButton
@onready var ready_button: Button = %OptionsReadyButton

var _first_team: PieceData.Team = PieceData.Team.RED


func _ready() -> void:
	red_first_button.pressed.connect(func() -> void:
		_first_team = PieceData.Team.RED
		_update_selection()
	)
	blue_first_button.pressed.connect(func() -> void:
		_first_team = PieceData.Team.BLUE
		_update_selection()
	)
	ready_button.pressed.connect(func() -> void:
		visible = false
		options_confirmed.emit(_first_team)
	)


func show_options() -> void:
	_first_team = PieceData.Team.RED
	_update_selection()
	visible = true


func _update_selection() -> void:
	if _first_team == PieceData.Team.RED:
		red_first_button.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
		blue_first_button.remove_theme_color_override("font_color")
	else:
		blue_first_button.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
		red_first_button.remove_theme_color_override("font_color")
