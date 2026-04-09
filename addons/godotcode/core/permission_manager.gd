class_name GCPermissionManager
extends RefCounted
## Permission prompt system with modes and rules

var _settings: GCSettings

# Rules: tool_name -> "allow" | "ask" | "deny"
var _rules: Dictionary = {
	"Read": "allow",
	"Glob": "allow",
	"Grep": "allow",
	"Write": "ask",
	"Edit": "ask",
	"Bash": "ask",
	"WebSearch": "allow",
	"WebFetch": "allow",
	"Agent": "allow",
	"TaskManage": "allow",
	"Schedule": "allow",
	"Sleep": "allow",
	"EnterPlanMode": "allow",
	"SceneTree": "ask",
	"NodeProperty": "ask",
	"Screenshot": "allow",
	"ErrorMonitor": "allow",
	"PluginWriter": "ask",
}


func get_current_mode() -> String:
	if _settings:
		return _settings.get_permission_mode()
	return "default"


func check_tool_permission(tool_name: String, tool_input: Dictionary, context: Dictionary) -> Dictionary:
	var mode := get_current_mode()

	# Bypass mode: allow everything
	if mode == "bypass":
		return {"behavior": "allow"}

	# Check rules
	var rule: String = _rules.get(tool_name, "ask")

	# Plan mode: only allow read-only tools
	if mode == "plan":
		var read_only_tools := ["Read", "Glob", "Grep", "WebSearch", "WebFetch", "Screenshot", "ErrorMonitor"]
		if tool_name in read_only_tools:
			return {"behavior": "allow"}
		return {"behavior": "deny", "message": "Plan mode: only read-only tools allowed"}

	match rule:
		"allow":
			return {"behavior": "allow"}
		"deny":
			return {"behavior": "deny", "message": "Tool '%s' is blocked by permission rules" % tool_name}
		_:
			return {"behavior": "ask", "message": "Tool '%s' requires your approval" % tool_name}


func set_rule(tool_name: String, behavior: String) -> void:
	_rules[tool_name] = behavior


func get_rules() -> Dictionary:
	return _rules.duplicate()
