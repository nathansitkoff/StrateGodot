extends ColorRect

signal options_confirmed(first_team: PieceData.Team, red_ai_type: int, blue_ai_type: int)

@onready var red_first_button: Button = %RedFirstButton
@onready var blue_first_button: Button = %BlueFirstButton
@onready var red_ai_row: HBoxContainer = %RedAIRow
@onready var blue_ai_row: HBoxContainer = %BlueAIRow
@onready var red_ai_select: OptionButton = %OptRedAISelect
@onready var blue_ai_select: OptionButton = %OptBlueAISelect
@onready var ready_button: Button = %OptionsReadyButton

var _first_team: PieceData.Team = PieceData.Team.RED

const AI_TYPES: Array[String] = ["Heuristic", "Monte Carlo"]


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
		options_confirmed.emit(_first_team, red_ai_select.selected, blue_ai_select.selected)
	)
	for ai_name: String in AI_TYPES:
		red_ai_select.add_item(ai_name)
		blue_ai_select.add_item(ai_name)


func show_options(mode: GameManager.GameMode) -> void:
	_first_team = PieceData.Team.RED
	_update_selection()

	# Show AI selectors based on mode
	match mode:
		GameManager.GameMode.LOCAL_2P:
			red_ai_row.visible = false
			blue_ai_row.visible = false
		GameManager.GameMode.VS_AI:
			red_ai_row.visible = false
			blue_ai_row.visible = true
		GameManager.GameMode.AI_TEST:
			red_ai_row.visible = false
			blue_ai_row.visible = true
		GameManager.GameMode.AI_VS_AI:
			red_ai_row.visible = true
			blue_ai_row.visible = true

	visible = true


func _update_selection() -> void:
	if _first_team == PieceData.Team.RED:
		red_first_button.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
		blue_first_button.remove_theme_color_override("font_color")
	else:
		blue_first_button.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
		red_first_button.remove_theme_color_override("font_color")
