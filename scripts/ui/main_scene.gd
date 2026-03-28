extends Control

@onready var board: Control = %Board
@onready var setup_phase: Control = %SetupPhase


func _ready() -> void:
	GameManager.phase_changed.connect(_on_phase_changed)
	setup_phase.setup_complete.connect(_on_setup_complete)
	# Start directly into a game for now (menu added in Phase 4)
	GameManager.start_game(GameManager.GameMode.LOCAL_2P)


func _on_phase_changed(phase: GameManager.GamePhase) -> void:
	match phase:
		GameManager.GamePhase.SETUP_RED:
			setup_phase.start_setup(PieceData.Team.RED)
		GameManager.GamePhase.SETUP_BLUE:
			setup_phase.start_setup(PieceData.Team.BLUE)
		GameManager.GamePhase.PLAY:
			setup_phase.visible = false
			board.refresh()
		GameManager.GamePhase.GAME_OVER:
			setup_phase.visible = false
			board.refresh()


func _on_setup_complete(team: PieceData.Team) -> void:
	GameManager.finish_setup(team)
