class_name GCAnimationTool
extends GCBaseTool
## Create and manage animations on AnimationPlayer nodes


func _init() -> void:
	super._init(
		"Animation",
		"Create and manage animations with AnimationPlayer. Actions: create_player, add_animation, add_track, keyframe, list, play, stop, remove, apply_preset.",
		{
			"action": {
				"type": "string",
				"description": "Action: create_player, add_animation, add_track, keyframe, list, play, stop, remove, apply_preset",
				"enum": ["create_player", "add_animation", "add_track", "keyframe", "list", "play", "stop", "remove", "apply_preset"]
			},
			"node_path": {
				"type": "string",
				"description": "Scene tree path to the target node or AnimationPlayer"
			},
			"animation_name": {
				"type": "string",
				"description": "Name of the animation (e.g. 'idle', 'walk', 'bounce')"
			},
			"track_type": {
				"type": "string",
				"description": "Track type: value, position, rotation, scale, blend_shape (default: value)",
				"enum": ["value", "position", "rotation", "scale", "blend_shape"]
			},
			"track_path": {
				"type": "string",
				"description": "Path within AnimationPlayer to the property being animated (e.g. ':position' or 'Sprite2D:modulate')"
			},
			"time": {
				"type": "number",
				"description": "Time in seconds for the keyframe (default: 0.0)"
			},
			"value": {
				"description": "Value for the keyframe (number, array for Vector2/3, string)"
			},
			"duration": {
				"type": "number",
				"description": "Animation duration in seconds (default: 1.0)"
			},
			"loop": {
				"type": "boolean",
				"description": "Loop the animation (default: false)"
			},
			"speed": {
				"type": "number",
				"description": "Playback speed multiplier (default: 1.0)"
			},
			"preset": {
				"type": "string",
				"description": "Animation preset: bounce, rotate, fade, scale_pulse, float, shake, flash",
				"enum": ["bounce", "rotate", "fade", "scale_pulse", "float", "shake", "flash"]
			},
			"transition": {
				"type": "number",
				"description": "Transition type: 0=linear, 1=ease_in, 2=ease_out, 3=ease_in_out (default: 1)"
			}
		}
	)
	is_read_only = false


func validate_input(input: Dictionary) -> Dictionary:
	var action: String = input.get("action", "")
	if action == "":
		return {"valid": false, "error": "action is required"}
	match action:
		"create_player", "add_animation", "play", "stop", "remove":
			if input.get("node_path", "") == "":
				return {"valid": false, "error": "node_path is required"}
		"add_track", "keyframe":
			if input.get("node_path", "") == "":
				return {"valid": false, "error": "node_path is required"}
			if input.get("animation_name", "") == "":
				return {"valid": false, "error": "animation_name is required"}
		"apply_preset":
			if input.get("node_path", "") == "":
				return {"valid": false, "error": "node_path is required"}
			if input.get("preset", "") == "":
				return {"valid": false, "error": "preset is required"}
	return {"valid": true}


func check_permissions(input: Dictionary, context: Dictionary) -> Dictionary:
	var action: String = input.get("action", "")
	if action == "list":
		return {"behavior": "allow"}
	return {"behavior": "ask", "message": "Animation: %s on %s" % [action, input.get("node_path", "")]}


func execute(input: Dictionary, context: Dictionary) -> Dictionary:
	if not Engine.is_editor_hint():
		return {"success": false, "error": "Animation tool only works in editor"}

	var action: String = input.get("action", "")

	match action:
		"create_player":
			return _create_player(input)
		"add_animation":
			return _add_animation(input)
		"add_track":
			return _add_track(input)
		"keyframe":
			return _keyframe(input)
		"list":
			return _list(input)
		"play":
			return _play(input)
		"stop":
			return _stop(input)
		"remove":
			return _remove(input)
		"apply_preset":
			return _apply_preset(input)
		_:
			return {"success": false, "error": "Unknown action: %s" % action}


func _get_player(input: Dictionary) -> AnimationPlayer:
	var node_path: String = input.get("node_path", "")
	var node := _get_node(node_path)
	if not node:
		return null
	var player: AnimationPlayer = null
	if node is AnimationPlayer:
		player = node
	else:
		player = node.find_child("AnimationPlayer", false) as AnimationPlayer
	return player


func _get_node(path: String) -> Node:
	var root := EditorInterface.get_edited_scene_root()
	if not root:
		return null
	if path == "" or path == ".":
		return root
	return root.get_node_or_null(NodePath(path))


func _create_player(input: Dictionary) -> Dictionary:
	var node_path: String = input.get("node_path", "")
	var node := _get_node(node_path)
	if not node:
		return {"success": false, "error": "Node not found: %s" % node_path}

	var existing := node.find_child("AnimationPlayer", false)
	if existing:
		return {"success": true, "data": "AnimationPlayer already exists on %s" % node_path}

	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	node.add_child(player)
	player.owner = EditorInterface.get_edited_scene_root()

	return {"success": true, "data": "Created AnimationPlayer on %s" % node_path}


func _add_animation(input: Dictionary) -> Dictionary:
	var player := _get_player(input)
	if not player:
		return {"success": false, "error": "AnimationPlayer not found on %s. Use create_player first." % input.get("node_path", "")}

	var anim_name: String = input.get("animation_name", "new_animation")
	var duration: float = input.get("duration", 1.0)
	var loop: bool = input.get("loop", false)

	if player.has_animation(anim_name):
		return {"success": false, "error": "Animation '%s' already exists" % anim_name}

	var anim := Animation.new()
	var lib := AnimationLibrary.new()
	anim.resource_name = anim_name
	anim.length = duration
	anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE

	if not player.has_animation_library(""):
		lib = AnimationLibrary.new()
		player.add_animation_library("", lib)

	player.get_animation_library("").add_animation(anim_name, anim)

	return {"success": true, "data": "Added animation '%s' (%.1fs, loop=%s)" % [anim_name, duration, str(loop)]}


func _add_track(input: Dictionary) -> Dictionary:
	var player := _get_player(input)
	if not player:
		return {"success": false, "error": "AnimationPlayer not found"}

	var anim_name: String = input.get("animation_name", "")
	if not player.has_animation(anim_name):
		return {"success": false, "error": "Animation '%s' not found" % anim_name}

	var anim: Animation = player.get_animation(anim_name)
	var track_type: String = input.get("track_type", "value")
	var track_path: String = input.get("track_path", ":position")

	var type_map := {
		"value": Animation.TYPE_VALUE,
		"position": Animation.TYPE_POSITION_3D if _is_3d(input) else Animation.TYPE_VALUE,
		"rotation": Animation.TYPE_ROTATION_3D if _is_3d(input) else Animation.TYPE_VALUE,
		"scale": Animation.TYPE_SCALE_3D if _is_3d(input) else Animation.TYPE_VALUE,
	}

	var track_idx: int = anim.add_track(type_map.get(track_type, Animation.TYPE_VALUE))
	anim.track_set_path(track_idx, track_path)

	return {"success": true, "data": "Added %s track (index %d) to '%s' at path '%s'" % [track_type, track_idx, anim_name, track_path], "track_index": track_idx}


func _keyframe(input: Dictionary) -> Dictionary:
	var player := _get_player(input)
	if not player:
		return {"success": false, "error": "AnimationPlayer not found"}

	var anim_name: String = input.get("animation_name", "")
	if not player.has_animation(anim_name):
		return {"success": false, "error": "Animation '%s' not found" % anim_name}

	var anim: Animation = player.get_animation(anim_name)
	var time: float = input.get("time", 0.0)
	var value = input.get("value", 0.0)
	var transition: int = input.get("transition", 1)

	# Use last track if no track specified
	var track_idx: int = anim.get_track_count() - 1
	if track_idx < 0:
		return {"success": false, "error": "No tracks in animation. Use add_track first."}

	# Convert value type
	var converted_value = _convert_value(value)
	var key_idx: int = anim.track_insert_key(track_idx, time, converted_value, transition)

	return {"success": true, "data": "Keyframe added at t=%.2f on track %d" % [time, track_idx], "key_index": key_idx}


func _list(input: Dictionary) -> Dictionary:
	var node_path: String = input.get("node_path", "")
	if node_path == "":
		# List all AnimationPlayers in scene
		var root := EditorInterface.get_edited_scene_root()
		if not root:
			return {"success": false, "error": "No scene open"}
		var players := _find_animation_players(root)
		if players.is_empty():
			return {"success": true, "data": "No AnimationPlayers in current scene"}
		var lines: Array = []
		for p in players:
			var anims: Array = p.get_animation_list()
			lines.append("%s: [%s]" % [str(root.get_path_to(p)), ", ".join(anims)])
		return {"success": true, "data": "AnimationPlayers:\n" + "\n".join(lines)}

	var player := _get_player(input)
	if not player:
		return {"success": false, "error": "AnimationPlayer not found"}
	var anims: Array = player.get_animation_list()
	if anims.is_empty():
		return {"success": true, "data": "No animations on %s" % node_path}
	var lines: Array = []
	for anim_name in anims:
		var anim: Animation = player.get_animation(anim_name)
		var info := "%s (%.1fs, %d tracks" % [anim_name, anim.length, anim.get_track_count()]
		if anim.loop_mode != Animation.LOOP_NONE:
			info += ", looping"
		info += ")"
		lines.append("  " + info)
	return {"success": true, "data": "Animations on %s:\n%s" % [node_path, "\n".join(lines)]}


func _play(input: Dictionary) -> Dictionary:
	var player := _get_player(input)
	if not player:
		return {"success": false, "error": "AnimationPlayer not found"}

	var anim_name: String = input.get("animation_name", "")
	var speed: float = input.get("speed", 1.0)

	if anim_name != "":
		player.play(anim_name, -1.0, speed)
		return {"success": true, "data": "Playing '%s' at %.1fx speed" % [anim_name, speed]}
	else:
		player.play()
		return {"success": true, "data": "Playing default animation"}


func _stop(input: Dictionary) -> Dictionary:
	var player := _get_player(input)
	if not player:
		return {"success": false, "error": "AnimationPlayer not found"}
	player.stop()
	return {"success": true, "data": "Stopped animation on %s" % input.get("node_path", "")}


func _remove(input: Dictionary) -> Dictionary:
	var player := _get_player(input)
	if not player:
		return {"success": false, "error": "AnimationPlayer not found"}

	var anim_name: String = input.get("animation_name", "")
	if anim_name == "":
		# Remove the AnimationPlayer node
		var node_path: String = input.get("node_path", "")
		var node := _get_node(node_path)
		if node is AnimationPlayer:
			node.queue_free()
			return {"success": true, "data": "Removed AnimationPlayer at %s" % node_path}
		return {"success": false, "error": "Specify animation_name or target an AnimationPlayer node"}

	if not player.has_animation(anim_name):
		return {"success": false, "error": "Animation '%s' not found" % anim_name}

	player.get_animation_library("").remove_animation(anim_name)
	return {"success": true, "data": "Removed animation '%s'" % anim_name}


func _apply_preset(input: Dictionary) -> Dictionary:
	var node_path: String = input.get("node_path", "")
	var preset_name: String = input.get("preset", "")
	var duration: float = input.get("duration", 1.0)
	var loop: bool = input.get("loop", true)

	# Ensure AnimationPlayer exists
	var create_result := _create_player(input)
	var player := _get_player(input)
	if not player:
		return {"success": false, "error": "Could not create/find AnimationPlayer"}

	var anim_name: String = preset_name
	if player.has_animation(anim_name):
		player.get_animation_library("").remove_animation(anim_name)

	var anim := Animation.new()
	anim.resource_name = anim_name
	anim.length = duration
	anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE

	var node := _get_node(node_path)
	var relative_path: String = ""
	if node:
		var root := EditorInterface.get_edited_scene_root()
		if root:
			relative_path = str(root.get_path_to(node))

	# Build preset animation
	match preset_name:
		"bounce":
			var track := anim.add_track(Animation.TYPE_VALUE)
			anim.track_set_path(track, ":position:y")
			anim.track_insert_key(track, 0.0, 0.0)
			anim.track_insert_key(track, duration * 0.3, -30.0)
			anim.track_insert_key(track, duration * 0.5, -40.0)
			anim.track_insert_key(track, duration * 0.7, -30.0)
			anim.track_insert_key(track, duration, 0.0)

		"rotate":
			var track := anim.add_track(Animation.TYPE_VALUE)
			anim.track_set_path(track, ":rotation_degrees:y" if _is_3d(input) else ":rotation_degrees")
			anim.track_insert_key(track, 0.0, 0.0)
			anim.track_insert_key(track, duration, 360.0)

		"fade":
			var track := anim.add_track(Animation.TYPE_VALUE)
			anim.track_set_path(track, ":modulate:a")
			anim.track_insert_key(track, 0.0, 1.0)
			anim.track_insert_key(track, duration * 0.5, 0.0)
			anim.track_insert_key(track, duration, 1.0)

		"scale_pulse":
			var track := anim.add_track(Animation.TYPE_VALUE)
			anim.track_set_path(track, ":scale")
			anim.track_insert_key(track, 0.0, Vector2(1.0, 1.0))
			anim.track_insert_key(track, duration * 0.5, Vector2(1.2, 1.2))
			anim.track_insert_key(track, duration, Vector2(1.0, 1.0))

		"float":
			var track := anim.add_track(Animation.TYPE_VALUE)
			anim.track_set_path(track, ":position:y")
			anim.track_insert_key(track, 0.0, 0.0)
			anim.track_insert_key(track, duration * 0.25, -5.0)
			anim.track_insert_key(track, duration * 0.75, 5.0)
			anim.track_insert_key(track, duration, 0.0)

		"shake":
			var track := anim.add_track(Animation.TYPE_VALUE)
			anim.track_set_path(track, ":position:x")
			var steps := 8
			for i in steps + 1:
				var t := duration * float(i) / float(steps)
				var offset := 3.0 * (1.0 if i % 2 == 0 else -1.0)
				if i == 0 or i == steps:
					offset = 0.0
				anim.track_insert_key(track, t, offset)

		"flash":
			var track := anim.add_track(Animation.TYPE_VALUE)
			anim.track_set_path(track, ":modulate")
			anim.track_insert_key(track, 0.0, Color.WHITE)
			anim.track_insert_key(track, duration * 0.2, Color.RED)
			anim.track_insert_key(track, duration * 0.4, Color.WHITE)
			anim.track_insert_key(track, duration * 0.6, Color.RED)
			anim.track_insert_key(track, duration, Color.WHITE)

		_:
			return {"success": false, "error": "Unknown preset: %s" % preset_name}

	if not player.has_animation_library(""):
		var lib := AnimationLibrary.new()
		player.add_animation_library("", lib)
	player.get_animation_library("").add_animation(anim_name, anim)

	return {"success": true, "data": "Applied '%s' preset to %s (%.1fs, loop=%s)" % [preset_name, node_path, duration, str(loop)]}


func _is_3d(input: Dictionary) -> bool:
	var node_path: String = input.get("node_path", "")
	var node := _get_node(node_path)
	if node:
		return node is Node3D
	return false


func _find_animation_players(node: Node, result: Array = []) -> Array:
	if node is AnimationPlayer:
		result.append(node)
	for child in node.get_children():
		_find_animation_players(child, result)
	return result


func _convert_value(value) -> Variant:
	if value is Array:
		if value.size() == 2:
			return Vector2(float(value[0]), float(value[1]))
		if value.size() == 3:
			return Vector3(float(value[0]), float(value[1]), float(value[2]))
		if value.size() == 4:
			return Color(float(value[0]), float(value[1]), float(value[2]), float(value[3]))
	if value is float or value is int:
		return float(value)
	return value
