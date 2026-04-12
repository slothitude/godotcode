class_name GCCollisionTool
extends GCBaseTool
## Configure physics collision layers and masks


func _init() -> void:
	super._init(
		"Collision",
		"Configure physics collision layers and masks. Actions: define_layers, apply_layers, list_layers, check_conflicts, set_node_collision.",
		{
			"action": {
				"type": "string",
				"description": "Action: define_layers, apply_layers, list_layers, check_conflicts, set_node_collision",
				"enum": ["define_layers", "apply_layers", "list_layers", "check_conflicts", "set_node_collision"]
			},
			"layers": {
				"type": "object",
				"description": "Layer name to bit number mapping, e.g. {\"Player\": 1, \"Enemy\": 2, \"Projectile\": 3, \"Environment\": 4}"
			},
			"entity_layers": {
				"type": "object",
				"description": "Entity to layer assignment, e.g. {\"Player\": {\"layer\": [\"Player\"], \"mask\": [\"Enemy\", \"Environment\"]}}"
			},
			"node_path": {
				"type": "string",
				"description": "Scene tree path to the node (for set_node_collision)"
			},
			"collision_layer": {
				"type": "array",
				"description": "Layer names this node belongs to (for set_node_collision)"
			},
			"collision_mask": {
				"type": "array",
				"description": "Layer names this node detects (for set_node_collision)"
			},
			"layer_value": {
				"type": "integer",
				"description": "Raw bit value for collision_layer (1-32, for set_node_collision)"
			},
			"mask_value": {
				"type": "integer",
				"description": "Raw bit value for collision_mask (1-32, for set_node_collision)"
			},
			"scene_path": {
				"type": "string",
				"description": "Scene file to apply layers to (for apply_layers)"
			}
		}
	)
	is_read_only = false


func validate_input(input: Dictionary) -> Dictionary:
	var action: String = input.get("action", "")
	if action == "":
		return {"valid": false, "error": "action is required"}
	match action:
		"define_layers":
			if input.get("layers", {}) is not Dictionary or input.get("layers", {}).is_empty():
				return {"valid": false, "error": "layers mapping is required"}
		"apply_layers":
			if input.get("entity_layers", {}) is not Dictionary or input.get("entity_layers", {}).is_empty():
				return {"valid": false, "error": "entity_layers mapping is required"}
		"set_node_collision":
			if input.get("node_path", "") == "":
				return {"valid": false, "error": "node_path is required"}
	return {"valid": true}


func check_permissions(input: Dictionary, context: Dictionary) -> Dictionary:
	var action: String = input.get("action", "")
	if action in ["list_layers", "check_conflicts"]:
		return {"behavior": "allow"}
	return {"behavior": "ask", "message": "Collision: %s" % action}


func execute(input: Dictionary, context: Dictionary) -> Dictionary:
	var action: String = input.get("action", "")
	var project_path: String = context.get("project_path", "")

	match action:
		"define_layers":
			return _define_layers(input, project_path)
		"apply_layers":
			return _apply_layers(input, project_path)
		"list_layers":
			return _list_layers(project_path)
		"check_conflicts":
			return _check_conflicts(input)
		"set_node_collision":
			return _set_node_collision(input)
		_:
			return {"success": false, "error": "Unknown action: %s" % action}


func _define_layers(input: Dictionary, project_path: String) -> Dictionary:
	var layers: Dictionary = input.get("layers", {})
	var config := ConfigFile.new()
	var path: String = project_path + "/project.godot"
	config.load(path)

	var lines: Array = []
	for layer_name in layers:
		var bit: int = int(layers[layer_name])
		if bit < 1 or bit > 32:
			return {"success": false, "error": "Layer bit must be 1-32, got %d for '%s'" % [bit, layer_name]}

		# Set both 2D and 3D layer names
		var key_2d := "layer_names_2d_physics/layer_%d" % bit
		var key_3d := "layer_names_3d_physics/layer_%d" % bit
		config.set_value("physics", key_2d, layer_name)
		config.set_value("physics", key_3d, layer_name)
		lines.append("  Layer %d: %s" % [bit, layer_name])

	# Save layer mapping for later use
	var mapping_path: String = project_path + "/.godotcode_collision_layers.json"
	var mapping_file := FileAccess.open(mapping_path, FileAccess.WRITE)
	if mapping_file:
		mapping_file.store_string(JSON.stringify(layers, "\t"))
		mapping_file.close()

	config.save(path)
	return {"success": true, "data": "Defined %d collision layers:\n%s" % [layers.size(), "\n".join(lines)]}


func _apply_layers(input: Dictionary, project_path: String) -> Dictionary:
	var entity_layers: Dictionary = input.get("entity_layers", {})

	# Load layer mapping
	var mapping_path: String = project_path + "/.godotcode_collision_layers.json"
	var layer_map: Dictionary = {}
	if FileAccess.file_exists(mapping_path):
		var fa := FileAccess.open(mapping_path, FileAccess.READ)
		if fa:
			var json := JSON.new()
			json.parse(fa.get_as_text())
			layer_map = json.data if json.data is Dictionary else {}
			fa.close()

	if layer_map.is_empty():
		return {"success": false, "error": "No layer definitions found. Use define_layers first."}

	if not Engine.is_editor_hint():
		return {"success": false, "error": "apply_layers requires editor mode"}

	var root := EditorInterface.get_edited_scene_root()
	if not root:
		return {"success": false, "error": "No scene open"}

	var applied: Array = []
	var errors: Array = []

	for entity_name in entity_layers:
		var config: Dictionary = entity_layers[entity_name]
		var layer_names: Array = config.get("layer", [])
		var mask_names: Array = config.get("mask", [])

		var layer_value := _names_to_bits(layer_names, layer_map)
		var mask_value := _names_to_bits(mask_names, layer_map)

		# Find nodes matching entity name
		var nodes := _find_collision_nodes(root, entity_name)
		if nodes.is_empty():
			# Try finding by partial match
			nodes = _find_collision_nodes_fuzzy(root, entity_name)

		for node in nodes:
			if _set_collision_on_node(node, layer_value, mask_value):
				applied.append("%s (layer=%d, mask=%d)" % [str(root.get_path_to(node)), layer_value, mask_value])
			else:
				errors.append("Could not set collision on %s" % str(root.get_path_to(node)))

	var msg := "Applied collision config to %d nodes" % applied.size()
	if not errors.is_empty():
		msg += "\nErrors:\n" + "\n".join(errors)
	if not applied.is_empty():
		msg += "\nNodes:\n" + "\n".join(applied)
	return {"success": true, "data": msg}


func _list_layers(project_path: String) -> Dictionary:
	var config := ConfigFile.new()
	config.load(project_path + "/project.godot")

	var layers_2d: Array = []
	var layers_3d: Array = []

	for i in range(1, 33):
		var name_2d: String = config.get_value("physics", "layer_names_2d_physics/layer_%d" % i, "")
		var name_3d: String = config.get_value("physics", "layer_names_3d_physics/layer_%d" % i, "")
		if name_2d != "":
			layers_2d.append("  %d: %s" % [i, name_2d])
		if name_3d != "":
			layers_3d.append("  %d: %s" % [i, name_3d])

	var lines: Array = []
	if not layers_2d.is_empty():
		lines.append("2D Physics Layers:")
		lines.append_array(layers_2d)
	if not layers_3d.is_empty():
		if not lines.is_empty():
			lines.append("")
		lines.append("3D Physics Layers:")
		lines.append_array(layers_3d)
	if lines.is_empty():
		return {"success": true, "data": "No collision layers defined. Use define_layers."}

	return {"success": true, "data": "\n".join(lines)}


func _check_conflicts(input: Dictionary) -> Dictionary:
	if not Engine.is_editor_hint():
		return {"success": false, "error": "Requires editor mode"}

	var root := EditorInterface.get_edited_scene_root()
	if not root:
		return {"success": false, "error": "No scene open"}

	var issues: Array = []
	_check_node_collisions(root, issues, root)

	if issues.is_empty():
		return {"success": true, "data": "No collision issues found."}

	return {"success": true, "data": "Collision issues:\n" + "\n".join(issues), "issues": issues}


func _set_node_collision(input: Dictionary) -> Dictionary:
	if not Engine.is_editor_hint():
		return {"success": false, "error": "Requires editor mode"}

	var node_path: String = input.get("node_path", "")
	var root := EditorInterface.get_edited_scene_root()
	if not root:
		return {"success": false, "error": "No scene open"}

	var node := root.get_node_or_null(NodePath(node_path))
	if not node:
		return {"success": false, "error": "Node not found: %s" % node_path}

	var layer_value: int = input.get("layer_value", 0)
	var mask_value: int = input.get("mask_value", 0)

	if layer_value == 0 and mask_value == 0:
		return {"success": false, "error": "Provide layer_value and/or mask_value"}

	if layer_value > 0 and "collision_layer" in node:
		node.collision_layer = layer_value
	if mask_value > 0 and "collision_mask" in node:
		node.collision_mask = mask_value

	return {"success": true, "data": "Set collision on %s: layer=%d, mask=%d" % [node_path, node.collision_layer if "collision_layer" in node else 0, node.collision_mask if "collision_mask" in node else 0]}


func _names_to_bits(names: Array, layer_map: Dictionary) -> int:
	var bits: int = 0
	for name in names:
		if layer_map.has(name):
			bits |= 1 << (int(layer_map[name]) - 1)
		elif name.is_valid_int():
			bits |= 1 << (int(name) - 1)
	return bits


func _find_collision_nodes(node: Node, name: String) -> Array:
	var results: Array = []
	if node.name == name:
		if node is CollisionShape2D or node is CollisionShape3D or node is CollisionPolygon2D or node is CollisionPolygon3D:
			results.append(node)
		elif node is CharacterBody2D or node is CharacterBody3D or node is RigidBody2D or node is RigidBody3D or node is StaticBody2D or node is StaticBody3D or node is Area2D or node is Area3D:
			results.append(node)
	for child in node.get_children():
		results.append_array(_find_collision_nodes(child, name))
	return results


func _find_collision_nodes_fuzzy(node: Node, name: String) -> Array:
	var results: Array = []
	var lower_name := name.to_lower()
	if node.name.to_lower().find(lower_name) >= 0:
		if node is CharacterBody2D or node is CharacterBody3D or node is RigidBody2D or node is RigidBody3D or node is Area2D or node is Area3D:
			results.append(node)
	for child in node.get_children():
		results.append_array(_find_collision_nodes_fuzzy(child, name))
	return results


func _set_collision_on_node(node: Node, layer: int, mask: int) -> bool:
	if "collision_layer" in node:
		node.collision_layer = layer
	if "collision_mask" in node:
		node.collision_mask = mask
	return "collision_layer" in node or "collision_mask" in node


func _check_node_collisions(node: Node, issues: Array, root: Node) -> void:
	if "collision_layer" in node:
		var layer: int = node.collision_layer
		var mask: int = node.collision_mask
		if layer == 0:
			issues.append("WARNING: %s has no collision_layer set" % str(root.get_path_to(node)))
		if mask == 0:
			issues.append("INFO: %s has no collision_mask (won't detect any collisions)" % str(root.get_path_to(node)))
		# Check for CollisionShape children
		var has_shape := false
		for child in node.get_children():
			if child is CollisionShape2D or child is CollisionShape3D or child is CollisionPolygon2D or child is CollisionPolygon3D:
				has_shape = true
				break
		if not has_shape and (node is CharacterBody2D or node is CharacterBody3D or node is RigidBody2D or node is RigidBody3D or node is StaticBody2D or node is StaticBody3D):
			issues.append("WARNING: %s is a physics body but has no CollisionShape child" % str(root.get_path_to(node)))
	for child in node.get_children():
		_check_node_collisions(child, issues, root)
