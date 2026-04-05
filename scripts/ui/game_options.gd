extends ColorRect

signal options_confirmed(first_team: PieceData.Team, red_ai_type: int, blue_ai_type: int, red_placement: int, blue_placement: int)

@onready var red_first_button: Button = %RedFirstButton
@onready var blue_first_button: Button = %BlueFirstButton
@onready var red_ai_row: HBoxContainer = %RedAIRow
@onready var blue_ai_row: HBoxContainer = %BlueAIRow
@onready var red_ai_select: OptionButton = %OptRedAISelect
@onready var blue_ai_select: OptionButton = %OptBlueAISelect
@onready var red_place_row: HBoxContainer = %RedPlaceRow
@onready var blue_place_row: HBoxContainer = %BluePlaceRow
@onready var red_place_select: OptionButton = %OptRedPlaceSelect
@onready var blue_place_select: OptionButton = %OptBluePlaceSelect
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
		options_confirmed.emit(_first_team, red_ai_select.selected, blue_ai_select.selected, red_place_select.selected, blue_place_select.selected)
	)
	for ai_name: String in AIBase.AI_NAMES:
		red_ai_select.add_item(ai_name)
		blue_ai_select.add_item(ai_name)
	for strat_name: String in Placement.STRATEGY_NAMES:
		red_place_select.add_item(strat_name)
		blue_place_select.add_item(strat_name)


func show_options(mode: GameManager.GameMode) -> void:
	_first_team = PieceData.Team.RED
	_update_selection()

	var show_ai: bool = mode != GameManager.GameMode.LOCAL_2P
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

	# Placement configurable for AI players, but not in AI Test (handled during setup)
	if mode == GameManager.GameMode.AI_TEST:
		red_place_row.visible = false
		blue_place_row.visible = false
	else:
		red_place_row.visible = red_ai_row.visible
		blue_place_row.visible = show_ai

	visible = true


func _update_selection() -> void:
	if _first_team == PieceData.Team.RED:
		red_first_button.add_theme_color_override("font_color", VisualConfig.BUTTON_HIGHLIGHT)
		blue_first_button.remove_theme_color_override("font_color")
	else:
		blue_first_button.add_theme_color_override("font_color", VisualConfig.BUTTON_HIGHLIGHT)
		red_first_button.remove_theme_color_override("font_color")
