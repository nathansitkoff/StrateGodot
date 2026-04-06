class_name UIHelpers
extends RefCounted

# Shared UI management functions used by main_scene and network_game.


static func show_game_ui(board: Control, left_hud: PanelContainer, hud: PanelContainer, turn_bar: PanelContainer) -> void:
	board.visible = true
	left_hud.visible = true
	hud.visible = true
	turn_bar.visible = true
	board.set_game_layout()


static func hide_game_ui(left_hud: PanelContainer, hud: PanelContainer, turn_bar: PanelContainer, board: Control) -> void:
	left_hud.visible = false
	hud.visible = false
	turn_bar.visible = false
	board.reset_layout()


static func update_turn_label(label: Label, team: PieceData.Team, custom_text: String = "") -> void:
	var c: Color = VisualConfig.get_team_color(team)
	if custom_text != "":
		label.text = custom_text
	else:
		label.text = "%s's Turn" % PieceData.get_team_name(team)
	label.add_theme_color_override("font_color", c)


static func update_remaining(left_hud: PanelContainer, hud: PanelContainer, viewing_team: PieceData.Team) -> void:
	left_hud.update_remaining(PieceData.Team.RED)
	hud.update_enemy_remaining(viewing_team)
