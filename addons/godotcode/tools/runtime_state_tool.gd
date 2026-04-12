class_name GCRuntimeStateTool
extends GCBaseTool
## Inspect live game state during play mode


var _runtime_monitor: GCRuntimeMonitor


func _init() -> void:
	super._init(
		"RuntimeState",
		"Inspect live game state during play mode. Only works when the game is running. Actions: tree, properties, screenshot, watch.",
		{
			"action": {
				"type": "string",
				"description": "Action: tree (scene tree), properties (node values), screenshot (game viewport), watch (poll property)",
				"enum": ["tree", "properties", "screenshot", "watch"]
			},
			"node_path": {
				"type": "string",
				"description": "Node path for properties/watch actions (e.g. 'Player' or 'Root/Enemies/Enemy1')"
			},
			"property": {
				"type": "string",
				"description": "Property name to watch (for watch action)"
			},
			"depth": {
				"type": "integer",
				"description": "Tree depth for tree action (default 3, max 6)"
			},
			"frames": {
				"type": "integer",
				"description": "Number of frames to poll for watch action (default 60)"
			}
		}
	)
	is_read_only = true


func validate_input(input: Dictionary) -> Dictionary:
	var action: String = input.get("action", "")
	if action == "":
		return {"valid": false, "error": "action is required"}
	return {"valid": true}


func execute(input: Dictionary, context: Dictionary) -> Dictionary:
	if not _runtime_monitor:
		_runtime_monitor = context.get("runtime_monitor")
	if not _runtime_monitor:
		return {"success": false, "error": "Runtime monitor not available"}

	var action: String = input.get("action", "")

	match action:
		"tree":
			var depth: int = input.get("depth", 3)
			depth = clampi(depth, 1, 6)
			var tree_str := _runtime_monitor.get_remote_tree(depth)
			return {"success": true, "data": tree_str}

		"properties":
			var node_path: String = input.get("node_path", "")
			if node_path == "":
				return {"success": false, "error": "node_path is required for properties action"}
			return _runtime_monitor.get_remote_node_properties(node_path)

		"screenshot":
			return await _capture_screenshot()

		"watch":
			var node_path: String = input.get("node_path", "")
			var prop: String = input.get("property", "")
			var frames: int = input.get("frames", 60)
			if node_path == "" or prop == "":
				return {"success": false, "error": "node_path and property are required for watch action"}
			return await _watch_property(node_path, prop, frames)

		_:
			return {"success": false, "error": "Unknown action: %s" % action}


func _capture_screenshot() -> Dictionary:
	var result := _runtime_monitor.capture_runtime_screenshot()
	if not result.get("success", false):
		return result

	if not result.get("needs_await", false):
		return result

	var viewport: Viewport = result.get("viewport")
	if not viewport:
		return {"success": false, "error": "No viewport available"}

	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	if not image:
		return {"success": false, "error": "Failed to capture viewport image"}

	# Resize for reasonable size
	if image.get_width() > 1280:
		var scale := 1280.0 / image.get_width()
		image.resize(1280, int(image.get_height() * scale))

	var png_data := image.save_png_to_buffer()
	var base64_str := Marshalls.raw_to_base64(png_data)

	return {
		"success": true,
		"data": "Runtime screenshot captured (%dx%d)" % [image.get_width(), image.get_height()],
		"is_vision": true,
		"vision_data": base64_str,
		"media_type": "image/png"
	}


func _watch_property(node_path: String, prop: String, frames: int) -> Dictionary:
	var values: Array = []
	var collected := 0

	for i in range(frames):
		await Engine.get_main_loop().process_frame

		var result := _runtime_monitor.get_remote_node_properties(node_path)
		if result.get("success", false):
			var data: Dictionary = result.get("data", {})
			if data.has(prop):
				values.append({"frame": i, "value": data[prop]})
				collected += 1

		if not _runtime_monitor.is_game_running():
			break

	if values.is_empty():
		return {"success": false, "error": "Could not read property '%s' on '%s'" % [prop, node_path]}

	var lines: Array = ["Frame | Value"]
	lines.append("-----|------")
	for v in values:
		lines.append("%5d | %s" % [v.frame, v.value])

	return {"success": true, "data": "Watched %s.%s over %d frames:\n%s" % [node_path, prop, collected, "\n".join(lines)]}
