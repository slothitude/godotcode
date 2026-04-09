class_name GCPluginWriterTool
extends GCBaseTool
## Write and install GDScript EditorPlugin extensions at runtime


func _init() -> void:
	super._init(
		"PluginWriter",
		"Create and install Godot editor plugins from GDScript code. The plugin is written to disk and enabled in the project.",
		{
			"plugin_name": {
				"type": "string",
				"description": "Plugin name (alphanumeric + underscore, will be prefixed 'godotcode_')"
			},
			"plugin_cfg": {
				"type": "string",
				"description": "Full content of the plugin.cfg file"
			},
			"gdscript_code": {
				"type": "string",
				"description": "GDScript code (must contain 'extends EditorPlugin')"
			},
			"additional_files": {
				"type": "object",
				"description": "Optional dict of {relative_path: file_content} for extra files"
			}
		}
	)
	is_read_only = false


func validate_input(input: Dictionary) -> Dictionary:
	if not input.has("plugin_name"):
		return {"valid": false, "error": "plugin_name is required"}
	if not input.has("plugin_cfg"):
		return {"valid": false, "error": "plugin_cfg (plugin.cfg content) is required"}
	if not input.has("gdscript_code"):
		return {"valid": false, "error": "gdscript_code is required"}

	var name: String = input.get("plugin_name", "")
	if name == "":
		return {"valid": false, "error": "plugin_name cannot be empty"}

	# Sanitize name
	var sanitized := _sanitize_name(name)
	if sanitized != name:
		return {"valid": false, "error": "plugin_name must be alphanumeric + underscore only (suggested: '%s')" % sanitized}

	var code: String = input.get("gdscript_code", "")
	if not "extends EditorPlugin" in code:
		return {"valid": false, "error": "gdscript_code must contain 'extends EditorPlugin'"}

	return {"valid": true}


func execute(input: Dictionary, context: Dictionary) -> Dictionary:
	var raw_name: String = input.get("plugin_name", "")
	var plugin_name := _sanitize_name(raw_name)
	var dir_name := "godotcode_" + plugin_name
	var base_path := "res://addons/" + dir_name + "/"

	# Create directory
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(base_path)):
		var err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(base_path))
		if err != OK:
			return {"success": false, "error": "Failed to create directory: %s (error %d)" % [base_path, err]}

	var files_written: Array = []

	# Write plugin.cfg
	var cfg_content: String = input.get("plugin_cfg", "")
	if _write_file(base_path + "plugin.cfg", cfg_content):
		files_written.append("plugin.cfg")
	else:
		return {"success": false, "error": "Failed to write plugin.cfg"}

	# Write main script
	var script_content: String = input.get("gdscript_code", "")
	var script_name := plugin_name + "_plugin.gd"
	if _write_file(base_path + script_name, script_content):
		files_written.append(script_name)
	else:
		return {"success": false, "error": "Failed to write %s" % script_name}

	# Write additional files
	var additional: Dictionary = input.get("additional_files", {})
	for rel_path in additional:
		var full_path: String = base_path + rel_path
		# Security: ensure no path traversal
		if ".." in rel_path or rel_path.begins_with("/"):
			continue
		if _write_file(full_path, str(additional[rel_path])):
			files_written.append(rel_path)

	# Scan filesystem so Godot sees the new files
	EditorInterface.get_resource_filesystem().scan()

	# Enable the plugin
	_enable_plugin(dir_name, base_path + script_name)

	return {"success": true, "data": "Plugin '%s' installed. Files: %s\nThe plugin has been enabled. A full editor restart may be needed for complete activation." % [dir_name, ", ".join(files_written)]}


func _sanitize_name(name: String) -> String:
	var result := ""
	for c in name:
		if c.is_valid_identifier() or c == "_":
			result += c
		elif c == " ":
			result += "_"
		else:
			result += "_"
	# Ensure it doesn't start with a digit
	if result.length() > 0 and result[0].is_valid_int():
		result = "_" + result
	return result


func _write_file(path: String, content: String) -> bool:
	# Ensure parent directory exists
	var dir := path.get_base_dir()
	var global_dir := ProjectSettings.globalize_path(dir)
	if not DirAccess.dir_exists_absolute(global_dir):
		DirAccess.make_dir_recursive_absolute(global_dir)

	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return false
	file.store_string(content)
	file.close()
	return true


func _enable_plugin(dir_name: String, script_path: String) -> void:
	# Update project settings to enable the plugin
	var enabled_setting := "editor_plugins/enabled"
	var enabled

	if ProjectSettings.has_setting(enabled_setting):
		enabled = ProjectSettings.get_setting(enabled_setting)
	else:
		enabled = PackedStringArray()

	# Handle both PackedStringArray and Array
	var enabled_list: Array = []
	if enabled is PackedStringArray:
		for item in enabled:
			enabled_list.append(item)
	elif enabled is Array:
		enabled_list = enabled

	# Add if not already present
	if dir_name not in enabled_list:
		enabled_list.append(dir_name)
		var new_packed := PackedStringArray()
		for item in enabled_list:
			new_packed.append(item)
		ProjectSettings.set_setting(enabled_setting, new_packed)
		ProjectSettings.save()

	# Attempt immediate load
	var script: Resource = load(script_path)
	if script:
		var instance: RefCounted = script.new()
		if instance:
			instance._enter_tree()
