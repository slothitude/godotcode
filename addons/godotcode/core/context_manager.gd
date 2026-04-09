class_name GCContextManager
extends RefCounted
## Gather project context for the system prompt


func build_system_prompt() -> String:
	var parts: Array = []

	# Project info
	var project_name := _get_project_name()
	if project_name != "":
		parts.append("Project: %s" % project_name)

	# Project.godot contents
	var project_godot := _read_project_godot()
	if project_godot != "":
		parts.append("## Project Settings\n```\n%s\n```" % project_godot.left(2000))

	# File tree listing
	var file_tree := _get_file_tree()
	if file_tree != "":
		parts.append("## Project Files\n%s" % file_tree)

	# CLAUDE.md contents
	var claude_md := _read_claude_md()
	if claude_md != "":
		parts.append("## Project Instructions (CLAUDE.md)\n%s" % claude_md)

	# Current scene info
	var scene_info := _get_current_scene_info()
	if scene_info != "":
		parts.append("## Current Scene\n%s" % scene_info)

	var prompt := "You are GodotCode, an AI assistant integrated into the Godot editor as a plugin. "
	prompt += "You help with GDScript, Godot scenes, shaders, and general programming tasks.\n\n"
	prompt += "You have direct access to the live editor via SceneTree, NodeProperty, Screenshot, ErrorMonitor, and PluginWriter tools. "
	prompt += "If you need a capability you don't have, write a GDScript EditorPlugin that provides it. "
	prompt += "Use PluginWriter to install it. You are not limited to your current toolset — you can extend yourself.\n\n"

	if not parts.is_empty():
		prompt += "## Project Context\n\n"
		prompt += "\n\n".join(parts)

	return prompt


func _get_project_name() -> String:
	if FileAccess.file_exists("res://project.godot"):
		var file := FileAccess.open("res://project.godot", FileAccess.READ)
		if file:
			var text := file.get_as_text()
			file.close()
			var regex := RegEx.new()
			regex.compile('config/name="([^"]*)"')
			var m := regex.search(text)
			if m:
				return m.get_string(1)
	return ""


func _read_project_godot() -> String:
	var path := "res://project.godot"
	if FileAccess.file_exists(path):
		var file := FileAccess.open(path, FileAccess.READ)
		if file:
			var text := file.get_as_text()
			file.close()
			return text.left(2000)
	return ""


func _get_file_tree() -> String:
	var files: Array = []
	_collect_files("res://", files, 3)  # 3 levels deep
	if files.is_empty():
		return ""

	# Limit output
	if files.size() > 100:
		files = files.slice(0, 100)
		files.append("... (%d more files)" % (files.size() - 100))

	return "\n".join(files)


func _collect_files(dir_path: String, results: Array, max_depth: int, current_depth: int = 0) -> void:
	if current_depth >= max_depth:
		return

	var da := DirAccess.open(dir_path)
	if not da:
		return

	var skip := [".git", ".godot", "node_modules", ".import", "__pycache__", ".vscode"]

	da.list_dir_begin()
	var file_name := da.get_next()
	while file_name != "":
		if file_name.begins_with("."):
			file_name = da.get_next()
			continue

		var full_path := dir_path + file_name
		if da.current_is_dir():
			if file_name not in skip:
				results.append(full_path + "/")
				_collect_files(full_path + "/", results, max_depth, current_depth + 1)
		else:
			results.append(full_path)

		file_name = da.get_next()
	da.list_dir_end()


func _read_claude_md() -> String:
	for path in ["res://CLAUDE.md", "res://claude.md", "res://.claude/CLAUDE.md"]:
		if FileAccess.file_exists(path):
			var file := FileAccess.open(path, FileAccess.READ)
			if file:
				var text := file.get_as_text()
				file.close()
				return text
	return ""


func _get_current_scene_info() -> String:
	if Engine.is_editor_hint():
		var edited_scene := EditorInterface.get_edited_scene_root()
		if edited_scene:
			var info := "Currently editing: %s" % edited_scene.scene_file_path
			info += "\nRoot node: %s [%s]" % [edited_scene.name, edited_scene.get_class()]
			var child_count := edited_scene.get_child_count()
			if child_count > 0:
				info += "\nTop-level children (%d):" % child_count
				for i in range(mini(child_count, 10)):
					var child: Node = edited_scene.get_child(i)
					info += "\n  - %s [%s]" % [child.name, child.get_class()]
				if child_count > 10:
					info += "\n  ... and %d more" % (child_count - 10)
			return info
	return ""
