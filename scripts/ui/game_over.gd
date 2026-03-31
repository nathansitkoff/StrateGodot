extends ColorRect

signal play_again_pressed

@onready var label: Label = %GameOverLabel
@onready var play_again_button: Button = %PlayAgainButton


func _ready() -> void:
	play_again_button.pressed.connect(func() -> void:
		visible = false
		play_again_pressed.emit()
	)


func show_winner(team: PieceData.Team) -> void:
	var team_name: String = PieceData.get_team_name(team)
	label.text = "Player %s Wins!" % team_name
	visible = true
