extends PanelContainer

@onready var remaining_label: Label = %LeftRemainingLabel
@onready var remaining_list: Label = %LeftRemainingList


func update_remaining(team: PieceData.Team) -> void:
	remaining_label.text = "%s Remaining:" % PieceData.get_team_name(team)
	remaining_list.text = PieceData.format_remaining(team)
