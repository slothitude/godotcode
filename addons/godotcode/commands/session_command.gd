class_name GCSessionCommand
extends GCBaseCommand
## /session — Manage conversation sessions across editor restarts


func _init():
	super._init("session", "Manage conversation sessions: list, save, load, delete, new")


func execute(args: String, context: Dictionary) -> Dictionary:
	var session_manager: GCSessionManager = context.get("session_manager")
	var conversation_history: GCConversationHistory = context.get("conversation_history")
	if not session_manager or not conversation_history:
		return _result("Session system not available")

	var parts := args.split(" ", false, 2)
	var sub_cmd := parts[0] if parts.size() > 0 else ""

	match sub_cmd:
		"", "list":
			return _list_sessions(session_manager)
		"save":
			var name := parts[1] if parts.size() > 1 else "Manual save"
			var id := session_manager.create_session(name, conversation_history)
			return _result("Session saved: %s (id: %s)" % [name, id.left(8)])
		"load":
			if parts.size() < 2:
				return _result("Usage: /session load <id>")
			return _load_session(parts[1], session_manager, conversation_history)
		"delete":
			if parts.size() < 2:
				return _result("Usage: /session delete <id>")
			var id := _resolve_id(parts[1], session_manager)
			if id == "":
				return _result("Session not found")
			if session_manager.delete_session(id):
				return _result("Session deleted")
			return _result("Failed to delete session")
		"new":
			conversation_history.clear()
			return _result("Started new conversation")
		_:
			return _result("Usage: /session [list|save [name]|load <id>|delete <id>|new]")


func _list_sessions(sm: GCSessionManager) -> Dictionary:
	var sessions := sm.list_sessions()
	if sessions.is_empty():
		return _result("No saved sessions")

	var lines: Array = []
	for s in sessions:
		var id_short: String = str(s.get("id", "")).left(8)
		var name: String = s.get("name", "Unnamed")
		var count: int = s.get("message_count", 0)
		var updated: String = s.get("updated_at", "")
		lines.append("%s  %s  (%d msgs)  %s" % [id_short, name, count, updated])

	return _result("Sessions:\n" + "\n".join(lines))


func _load_session(id_fragment: String, sm: GCSessionManager, history: GCConversationHistory) -> Dictionary:
	var id := _resolve_id(id_fragment, sm)
	if id == "":
		return _result("Session not found (use /session list to see ids)")

	var data := sm.load_session(id)
	if data.is_empty():
		return _result("Failed to load session")

	var messages = data.get("messages", [])
	if messages is Array:
		history.from_storage_array(messages)
		var sp: String = data.get("system_prompt", "")
		if sp != "":
			history.set_system_prompt(sp)
		return _result("Loaded session: %s (%d messages)" % [data.get("name", ""), messages.size()])

	return _result("Failed to parse session data")


func _resolve_id(fragment: String, sm: GCSessionManager) -> String:
	## Match a fragment to a full session id
	var sessions := sm.list_sessions()
	for s in sessions:
		var id: String = str(s.get("id", ""))
		if id.begins_with(fragment) or id.left(8) == fragment:
			return id
	return ""
