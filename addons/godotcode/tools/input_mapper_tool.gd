class_name GCInputMapperTool
extends GCBaseTool
## Configure input actions in project.godot


func _init() -> void:
	super._init(
		"InputMapper",
		"Configure input actions in project.godot. Actions: add_action, remove_action, list_actions, add_binding, set_preset.",
		{
			"action": {
				"type": "string",
				"description": "Action: add_action, remove_action, list_actions, add_binding, set_preset",
				"enum": ["add_action", "remove_action", "list_actions", "add_binding", "set_preset"]
			},
			"input_action": {
				"type": "string",
				"description": "Name of the input action (e.g. 'jump', 'move_left')"
			},
			"key": {
				"type": "string",
				"description": "Key name (e.g. 'KEY_SPACE', 'KEY_A', 'KEY_UP'). Use Godot Key constants."
			},
			"keycode": {
				"type": "integer",
				"description": "Raw keycode integer (alternative to key name)"
			},
			"mouse_button": {
				"type": "integer",
				"description": "Mouse button index (1=left, 2=right, 3=middle, 4=wheel_up, 5=wheel_down)"
			},
			"joy_button": {
				"type": "integer",
				"description": "Joypad button index (0-16)"
			},
			"joy_axis": {
				"type": "object",
				"description": "Joypad axis: {axis: 0-7, positive: true/false}"
			},
			"deadzone": {
				"type": "number",
				"description": "Input action deadzone (0.0 to 1.0, default 0.5)"
			},
			"preset": {
				"type": "string",
				"description": "Preset name: wasd, arrows, fps, platformer, rpg, fighting, racing, twin_stick",
				"enum": ["wasd", "arrows", "fps", "platformer", "rpg", "fighting", "racing", "twin_stick"]
			}
		}
	)
	is_read_only = false


func validate_input(input: Dictionary) -> Dictionary:
	var action: String = input.get("action", "")
	if action == "":
		return {"valid": false, "error": "action is required"}
	match action:
		"add_action", "remove_action", "add_binding":
			if input.get("input_action", "") == "":
				return {"valid": false, "error": "input_action is required for %s" % action}
		"set_preset":
			if input.get("preset", "") == "":
				return {"valid": false, "error": "preset is required for set_preset"}
	return {"valid": true}


func check_permissions(input: Dictionary, context: Dictionary) -> Dictionary:
	var action: String = input.get("action", "")
	if action == "list_actions":
		return {"behavior": "allow"}
	return {"behavior": "ask", "message": "Input Mapper: %s" % action}


func execute(input: Dictionary, context: Dictionary) -> Dictionary:
	var action: String = input.get("action", "")
	var project_path: String = context.get("project_path", "")

	match action:
		"list_actions":
			return _list_actions(project_path)
		"add_action":
			return _add_action(input, project_path)
		"remove_action":
			return _remove_action(input, project_path)
		"add_binding":
			return _add_binding(input, project_path)
		"set_preset":
			return _set_preset(input, project_path)
		_:
			return {"success": false, "error": "Unknown action: %s" % action}


func _load_project_config(project_path: String) -> ConfigFile:
	var config := ConfigFile.new()
	var path: String = project_path + "/project.godot"
	if FileAccess.file_exists(path):
		config.load(path)
	return config


func _save_project_config(config: ConfigFile, project_path: String) -> bool:
	return config.save(project_path + "/project.godot") == OK


func _list_actions(project_path: String) -> Dictionary:
	var config := _load_project_config(project_path)
	var actions: Array = []
	if not config.has_section("input"):
		return {"success": true, "data": "No input actions configured."}
	var input_keys := config.get_section_keys("input")
	for key in input_keys:
		var value = config.get_value("input", key)
		var events_desc: String = ""
		if value is Array:
			for entry in value:
				if entry is Dictionary:
					var evts: Array = entry.get("events", [])
					for evt in evts:
						if evt is Dictionary:
							var ev: Dictionary = evt.get("event", {})
							if ev.has("keycode"):
								events_desc += "Key(%d) " % ev.keycode
							elif ev.has("button_index"):
								events_desc += "Mouse(%d) " % ev.button_index
							elif ev.has("button_mask"):
								events_desc += "MBtn "
		actions.append({"name": key, "bindings": events_desc.strip_edges()})

	if actions.is_empty():
		return {"success": true, "data": "No input actions configured."}

	var lines: Array = []
	for a in actions:
		var binding_info: String = a.bindings if a.bindings != "" else "no bindings"
		lines.append("  %s: %s" % [a.name, binding_info])
	return {"success": true, "data": "Input actions:\n" + "\n".join(lines), "actions": actions}


func _add_action(input: Dictionary, project_path: String) -> Dictionary:
	var action_name: String = input.get("input_action", "")
	var deadzone: float = input.get("deadzone", 0.5)
	var config := _load_project_config(project_path)

	var events: Array = []
	# Add initial binding if provided
	var binding := _build_event(input)
	if not binding.is_empty():
		events.append(binding)

	var action_data := [{"deadzone": deadzone, "events": events}]
	config.set_value("input", action_name, action_data)

	if not _save_project_config(config, project_path):
		return {"success": false, "error": "Failed to save project.godot"}

	return {"success": true, "data": "Added input action '%s' (deadzone: %.1f, bindings: %d)" % [action_name, deadzone, events.size()]}


func _remove_action(input: Dictionary, project_path: String) -> Dictionary:
	var action_name: String = input.get("input_action", "")
	var config := _load_project_config(project_path)

	if not config.has_section_key("input", action_name):
		return {"success": false, "error": "Action '%s' not found" % action_name}

	config.set_value("input", action_name, null)

	if not _save_project_config(config, project_path):
		return {"success": false, "error": "Failed to save project.godot"}

	return {"success": true, "data": "Removed input action '%s'" % action_name}


func _add_binding(input: Dictionary, project_path: String) -> Dictionary:
	var action_name: String = input.get("input_action", "")
	var config := _load_project_config(project_path)

	if not config.has_section_key("input", action_name):
		return {"success": false, "error": "Action '%s' not found. Use add_action first." % action_name}

	var action_data: Array = config.get_value("input", action_name)
	if action_data.is_empty() or not action_data[0] is Dictionary:
		return {"success": false, "error": "Invalid action data for '%s'" % action_name}

	var binding := _build_event(input)
	if binding.is_empty():
		return {"success": false, "error": "No binding specified. Provide key, keycode, mouse_button, joy_button, or joy_axis."}

	# Add to existing events
	var entry: Dictionary = action_data[0]
	var events: Array = entry.get("events", [])
	events.append(binding)
	entry["events"] = events
	action_data[0] = entry

	config.set_value("input", action_name, action_data)

	if not _save_project_config(config, project_path):
		return {"success": false, "error": "Failed to save project.godot"}

	return {"success": true, "data": "Added binding to '%s'" % action_name}


func _build_event(input: Dictionary) -> Dictionary:
	var keycode: int = input.get("keycode", 0)
	var key_name: String = input.get("key", "")

	if keycode == 0 and key_name != "":
		keycode = _key_name_to_code(key_name)

	if keycode != 0:
		return {
			"event": {
				"alt_pressed": false,
				"ctrl_pressed": false,
				"keycode": keycode,
				"physical_keycode": 0,
				"meta_pressed": false,
				"shift_pressed": false,
				"unicode": 0
			},
			"read_only": false
		}

	var mouse_btn: int = input.get("mouse_button", 0)
	if mouse_btn != 0:
		return {
			"event": {
				"button_mask": 1 << (mouse_btn - 1),
				"double_click": false,
				"factor": 1.0,
				"button_index": mouse_btn,
				"pressed": true,
				"ctrl_pressed": false,
				"shift_pressed": false,
				"meta_pressed": false,
				"alt_pressed": false
			},
			"read_only": false
		}

	var joy_btn: int = input.get("joy_button", -1)
	if joy_btn >= 0:
		return {
			"event": {
				"button_index": joy_btn,
				"pressure": 0.0,
				"pressed": true
			},
			"read_only": false
		}

	var joy_axis_data: Dictionary = input.get("joy_axis", {})
	if not joy_axis_data.is_empty():
		var axis: int = int(joy_axis_data.get("axis", 0))
		var positive: bool = joy_axis_data.get("positive", true)
		return {
			"event": {
				"axis": axis,
				"axis_value": 1.0 if positive else -1.0
			},
			"read_only": false
		}

	return {}


func _key_name_to_code(name: String) -> int:
	var key_map := {
		"KEY_SPACE": 32, "KEY_A": 4194305, "KEY_B": 4194306, "KEY_C": 4194307,
		"KEY_D": 4194308, "KEY_E": 4194309, "KEY_F": 4194310, "KEY_G": 4194311,
		"KEY_H": 4194312, "KEY_I": 4194313, "KEY_J": 4194314, "KEY_K": 4194315,
		"KEY_L": 4194316, "KEY_M": 4194317, "KEY_N": 4194318, "KEY_O": 4194319,
		"KEY_P": 4194320, "KEY_Q": 4194321, "KEY_R": 4194322, "KEY_S": 4194323,
		"KEY_T": 4194324, "KEY_U": 4194325, "KEY_V": 4194326, "KEY_W": 4194327,
		"KEY_X": 4194328, "KEY_Y": 4194329, "KEY_Z": 4194330,
		"KEY_UP": 4194320, "KEY_DOWN": 4194321, "KEY_LEFT": 4194322, "KEY_RIGHT": 4194323,
		"KEY_ENTER": 4194309, "KEY_ESCAPE": 4194305, "KEY_TAB": 4194306,
		"KEY_SHIFT": 4194325, "KEY_CTRL": 4194326, "KEY_ALT": 4194327,
		"KEY_0": 48, "KEY_1": 49, "KEY_2": 50, "KEY_3": 51, "KEY_4": 52,
		"KEY_5": 53, "KEY_6": 54, "KEY_7": 55, "KEY_8": 56, "KEY_9": 57,
	}
	# Normalize: strip KEY_ prefix and look up
	var normalized := name.to_upper()
	if not normalized.begins_with("KEY_"):
		normalized = "KEY_" + normalized
	return key_map.get(normalized, 0)


func _set_preset(input: Dictionary, project_path: String) -> Dictionary:
	var preset_name: String = input.get("preset", "")
	var config := _load_project_config(project_path)
	var deadzone: float = input.get("deadzone", 0.5)

	var presets := {
		"wasd": {
			"move_up": [KEY_W],
			"move_down": [KEY_S],
			"move_left": [KEY_A],
			"move_right": [KEY_D],
		},
		"arrows": {
			"move_up": [KEY_UP],
			"move_down": [KEY_DOWN],
			"move_left": [KEY_LEFT],
			"move_right": [KEY_RIGHT],
		},
		"fps": {
			"move_forward": [KEY_W],
			"move_back": [KEY_S],
			"move_left": [KEY_A],
			"move_right": [KEY_D],
			"jump": [KEY_SPACE],
			"shoot": [32],  # MOUSE_BUTTON_LEFT mapped as keycode placeholder
			"reload": [KEY_R],
		},
		"platformer": {
			"move_left": [KEY_A, KEY_LEFT],
			"move_right": [KEY_D, KEY_RIGHT],
			"jump": [KEY_SPACE, KEY_W, KEY_UP],
		},
		"rpg": {
			"move_up": [KEY_W, KEY_UP],
			"move_down": [KEY_S, KEY_DOWN],
			"move_left": [KEY_A, KEY_LEFT],
			"move_right": [KEY_D, KEY_RIGHT],
			"interact": [KEY_E],
			"inventory": [KEY_I],
			"attack": [KEY_J],
		},
		"fighting": {
			"move_left": [KEY_A, KEY_LEFT],
			"move_right": [KEY_D, KEY_RIGHT],
			"jump": [KEY_W, KEY_UP],
			"crouch": [KEY_S, KEY_DOWN],
			"attack_light": [KEY_J],
			"attack_heavy": [KEY_K],
			"block": [KEY_L],
		},
		"racing": {
			"accelerate": [KEY_W, KEY_UP],
			"brake": [KEY_S, KEY_DOWN],
			"steer_left": [KEY_A, KEY_LEFT],
			"steer_right": [KEY_D, KEY_RIGHT],
		},
		"twin_stick": {
			"move_up": [KEY_W],
			"move_down": [KEY_S],
			"move_left": [KEY_A],
			"move_right": [KEY_D],
			"shoot": [32],
		},
	}

	var preset: Dictionary = presets.get(preset_name, {})
	if preset.is_empty():
		return {"success": false, "error": "Unknown preset: %s. Available: %s" % [preset_name, ", ".join(presets.keys())]}

	var added: Array = []
	for action_name in preset:
		var keys: Array = preset[action_name]
		var events: Array = []
		for key_code in keys:
			events.append({
				"event": {
					"alt_pressed": false,
					"ctrl_pressed": false,
					"keycode": key_code,
					"physical_keycode": 0,
					"meta_pressed": false,
					"shift_pressed": false,
					"unicode": 0
				},
				"read_only": false
			})
		config.set_value("input", action_name, [{"deadzone": deadzone, "events": events}])
		added.append(action_name)

	if not _save_project_config(config, project_path):
		return {"success": false, "error": "Failed to save project.godot"}

	return {"success": true, "data": "Applied '%s' preset: %d actions configured\nActions: %s" % [preset_name, added.size(), ", ".join(added)]}
