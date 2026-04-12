class_name GCHooksManager
extends RefCounted
## User-configurable pre/post execution hooks

const HOOKS_FILE := "user://godotcode_hooks.json"

var _hooks: Array = []  # Array of hook definitions


func _init() -> void:
	load_hooks()


func load_hooks() -> void:
	_hooks.clear()
	if not FileAccess.file_exists(HOOKS_FILE):
		return

	var file := FileAccess.open(HOOKS_FILE, FileAccess.READ)
	if not file:
		return

	var json_text := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(json_text) != OK:
		return

	var data = json.data
	if data is Array:
		_hooks = data


func save_hooks() -> void:
	var file := FileAccess.open(HOOKS_FILE, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(_hooks, "\t"))
		file.close()


func fire(event: String, context: Dictionary) -> Dictionary:
	## Fire hooks for an event. Returns {proceed: bool, message: string}
	var proceed := true
	var messages: Array = []

	for hook in _hooks:
		if not hook is Dictionary:
			continue

		var hook_event: String = hook.get("event", "")
		if hook_event != event:
			continue

		# Check conditions
		if not _matches_conditions(hook, context):
			continue

		# Execute action
		var action: String = hook.get("action", "")
		match action:
			"block":
				proceed = false
				messages.append(hook.get("message", "Blocked by hook"))
			"log":
				var msg: String = hook.get("message", "Hook fired: %s" % event)
				messages.append(msg)
				print("[GodotCode Hook] %s" % msg)
			"notify":
				messages.append(hook.get("message", "Hook notification"))
			"shell_command":
				var cmd: String = hook.get("command", "")
				if cmd != "":
					_execute_shell_hook(cmd, context)

	return {"proceed": proceed, "messages": messages}


func add_hook(hook: Dictionary) -> void:
	_hooks.append(hook)
	save_hooks()


func remove_hook(index: int) -> void:
	if index >= 0 and index < _hooks.size():
		_hooks.remove_at(index)
		save_hooks()


func get_hooks() -> Array:
	return _hooks.duplicate()


func _matches_conditions(hook: Dictionary, context: Dictionary) -> bool:
	var conditions: Dictionary = hook.get("condition", {})

	# Check tool_name condition
	if conditions.has("tool_name"):
		var tool_name: String = context.get("tool_name", "")
		var pattern: String = conditions.tool_name
		if pattern != "*" and tool_name != pattern:
			return false

	# Check file_pattern condition
	if conditions.has("file_pattern"):
		var file_path: String = context.get("file_path", "")
		if file_path.find(conditions.file_pattern) == -1:
			return false

	return true


func _execute_shell_hook(command: String, context: Dictionary) -> void:
	# Substitute context variables
	var cmd := command
	cmd = cmd.replace("{tool_name}", str(context.get("tool_name", "")))
	cmd = cmd.replace("{file_path}", str(context.get("file_path", "")))
	cmd = cmd.replace("{project_path}", str(context.get("project_path", "")))

	# Execute in thread to avoid blocking
	var thread := Thread.new()
	thread.start(func():
		OS.execute("bash", ["-c", cmd], [], true)
		thread.call_deferred("wait_to_finish")
	)
