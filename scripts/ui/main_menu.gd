extends ColorRect

signal mode_selected(mode: GameManager.GameMode)

@onready var local_button: Button = %LocalButton
@onready var ai_button: Button = %AIButton
@onready var ai_test_button: Button = %AITestButton


func _ready() -> void:
	local_button.pressed.connect(func() -> void:
		visible = false
		mode_selected.emit(GameManager.GameMode.LOCAL_2P)
	)
	ai_button.pressed.connect(func() -> void:
		visible = false
		mode_selected.emit(GameManager.GameMode.VS_AI)
	)
	ai_test_button.pressed.connect(func() -> void:
		visible = false
		mode_selected.emit(GameManager.GameMode.AI_TEST)
	)
