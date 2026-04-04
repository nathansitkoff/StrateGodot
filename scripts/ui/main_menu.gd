extends ColorRect

signal mode_selected(mode: GameManager.GameMode)
signal headless_selected
signal replays_selected
signal network_selected

@onready var local_button: Button = %LocalButton
@onready var ai_button: Button = %AIButton
@onready var ai_test_button: Button = %AITestButton
@onready var ai_vs_ai_button: Button = %AIvsAIButton
@onready var headless_button: Button = %HeadlessButton
@onready var replays_button: Button = %ReplaysButton
@onready var network_button: Button = %NetworkButton
@onready var exit_button: Button = %ExitButton


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
	ai_vs_ai_button.pressed.connect(func() -> void:
		visible = false
		mode_selected.emit(GameManager.GameMode.AI_VS_AI)
	)
	headless_button.pressed.connect(func() -> void:
		visible = false
		headless_selected.emit()
	)
	replays_button.pressed.connect(func() -> void:
		visible = false
		replays_selected.emit()
	)
	network_button.pressed.connect(func() -> void:
		visible = false
		network_selected.emit()
	)
	exit_button.pressed.connect(func() -> void:
		get_tree().quit()
	)
