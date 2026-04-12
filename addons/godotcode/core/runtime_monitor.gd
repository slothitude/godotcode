class_name GCRuntimeMonitor
extends RefCounted
## Watch game state during play mode — impossible for CLI tools


func is_game_running() -> bool:
	## Check if the game is currently running (not editor-only)
	if Engine.is_editor_hint():
		# In editor — check if there's a running game scene
		var tree := Engine.get_main_loop() as SceneTree
		if tree and tree.root.get_child_count() > 1:
			# Child 0 is usually the editor, child 1+ are game scenes
			for i in range(1, tree.root.get_child_count()):
				var child: Node = tree.root.get_child(i)
				if child is Node and not child.is_queued_for_deletion():
					return true
	return false


func get_remote_tree(depth: int = 3) -> String:
	## Serialize live runtime scene tree
	if not is_game_running():
		return "Game is not running"

	var game_root := _get_game_root()
	if not game_root:
		return "No game root found"

	return _serialize_tree(game_root, depth, 0)


func get_remote_node_properties(node_path: String) -> Dictionary:
	## Read runtime property values from a live node
	if not is_game_running():
		return {"success": false, "error": "Game is not running"}

	var game_root := _get_game_root()
	if not game_root:
		return {"success": false, "error": "No game root found"}

	var node := game_root.get_node_or_null(node_path)
	if not node:
		# Try finding the node from the scene tree root
		var tree := Engine.get_main_loop() as SceneTree
		if tree:
			node = tree.root.get_node_or_null(node_path)
	if not node:
		return {"success": false, "error": "Node not found: %s" % node_path}

	# Collect common properties
	var props: Dictionary = {}
	var property_list := node.get_property_list()
	for prop in property_list:
		var pname: String = prop.get("name", "")
		# Only include useful properties (skip internal/engine ones)
		if pname.begins_with("_") or pname.contains("/"):
			continue
		if prop.get("usage", 0) & PROPERTY_USAGE_STORAGE or prop.get("usage", 0) & PROPERTY_USAGE_EDITOR:
			var value = node.get(pname)
			# Only include serializable types
			if value is String or value is int or value is float or value is bool or value is Vector2 or value is Vector3 or value is Color or value is Array or value is Dictionary:
				props[pname] = str(value)

	return {"success": true, "data": props}


func capture_runtime_screenshot() -> Dictionary:
	## Capture game viewport as base64
	if not is_game_running():
		return {"success": false, "error": "Game is not running"}

	var game_root := _get_game_root()
	if not game_root or not game_root.get_viewport():
		return {"success": false, "error": "No game viewport found"}

	# This must be called with await — return instruction
	return {
		"success": true,
		"needs_await": true,
		"viewport": game_root.get_viewport()
	}


func watch_property(node_path: String, property_name: String, frames: int = 60) -> Dictionary:
	## Poll a node property over N frames — returns instruction for tool to handle
	if not is_game_running():
		return {"success": false, "error": "Game is not running"}

	return {
		"success": true,
		"watch": true,
		"node_path": node_path,
		"property": property_name,
		"frames": frames
	}


func _get_game_root() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if not tree:
		return null

	# Find the running game scene
	for i in range(1, tree.root.get_child_count()):
		var child: Node = tree.root.get_child(i)
		if child and not child.is_queued_for_deletion():
			return child
	return null


func _serialize_tree(node: Node, max_depth: int, current_depth: int) -> String:
	var indent := "  ".repeat(current_depth)
	var line := "%s%s [%s]" % [indent, node.name, node.get_class()]

	# Add key properties
	if node is Node2D or node is Node3D:
		if node is Node2D:
			line += " pos=(%s)" % str(node.position).replace("(", "").replace(")", "")
		elif node is Node3D:
			line += " pos=(%s)" % str(node.position).replace("((", "").replace("))", "").replace("(", "").replace(")", "").left(30)
	elif node is Control:
		line += " size=%s" % str(node.size).replace("(", "").replace(")", "")

	var lines := [line]

	if current_depth < max_depth:
		for i in range(node.get_child_count()):
			var child: Node = node.get_child(i)
			lines.append(_serialize_tree(child, max_depth, current_depth + 1))

	return "\n".join(lines)
