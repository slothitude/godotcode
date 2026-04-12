class_name GCMemoryCommand
extends GCBaseCommand
## /memory — View or manage persistent memory via GCMemoryManager


func _init():
	super._init("memory", "View or manage persistent memory")


func execute(args: String, context: Dictionary) -> Dictionary:
	var memory_manager: GCMemoryManager = context.get("memory_manager")

	if args == "clear":
		if memory_manager:
			memory_manager.clear_all_memories()
		return _result("Memory cleared")

	# If no memory manager, fall back to direct file I/O
	if not memory_manager:
		return _legacy_execute(args)

	# List memories
	var memories := memory_manager.list_memories()
	if memories.is_empty():
		return _result("No memories stored. Use the Memory tool to save memories.")

	var result: Array = []
	for m in memories:
		var name: String = m.get("name", "")
		var relevant := memory_manager.get_relevant_memories(name, 1)
		var preview := ""
		if relevant.size() > 0:
			preview = (relevant[0].content as String).left(300)
		result.append("== %s ==\n%s\n" % [name, preview])

	return _result("\n".join(result))


func _legacy_execute(args: String) -> Dictionary:
	var memory_dir := "user://claude_memory"
	var result: Array = []
	var da := DirAccess.open(memory_dir)
	if not da:
		DirAccess.make_dir_recursive_absolute(memory_dir)
		return _result("Memory directory created. No memories yet.")

	da.list_dir_begin()
	var file_name := da.get_next()
	while file_name != "":
		if file_name.ends_with(".md"):
			var path := memory_dir + "/" + file_name
			var file := FileAccess.open(path, FileAccess.READ)
			if file:
				var content := file.get_as_text()
				file.close()
				result.append("== %s ==\n%s\n" % [file_name, content.left(500)])
		file_name = da.get_next()
	da.list_dir_end()

	if result.is_empty():
		return _result("No memories stored")
	return _result("\n".join(result))
