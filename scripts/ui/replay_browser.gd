extends ColorRect

signal replay_selected(filepath: String)
signal back_pressed

@onready var replay_list: VBoxContainer = %ReplayList
@onready var browser_back_button: Button = %BrowserBackButton


func _ready() -> void:
	browser_back_button.pressed.connect(func() -> void:
		visible = false
		back_pressed.emit()
	)


func show_browser() -> void:
	_refresh_list()
	visible = true


func _refresh_list() -> void:
	for child: Node in replay_list.get_children():
		child.queue_free()

	# Ensure replay directory exists
	DirAccess.make_dir_recursive_absolute("user://replays")

	var dir: DirAccess = DirAccess.open("user://replays")
	if dir == null:
		return

	var files: Array[Dictionary] = []
	dir.list_dir_begin()
	var filename: String = dir.get_next()
	while filename != "":
		if filename.ends_with(".json"):
			var path: String = "user://replays/" + filename
			var mod_time: int = FileAccess.get_modified_time(path)
			files.append({ "name": filename, "time": mod_time })
		filename = dir.get_next()
	dir.list_dir_end()

	# Sort newest first by modification time
	files.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["time"] > b["time"]
	)

	if files.size() == 0:
		var label: Label = Label.new()
		label.text = "No replays saved yet."
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		replay_list.add_child(label)
		return

	for entry: Dictionary in files:
		var btn: Button = Button.new()
		btn.text = entry["name"].replace(".json", "")
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var filepath: String = "user://replays/" + entry["name"]
		btn.pressed.connect(func() -> void:
			visible = false
			replay_selected.emit(filepath)
		)
		replay_list.add_child(btn)
