class_name Protocol
extends RefCounted

# Message types: Client → Server
const PLACE: String = "place"
const REMOVE_PIECE: String = "remove"
const READY: String = "ready"
const MOVE: String = "move"
const RANDOMIZE: String = "randomize"
const PLACEMENT_STRATEGY: String = "placement_strategy"

# Message types: Server → Client
const ASSIGN_TEAM: String = "assign_team"
const STATE_UPDATE: String = "state_update"
const PHASE_CHANGE: String = "phase_change"
const TURN_CHANGE: String = "turn_change"
const COMBAT: String = "combat"
const GAME_OVER: String = "game_over"
const ERROR: String = "error"
const SETUP_STATE: String = "setup_state"


static func encode(msg: Dictionary) -> String:
	return JSON.stringify(msg)


static func decode(text: String) -> Dictionary:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return {}
	return json.data
