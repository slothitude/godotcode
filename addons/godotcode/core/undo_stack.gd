class_name GCUndoStack
extends RefCounted
## Safety net for AI file operations — stores original content before writes/edits

const MAX_DEPTH := 100

var _stack: Array = []  # {file_path, original_content, timestamp, tool_name}


func push(file_path: String, tool_name: String) -> bool:
	## Read current file content and push to stack. Returns false if file doesn't exist.
	if not FileAccess.file_exists(file_path):
		return false

	var file := FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return false

	var content := file.get_as_text()
	file.close()

	_stack.append({
		"file_path": file_path,
		"original_content": content,
		"timestamp": Time.get_datetime_string_from_system(),
		"tool_name": tool_name,
	})

	# Trim to max depth
	while _stack.size() > MAX_DEPTH:
		_stack.pop_front()

	return true


func pop() -> Dictionary:
	## Restore most recent file change and return the entry. Empty dict if nothing to undo.
	if _stack.is_empty():
		return {}

	var entry: Dictionary = _stack.pop_back()
	var file_path: String = entry.file_path
	var original: String = entry.original_content

	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if not file:
		return {"error": "Cannot open file for restore: %s" % file_path}

	file.store_string(original)
	file.close()
	return entry


func peek() -> Dictionary:
	## Return the most recent entry without restoring. Empty dict if stack is empty.
	if _stack.is_empty():
		return {}
	return _stack.back()


func list() -> Array:
	## Return copy of the full stack (newest last)
	return _stack.duplicate()


func clear() -> void:
	_stack.clear()


func can_undo() -> bool:
	return not _stack.is_empty()


func size() -> int:
	return _stack.size()
