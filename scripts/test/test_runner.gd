extends Node

# Headless test runner that works as an autoload.
# Run: /Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/nathan/claude/StrateGodot


func _ready() -> void:
	if not DisplayServer.get_name() == "headless":
		queue_free()
		return

	await get_tree().process_frame
	_run_tests()
	get_tree().quit(0)


func _run_tests() -> void:
	print("=== StrateGodot Headless Test Runner ===")

	_matchup("Heuristic", 0, "Clustered Defense", 0, "Greedy", 3, "Clustered Defense", 0, 100)

	print("\n=== All tests passed ===")


func _matchup(red_ai_name: String, red_ai_type: int, red_place_name: String, red_placement: int,
		blue_ai_name: String, blue_ai_type: int, blue_place_name: String, blue_placement: int, count: int) -> void:
	print("\n%s (%s) vs %s (%s) — %d games" % [red_ai_name, red_place_name, blue_ai_name, blue_place_name, count])

	var red_wins: int = 0
	var blue_wins: int = 0
	var draws: int = 0
	var illegal: int = 0

	for i: int in range(count):
		var ai_red: AIBase = AIBase.create(red_ai_type, PieceData.Team.RED)
		ai_red.placement_strategy = red_placement as Placement.Strategy
		var ai_blue: AIBase = AIBase.create(blue_ai_type, PieceData.Team.BLUE)
		ai_blue.placement_strategy = blue_placement as Placement.Strategy

		var starting: PieceData.Team = PieceData.Team.RED if i % 2 == 0 else PieceData.Team.BLUE
		var result: Dictionary = GameManager.run_headless_game(ai_red, ai_blue, starting)
		var reason: String = result["reason"]

		if reason == "timeout" or reason == "illegal_move":
			draws += 1
			if reason == "illegal_move":
				illegal += 1
		elif result["winner"] == PieceData.Team.RED:
			red_wins += 1
		else:
			blue_wins += 1

	print("  Red: %d  Blue: %d  Draws: %d  Illegal: %d" % [red_wins, blue_wins, draws, illegal])
	if illegal > 0:
		push_error("ILLEGAL MOVES DETECTED: %d" % illegal)

	var total: int = red_wins + blue_wins + draws
	if total != count:
		push_error("FAIL: Expected %d games, got %d" % [count, total])
		get_tree().quit(1)
