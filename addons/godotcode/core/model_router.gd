class_name GCModelRouter
extends RefCounted
## Route different operations to different models for cost/quality optimization

const CONFIG_FILE := "user://godotcode_model_routing.json"

var _rules: Array = []
var _default_overrides: Dictionary = {}


func _init() -> void:
	load_config()
	_init_built_in_defaults()


func _init_built_in_defaults() -> void:
	## Built-in routing defaults (can be overridden by user config)
	if _rules.is_empty():
		_rules = [
			# Fast/cheap tools → could use smaller model
			{
				"pattern": {"tool_names": ["Read", "Glob", "Grep"]},
				"model": "",  # empty = use default
				"provider": "",
				"max_tokens": 4096
			},
			# Write/Edit tools → use powerful model
			{
				"pattern": {"tool_names": ["Write", "Edit", "Shader", "PluginWriter"]},
				"model": "",  # use default (most capable)
				"provider": "",
				"max_tokens": 0  # 0 = use default
			},
		]


func resolve_model(tool_name: String, input: Dictionary, context: Dictionary) -> Dictionary:
	## Return {model, provider, max_tokens} overrides for a given tool execution
	# Check user rules first (appended at end), then built-in defaults
	# Iterate in reverse so later (user-added) rules take priority
	for i in range(_rules.size() - 1, -1, -1):
		var rule: Dictionary = _rules[i]
		if _matches_rule(rule, tool_name, input, context):
			var overrides := {}
			if rule.get("model", "") != "":
				overrides["model"] = rule.model
			if rule.get("provider", "") != "":
				overrides["provider"] = rule.provider
			if rule.get("max_tokens", 0) > 0:
				overrides["max_tokens"] = rule.max_tokens
			if not overrides.is_empty():
				return overrides

	return {}  # No override — use defaults


func load_config() -> void:
	if not FileAccess.file_exists(CONFIG_FILE):
		return

	var file := FileAccess.open(CONFIG_FILE, FileAccess.READ)
	if not file:
		return

	var json_text := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(json_text) != OK:
		return

	var data = json.data
	if data is Dictionary:
		var rules = data.get("rules", [])
		if rules is Array:
			_rules = rules
		var defaults = data.get("defaults", {})
		if defaults is Dictionary:
			_default_overrides = defaults
	elif data is Array:
		_rules = data


func save_config() -> void:
	var config := {
		"rules": _rules,
		"defaults": _default_overrides
	}
	var file := FileAccess.open(CONFIG_FILE, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(config, "\t"))
		file.close()


func add_rule(rule: Dictionary) -> void:
	_rules.append(rule)
	save_config()


func remove_rule(index: int) -> void:
	if index >= 0 and index < _rules.size():
		_rules.remove_at(index)
		save_config()


func get_rules() -> Array:
	return _rules.duplicate()


func _matches_rule(rule: Dictionary, tool_name: String, input: Dictionary, context: Dictionary) -> bool:
	var pattern: Dictionary = rule.get("pattern", {})

	# Check tool_name match
	if pattern.has("tool_names"):
		var tool_names: Array = pattern.tool_names
		if tool_name not in tool_names:
			return false

	# Check input size
	if pattern.has("min_input_size"):
		var input_size := JSON.stringify(input).length()
		if input_size < int(pattern.min_input_size):
			return false

	# Check conversation length
	if pattern.has("min_conversation_length"):
		var history: GCConversationHistory = context.get("conversation_history")
		if history:
			var msg_count := history.get_messages().size()
			if msg_count < int(pattern.min_conversation_length):
				return false

	return true
