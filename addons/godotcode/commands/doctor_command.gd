class_name GCDoctorCommand
extends GCBaseCommand
## /doctor — Environment diagnostics


func _init() -> void:
	super._init("doctor", "Run environment diagnostics")


func execute(_args: String, _context: Dictionary) -> Dictionary:
	var info: Array = []

	info.append("== GodotCode Plugin Diagnostics ==")
	info.append("")

	# Godot version
	info.append("Godot Version: %s" % Engine.get_version_info().get("string", "unknown"))

	# Plugin version
	info.append("Plugin Version: 0.1.0")

	# OS
	info.append("OS: %s" % OS.get_name())

	# Project path
	info.append("Project Path: %s" % ProjectSettings.globalize_path("res://"))

	# Settings
	var settings: GCSettings = _context.get("settings")
	if settings:
		var api_key := settings.get_api_key()
		info.append("API Key: %s" % ("configured (%d chars)" % api_key.length() if api_key != "" else "NOT SET"))
		info.append("Model: %s" % settings.get_model())
		info.append("Base URL: %s" % settings.get_base_url())
		info.append("Permission Mode: %s" % settings.get_permission_mode())
	else:
		info.append("Settings: NOT INITIALIZED")

	# Git
	var git_array: PackedStringArray = []
	OS.execute("git", ["--version"], git_array)
	var git_ver := git_array[0].strip_edges() if git_array.size() > 0 else "not found"
	info.append("Git: %s" % git_ver)

	# File system access
	var res_dir := DirAccess.open("res://")
	info.append("res:// access: %s" % ("OK" if res_dir else "FAILED"))

	# Conversation
	var history: GCConversationHistory = _context.get("conversation_history")
	if history:
		info.append("Messages in history: %d" % history.get_messages().size())
	else:
		info.append("Conversation: NOT INITIALIZED")

	return _result("\n".join(info))
