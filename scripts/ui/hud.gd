extends PanelContainer

@onready var enemy_remaining_label: Label = %EnemyRemainingLabel
@onready var enemy_remaining_list: Label = %EnemyRemainingList
@onready var combat_container: VBoxContainer = %CombatContainer
@onready var combat_label_1: Label = %CombatLabel1
@onready var combat_label_2: Label = %CombatLabel2

var _last_combat_text: String = ""


func _ready() -> void:
	combat_container.visible = false


func update_enemy_remaining(viewing_team: PieceData.Team) -> void:
	var enemy_team: PieceData.Team
	if viewing_team == PieceData.Team.RED:
		enemy_team = PieceData.Team.BLUE
	else:
		enemy_team = PieceData.Team.RED
	enemy_remaining_label.text = "%s Remaining:" % PieceData.get_team_name(enemy_team)
	enemy_remaining_list.text = PieceData.format_remaining(enemy_team)


func show_combat_result(atk_rank: PieceData.Rank, def_rank: PieceData.Rank, _atk_team: PieceData.Team, result: Combat.Result) -> void:
	var atk_name: String = PieceData.get_rank_name(atk_rank)
	var atk_display: String = PieceData.get_rank_display(atk_rank)
	var def_name: String = PieceData.get_rank_name(def_rank)
	var def_display: String = PieceData.get_rank_display(def_rank)

	var result_text: String
	match result:
		Combat.Result.ATTACKER_WINS:
			result_text = "Attacker wins!"
		Combat.Result.DEFENDER_WINS:
			result_text = "Defender wins!"
		Combat.Result.BOTH_DIE:
			result_text = "Both destroyed!"

	var new_text: String = "%s (%s) vs %s (%s)\n%s" % [atk_name, atk_display, def_name, def_display, result_text]

	combat_label_2.text = _last_combat_text
	combat_label_2.visible = _last_combat_text != ""
	combat_label_1.text = new_text
	_last_combat_text = new_text

	combat_container.visible = true


func clear_combat() -> void:
	combat_container.visible = false
	combat_label_1.text = ""
	combat_label_2.text = ""
	combat_label_2.visible = false
	_last_combat_text = ""
