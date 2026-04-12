class_name GCMemoryManager
extends RefCounted
## Persistent learning across sessions — auto-inject memory into system prompt

const MEMORY_DIR := "user://claude_memory"


func build_memory_section() -> String:
	## Read all .md memory files and return formatted section for system prompt
	var memories := _read_all_memories()
	if memories.is_empty():
		return ""

	var parts: Array = []
	for mem in memories:
		parts.append("### %s\n%s" % [mem.name, mem.content])

	return "## Persistent Memory\n\n%s" % "\n\n".join(parts)


func add_memory(key: String, content: String) -> bool:
	## Write a new memory file. Key is sanitized to a safe filename.
	var file_name := _sanitize_key(key)
	if file_name == "":
		return false

	var dir := MEMORY_DIR
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)

	var path := dir + "/" + file_name + ".md"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return false

	file.store_string(content)
	file.close()
	return true


func get_relevant_memories(query: String, max_items: int = 5) -> Array:
	## Keyword matching against filenames + first-line summaries
	var results: Array = []
	var memories := _read_all_memories()
	var lower_query := query.to_lower()
	var keywords := lower_query.split(" ", false)

	for mem in memories:
		var score := 0
		var searchable: String = (str(mem.name) + " " + str(mem.content).left(200)).to_lower()
		for kw in keywords:
			if kw.length() < 2:
				continue
			if searchable.find(kw) != -1:
				score += 1
		if score > 0:
			results.append({"name": mem.name, "content": mem.content, "score": score})

	# Sort by score descending
	results.sort_custom(func(a, b): return a.score > b.score)

	if results.size() > max_items:
		results = results.slice(0, max_items)

	return results


func list_memories() -> Array:
	## Return array of {name, file_path}
	var results: Array = []
	if not DirAccess.dir_exists_absolute(MEMORY_DIR):
		return results

	var da := DirAccess.open(MEMORY_DIR)
	if not da:
		return results

	da.list_dir_begin()
	var file_name := da.get_next()
	while file_name != "":
		if file_name.ends_with(".md"):
			results.append({
				"name": file_name.get_basename(),
				"file_path": MEMORY_DIR + "/" + file_name,
			})
		file_name = da.get_next()
	da.list_dir_end()
	return results


func delete_memory(name: String) -> bool:
	var file_name := _sanitize_key(name)
	var path := MEMORY_DIR + "/" + file_name + ".md"
	if FileAccess.file_exists(path):
		var da := DirAccess.open(MEMORY_DIR)
		if da:
			da.remove(file_name + ".md")
			return true
	return false


func clear_all_memories() -> void:
	var da := DirAccess.open(MEMORY_DIR)
	if not da:
		return
	da.list_dir_begin()
	var f := da.get_next()
	while f != "":
		if f.ends_with(".md"):
			da.remove(f)
		f = da.get_next()
	da.list_dir_end()


func _read_all_memories() -> Array:
	var results: Array = []
	if not DirAccess.dir_exists_absolute(MEMORY_DIR):
		return results

	var da := DirAccess.open(MEMORY_DIR)
	if not da:
		return results

	da.list_dir_begin()
	var file_name := da.get_next()
	while file_name != "":
		if file_name.ends_with(".md"):
			var path := MEMORY_DIR + "/" + file_name
			var file := FileAccess.open(path, FileAccess.READ)
			if file:
				results.append({
					"name": file_name.get_basename(),
					"content": file.get_as_text(),
				})
				file.close()
		file_name = da.get_next()
	da.list_dir_end()
	return results


func _sanitize_key(key: String) -> String:
	var result := key.to_lower().strip_edges()
	result = result.replace(" ", "_")
	# Only keep alphanumeric, underscores, hyphens
	var cleaned := ""
	for c in result:
		if c == "_" or c == "-" or (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			cleaned += c
	return cleaned
