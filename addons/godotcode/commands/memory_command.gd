class_name GCMemoryCommand
extends GCBaseCommand
## /memory — View persistent memory


func _init():
	super._init("memory", "View or manage persistent memory")


func execute(args: String, context: Dictionary) -> Dictionary:
	var memory_dir := "user://claude_memory"

	if args == "clear":
		var da := DirAccess.open(memory_dir)
		if da:
			da.list_dir_begin()
			var f := da.get_next()
			while f != "":
				da.remove(f)
				f = da.get_next()
			da.list_dir_end()
		return _result("Memory cleared")

	# Read and display memory files
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
