class_name GCUndoCommand
extends GCBaseCommand
## /undo — Restore recent file changes made by AI tools


func _init():
	super._init("undo", "Undo recent file changes made by AI tools")


func execute(args: String, context: Dictionary) -> Dictionary:
	var undo_stack: GCUndoStack = context.get("undo_stack")
	if not undo_stack:
		return _result("Undo system not available")

	if args == "clear":
		undo_stack.clear()
		return _result("Undo stack cleared")

	if args == "list":
		var entries := undo_stack.list()
		if entries.is_empty():
			return _result("Nothing to undo")
		var lines: Array = []
		for i in range(entries.size() - 1, -1, -1):
			var e: Dictionary = entries[i]
			lines.append("%d. [%s] %s — %s" % [entries.size() - i, e.tool_name, e.file_path.get_file(), e.timestamp])
		return _result("Undo history (newest first):\n" + "\n".join(lines))

	if not undo_stack.can_undo():
		return _result("Nothing to undo")

	var entry := undo_stack.pop()
	if entry.has("error"):
		return _result("Undo failed: %s" % entry.error)

	return _result("Restored %s (was %s by %s)" % [entry.file_path.get_file(), entry.timestamp, entry.tool_name])
