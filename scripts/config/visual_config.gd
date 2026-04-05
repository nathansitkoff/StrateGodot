extends Node

# --- Team Colors ---
const TEAM_RED: Color = Color(0.9, 0.3, 0.3)
const TEAM_BLUE: Color = Color(0.3, 0.4, 0.9)
const TEAM_NEUTRAL: Color = Color(0.8, 0.8, 0.8)
const BUTTON_HIGHLIGHT: Color = Color(1.0, 0.9, 0.3)

# --- Board Colors ---
const BOARD_LIGHT: Color = Color(0.82, 0.76, 0.62)
const BOARD_DARK: Color = Color(0.55, 0.48, 0.36)
const LAKE_LIGHT: Color = Color(0.25, 0.45, 0.7)
const LAKE_DARK: Color = Color(0.18, 0.35, 0.58)
const BOARD_BORDER: Color = Color(0.25, 0.2, 0.15)
const GRID_LINE: Color = Color(0.4, 0.35, 0.28, 0.4)
const MOVE_HIGHLIGHT: Color = Color(0.3, 0.75, 0.3, 0.45)
const SELECTED_HIGHLIGHT: Color = Color(1.0, 0.9, 0.2, 0.45)
const LAST_MOVE_RED: Color = Color(1.0, 0.5, 0.1)
const LAST_MOVE_BLUE: Color = Color(0.1, 0.6, 1.0)
const INVALID_ROW_DIM: Color = Color(0.0, 0.0, 0.0, 0.3)

# --- Piece Colors ---
const RED_PIECE: Color = Color(0.8, 0.2, 0.2)
const BLUE_PIECE: Color = Color(0.2, 0.3, 0.8)
const HIDDEN_PIECE: Color = Color(0.5, 0.5, 0.5)
const RED_PIECE_BORDER: Color = Color(0.5, 0.1, 0.1)
const BLUE_PIECE_BORDER: Color = Color(0.1, 0.15, 0.5)
const HIDDEN_PIECE_BORDER: Color = Color(0.3, 0.3, 0.3)

# --- Frame Colors ---
const FRAME_OUTER: Color = Color(0.12, 0.08, 0.05)
const FRAME_MAIN: Color = Color(0.4, 0.28, 0.15)
const FRAME_INNER: Color = Color(0.5, 0.36, 0.2)
const FRAME_BEVEL: Color = Color(0.2, 0.14, 0.08)

# --- Icon Colors ---
const STAR_GOLD: Color = Color(1.0, 0.85, 0.2)
const FLAG_PENNANT: Color = Color(1.0, 0.9, 0.3)
const REVEALED_EYE: Color = Color(1.0, 0.85, 0.0)

# --- UI Colors ---
const MENU_BACKGROUND: Color = Color(0.15, 0.15, 0.2, 1)

# --- Layout ---
const SIDEBAR_WIDTH: int = 220
const TURN_BAR_HEIGHT: int = 36
const REPLAY_BAR_HEIGHT: int = 60

# --- Animation Timing ---
const SLIDE_DURATION: float = 0.15
const COMBAT_FLASH_TIME: float = 0.15
const COMBAT_FADE_TIME: float = 0.2
const COMBAT_FLASH_DECAY: float = 0.3
const LAST_MOVE_PULSE_SPEED: float = 3.0
const AI_MOVE_DELAY: float = 0.5

# --- AI Scoring ---
const WIN_SCORE: float = 10000.0


static func get_team_color(team: PieceData.Team) -> Color:
	if team == PieceData.Team.RED:
		return TEAM_RED
	return TEAM_BLUE


static func get_last_move_color(team: PieceData.Team) -> Color:
	if team == PieceData.Team.RED:
		return LAST_MOVE_RED
	return LAST_MOVE_BLUE
