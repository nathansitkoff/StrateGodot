extends Node

# Server entry point. Detects --server flag and starts the WebSocket server.
# Add as autoload. Only activates when --server is in command line args.
# Usage: godot --headless --path /path/to/project -- --server --port 9000

var _server: Node = null


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if "--server" not in args:
		queue_free()
		return

	var port: int = 9000
	for i: int in range(args.size()):
		if args[i] == "--port" and i + 1 < args.size():
			port = int(args[i + 1])

	print("=== StrateGodot Server ===")
	_server = Node.new()
	_server.set_script(load("res://scripts/network/server.gd"))
	add_child(_server)
	_server.start(port)
