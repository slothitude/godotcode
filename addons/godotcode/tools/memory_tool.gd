class_name GCMemoryTool
extends GCBaseTool
## AI-facing tool for saving, recalling, listing, and deleting persistent memories


var _memory_manager: GCMemoryManager


func _init() -> void:
	super._init(
		"Memory",
		"Save, recall, list, or delete persistent memories that carry across sessions. Memories are injected into the system prompt automatically.",
		{
			"action": {
				"type": "string",
				"description": "Action: save, recall, list, delete",
				"enum": ["save", "recall", "list", "delete"]
			},
			"key": {
				"type": "string",
				"description": "Memory key/name (for save, recall, delete)"
			},
			"content": {
				"type": "string",
				"description": "Memory content (for save action)"
			},
			"query": {
				"type": "string",
				"description": "Search query (for recall action)"
			}
		}
	)
	is_read_only = true


func validate_input(input: Dictionary) -> Dictionary:
	var action: String = input.get("action", "")
	if action == "":
		return {"valid": false, "error": "action is required (save, recall, list, delete)"}
	if action == "save" and not input.has("content"):
		return {"valid": false, "error": "content is required for save action"}
	if action == "save" and not input.has("key"):
		return {"valid": false, "error": "key is required for save action"}
	return {"valid": true}


func execute(input: Dictionary, context: Dictionary) -> Dictionary:
	if not _memory_manager:
		_memory_manager = context.get("memory_manager")
	if not _memory_manager:
		return {"success": false, "error": "Memory manager not available"}

	var action: String = input.get("action", "")

	match action:
		"save":
			var key: String = input.get("key", "")
			var content: String = input.get("content", "")
			if _memory_manager.add_memory(key, content):
				return {"success": true, "data": "Memory saved: %s" % key}
			return {"success": false, "error": "Failed to save memory"}

		"recall":
			var query: String = input.get("query", input.get("key", ""))
			var results := _memory_manager.get_relevant_memories(query)
			if results.is_empty():
				return {"success": true, "data": "No matching memories found"}
			var lines: Array = []
			for r in results:
				lines.append("== %s (score: %d) ==\n%s" % [r.name, r.score, (r.content as String).left(500)])
			return {"success": true, "data": "\n\n".join(lines)}

		"list":
			var memories := _memory_manager.list_memories()
			if memories.is_empty():
				return {"success": true, "data": "No memories stored"}
			var lines: Array = []
			for m in memories:
				lines.append("- %s" % m.name)
			return {"success": true, "data": "Memories:\n" + "\n".join(lines)}

		"delete":
			var key: String = input.get("key", "")
			if _memory_manager.delete_memory(key):
				return {"success": true, "data": "Memory deleted: %s" % key}
			return {"success": false, "error": "Memory not found: %s" % key}

		_:
			return {"success": false, "error": "Unknown action: %s" % action}
