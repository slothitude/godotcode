class_name GCSessionManager
extends RefCounted
## Save/resume conversations across editor restarts

const SESSIONS_DIR := "user://godotcode_sessions"
const INDEX_FILE := "user://godotcode_sessions/sessions_index.json"


func _init() -> void:
	_ensure_dir()


func _ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(SESSIONS_DIR):
		DirAccess.make_dir_recursive_absolute(SESSIONS_DIR)


func list_sessions() -> Array:
	## Return array of session metadata sorted by updated_at descending
	var index := _load_index()
	if index.is_empty():
		return []

	index.sort_custom(func(a, b): return a.get("updated_at", "") > b.get("updated_at", ""))
	return index


func create_session(name: String, conversation_history: GCConversationHistory) -> String:
	## Create a new named session, returns session id
	var id := _generate_id()
	var session_data := _serialize_conversation(conversation_history)
	session_data["id"] = id
	session_data["name"] = name if name != "" else "Session %s" % id.left(8)
	session_data["created_at"] = Time.get_datetime_string_from_system()
	session_data["updated_at"] = session_data["created_at"]
	session_data["message_count"] = conversation_history.get_messages().size()

	_save_session_file(id, session_data)
	_add_to_index(id, session_data)
	return id


func load_session(id: String) -> Dictionary:
	## Load session data by id. Returns empty dict if not found.
	var path := SESSIONS_DIR + "/session_" + id + ".json"
	if not FileAccess.file_exists(path):
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return {}

	var json_text := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(json_text) != OK:
		return {}

	var data: Dictionary = json.data
	data["id"] = id
	return data


func delete_session(id: String) -> bool:
	var path := SESSIONS_DIR + "/session_" + id + ".json"
	if not FileAccess.file_exists(path):
		return false

	var da := DirAccess.open(SESSIONS_DIR)
	if da:
		da.remove("session_" + id + ".json")
	_remove_from_index(id)
	return true


func rename_session(id: String, new_name: String) -> bool:
	var data := load_session(id)
	if data.is_empty():
		return false

	data["name"] = new_name
	data["updated_at"] = Time.get_datetime_string_from_system()
	_save_session_file(id, data)

	# Update index entry
	var index := _load_index()
	for entry in index:
		if entry.get("id", "") == id:
			entry["name"] = new_name
			entry["updated_at"] = data["updated_at"]
			break
	_save_index(index)
	return true


func auto_save(conversation_history: GCConversationHistory, current_session_id: String = "") -> String:
	## Auto-save the current conversation. Creates new session if needed.
	var id := current_session_id
	if id == "":
		id = create_session("Auto-save", conversation_history)
		return id

	# Update existing session
	var data := load_session(id)
	if data.is_empty():
		id = create_session("Auto-save", conversation_history)
		return id

	var session_data := _serialize_conversation(conversation_history)
	session_data["id"] = id
	session_data["name"] = data.get("name", "Session")
	session_data["created_at"] = data.get("created_at", "")
	session_data["updated_at"] = Time.get_datetime_string_from_system()
	session_data["message_count"] = conversation_history.get_messages().size()

	_save_session_file(id, session_data)
	_update_in_index(id, session_data)
	return id


func get_most_recent_session() -> Dictionary:
	var sessions := list_sessions()
	if sessions.is_empty():
		return {}
	return sessions[0]


func _serialize_conversation(history: GCConversationHistory) -> Dictionary:
	return {
		"messages": history.to_storage_array(),
		"system_prompt": history.get_system_prompt(),
	}


func _generate_id() -> String:
	return str(Time.get_ticks_msec()) + "_" + str(randi() % 10000)


func _save_session_file(id: String, data: Dictionary) -> void:
	_ensure_dir()
	var path := SESSIONS_DIR + "/session_" + id + ".json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()


func _load_index() -> Array:
	if not FileAccess.file_exists(INDEX_FILE):
		return []

	var file := FileAccess.open(INDEX_FILE, FileAccess.READ)
	if not file:
		return []

	var json_text := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(json_text) != OK:
		return []

	var data = json.data
	if data is Array:
		return data
	return []


func _save_index(index: Array) -> void:
	_ensure_dir()
	var file := FileAccess.open(INDEX_FILE, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(index, "\t"))
		file.close()


func _add_to_index(id: String, data: Dictionary) -> void:
	var index := _load_index()
	index.append({
		"id": id,
		"name": data.get("name", ""),
		"created_at": data.get("created_at", ""),
		"updated_at": data.get("updated_at", ""),
		"message_count": data.get("message_count", 0),
		"preview": _get_preview(data),
	})
	_save_index(index)


func _update_in_index(id: String, data: Dictionary) -> void:
	var index := _load_index()
	for entry in index:
		if entry.get("id", "") == id:
			entry["name"] = data.get("name", entry.get("name", ""))
			entry["updated_at"] = data.get("updated_at", "")
			entry["message_count"] = data.get("message_count", 0)
			entry["preview"] = _get_preview(data)
			break
	_save_index(index)


func _remove_from_index(id: String) -> void:
	var index := _load_index()
	var new_index: Array = []
	for entry in index:
		if entry.get("id", "") != id:
			new_index.append(entry)
	_save_index(new_index)


func _get_preview(data: Dictionary) -> String:
	var messages = data.get("messages", [])
	if messages is Array and messages.size() > 0:
		var first: Variant = messages[0]
		if first is Dictionary:
			var content = first.get("content", "")
			if content is String:
				return content.left(100)
	return ""
