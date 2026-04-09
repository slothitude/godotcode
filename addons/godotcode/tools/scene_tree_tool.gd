class_name GCSceneTreeTool
extends GCBaseTool
## Inspect and manipulate the live scene tree in the Godot editor


func _init() -> void:
	super._init(
		"SceneTree",
		"Inspect and manipulate the live scene tree. List nodes, get details, add/delete/reparent nodes.",
		{
			"action": {
				"type": "string",
				"description": "'list' to show tree, 'get_node' for details, 'add_node' to create, 'delete_node' to remove, 'reparent_node' to move",
				"enum": ["list", "get_node", "add_node", "delete_node", "reparent_node"]
			},
			"node_path": {
				"type": "string",
				"description": "Path to node (e.g. 'Root/Player'). For list, use as root of subtree."
			},
			"depth": {
				"type": "integer",
				"description": "Max depth for list action (default 5)"
			},
			"node_type": {
				"type": "string",
				"description": "Class name for add_node (e.g. 'Node3D', 'Sprite2D', 'Camera3D')"
			},
			"node_name": {
				"type": "string",
				"description": "Name for the new node (add_node action)"
			},
			"parent_path": {
				"type": "string",
				"description": "Parent node path for add_node"
			},
			"new_parent_path": {
				"type": "string",
				"description": "New parent for reparent_node action"
			},
			"properties": {
				"type": "object",
				"description": "Initial properties to set on new node (add_node action, optional)"
			}
		}
	)
	is_read_only = false


func validate_input(input: Dictionary) -> Dictionary:
	var action: String = input.get("action", "")
	if action == "":
		return {"valid": false, "error": "action is required"}
	if action not in ["list", "get_node", "add_node", "delete_node", "reparent_node"]:
		return {"valid": false, "error": "Invalid action: %s" % action}

	match action:
		"add_node":
			if not input.has("node_type"):
				return {"valid": false, "error": "node_type is required for add_node"}
			if not input.has("parent_path"):
				return {"valid": false, "error": "parent_path is required for add_node"}
		"delete_node", "reparent_node":
			if not input.has("node_path"):
				return {"valid": false, "error": "node_path is required for %s" % action}
		"reparent_node":
			if not input.has("new_parent_path"):
				return {"valid": false, "error": "new_parent_path is required for reparent_node"}
	return {"valid": true}


func check_permissions(input: Dictionary, context: Dictionary) -> Dictionary:
	var action: String = input.get("action", "")
	# Read-only actions are safe
	if action in ["list", "get_node"]:
		return {"behavior": "allow"}
	# Mutations require approval
	return {"behavior": "ask", "message": "SceneTree '%s': %s" % [action, input.get("node_path", input.get("parent_path", ""))]}


func execute(input: Dictionary, context: Dictionary) -> Dictionary:
	if not Engine.is_editor_hint():
		return {"success": false, "error": "SceneTree only works in the editor"}

	var action: String = input.get("action", "")

	match action:
		"list":
			return _list_tree(input)
		"get_node":
			return _get_node_info(input)
		"add_node":
			return _add_node(input)
		"delete_node":
			return _delete_node(input)
		"reparent_node":
			return _reparent_node(input)
		_:
			return {"success": false, "error": "Unknown action: %s" % action}


func _get_root() -> Node:
	return EditorInterface.get_edited_scene_root()


func _resolve_node(path: String) -> Node:
	var root := _get_root()
	if root == null:
		return null
	if path == "" or path == root.name or path == "/":
		return root
	if root.has_node(path):
		return root.get_node(path)
	var full := root.name + "/" + path
	if root.has_node(full):
		return root.get_node(full)
	return null


func _list_tree(input: Dictionary) -> Dictionary:
	var root := _get_root()
	if root == null:
		return {"success": false, "error": "No scene currently open"}

	var start_node := root
	var start_path: String = input.get("node_path", "")
	if start_path != "":
		start_node = _resolve_node(start_path)
		if start_node == null:
			return {"success": false, "error": "Node not found: %s" % start_path}

	var max_depth: int = input.get("depth", 5)
	var lines: Array = []
	_build_tree_lines(start_node, lines, 0, max_depth)

	return {"success": true, "data": "## Scene Tree\n%s" % "\n".join(lines)}


func _build_tree_lines(node: Node, lines: Array, depth: int, max_depth: int) -> void:
	var indent := "  ".repeat(depth)
	var path := _relative_path(node)
	var type_info := "[%s]" % node.get_class()
	var line := "%s%s %s" % [indent, node.name, type_info]
	if path != node.name:
		line += "  (%s)" % path
	lines.append(line)

	if depth < max_depth:
		for child in node.get_children():
			_build_tree_lines(child, lines, depth + 1, max_depth)


func _relative_path(node: Node) -> String:
	var root := _get_root()
	if root == null:
		return node.name
	if node == root:
		return node.name
	var path := node.get_path()
	var root_path := root.get_path()
	var rel := str(path).substr(str(root_path).length())
	if rel.begins_with("/"):
		rel = rel.substr(1)
	if rel == "":
		return node.name
	return node.name


func _get_node_info(input: Dictionary) -> Dictionary:
	var path: String = input.get("node_path", "")
	var node := _resolve_node(path)
	if node == null:
		return {"success": false, "error": "Node not found: %s" % path}

	var root := _get_root()
	var info := "## Node: %s\n" % node.name
	info += "Type: %s\n" % node.get_class()
	info += "Path: %s\n" % str(node.get_path())

	if node.scene_file_path != "":
		info += "Scene: %s\n" % node.scene_file_path

	if node.script:
		info += "Script: %s\n" % str(node.script.resource_path)

	info += "Children: %d\n" % node.get_child_count()

	# Key properties based on type
	var key_props := _get_key_properties(node)
	if key_props.size() > 0:
		info += "\n### Key Properties\n"
		for prop_name in key_props:
			var val = node.get(prop_name)
			if val != null:
				info += "%s: %s\n" % [prop_name, _format_val(val)]

	# Signal connections
	var connections := node.get_incoming_connections()
	if connections.size() > 0:
		info += "\n### Signal Connections\n"
		for conn in connections:
			var signal_name: String = conn.signal.get_name() if conn.signal else "?"
			var source: String = str(conn.source) if conn.source else "?"
			var method: String = conn.method if conn.method else "?"
			info += "%s -> %s.%s\n" % [signal_name, source, method]

	return {"success": true, "data": info}


func _get_key_properties(node: Node) -> Array:
	var type := node.get_class()
	match type:
		"Node3D":
			return ["position", "rotation_degrees", "scale", "visible"]
		"Node2D":
			return ["position", "rotation_degrees", "scale", "visible", "z_index"]
		"Control":
			return ["position", "size", "visible", "modulate"]
		"Camera3D":
			return ["current", "fov", "near", "far"]
		"Camera2D":
			return ["current", "zoom", "offset"]
		"MeshInstance3D":
			return ["mesh", "visible"]
		"Sprite2D", "Sprite3D":
			return ["texture", "visible", "modulate"]
		"RigidBody3D", "RigidBody2D":
			return ["position", "linear_velocity", "mass"]
		"CharacterBody3D", "CharacterBody2D":
			return ["position", "velocity"]
		"Area3D", "Area2D":
			return ["position", "monitoring"]
		"CollisionShape3D", "CollisionShape2D":
			return ["shape", "disabled"]
		_:
			return ["visible"] if "visible" in node else []


func _add_node(input: Dictionary) -> Dictionary:
	var node_type: String = input.get("node_type", "")
	var parent_path: String = input.get("parent_path", "")
	var node_name: String = input.get("node_name", node_type)

	var parent := _resolve_node(parent_path)
	if parent == null:
		return {"success": false, "error": "Parent node not found: %s" % parent_path}

	# Validate the type is instantiable
	if not ClassDB.class_exists(node_type):
		return {"success": false, "error": "Unknown class: %s" % node_type}
	if not ClassDB.can_instantiate(node_type):
		return {"success": false, "error": "Cannot instantiate class: %s (may be abstract or inherited)" % node_type}

	var node := ClassDB.instantiate(node_type)
	if node == null:
		return {"success": false, "error": "Failed to instantiate: %s" % node_type}

	node.name = node_name

	# Add to parent — owner must be set for scene persistence
	parent.add_child(node)
	var root := _get_root()
	if root:
		node.owner = root

	# Set initial properties if provided
	var properties: Dictionary = input.get("properties", {})
	var set_errors: Array = []
	for prop_name in properties:
		if prop_name in node:
			node.set(prop_name, properties[prop_name])
		else:
			set_errors.append("Property '%s' not found" % prop_name)

	var result := "Created %s '%s' under %s" % [node_type, node_name, parent.name]
	if set_errors.size() > 0:
		result += "\nWarnings: " + "; ".join(set_errors)

	return {"success": true, "data": result}


func _delete_node(input: Dictionary) -> Dictionary:
	var path: String = input.get("node_path", "")
	var node := _resolve_node(path)
	if node == null:
		return {"success": false, "error": "Node not found: %s" % path}

	var root := _get_root()
	if node == root:
		return {"success": false, "error": "Cannot delete the scene root node"}

	var parent := node.get_parent()
	if parent == null:
		return {"success": false, "error": "Node has no parent (cannot delete root)"}

	var node_name: String = node.name
	parent.remove_child(node)
	node.queue_free()

	return {"success": true, "data": "Deleted node '%s'" % node_name}


func _reparent_node(input: Dictionary) -> Dictionary:
	var path: String = input.get("node_path", "")
	var new_parent_path: String = input.get("new_parent_path", "")

	var node := _resolve_node(path)
	if node == null:
		return {"success": false, "error": "Node not found: %s" % path}

	var new_parent := _resolve_node(new_parent_path)
	if new_parent == null:
		return {"success": false, "error": "New parent not found: %s" % new_parent_path}

	var root := _get_root()
	if node == root:
		return {"success": false, "error": "Cannot reparent the scene root node"}

	# Check for circular reparenting (don't move a parent into its own child)
	if new_parent == node or _is_descendant_of(new_parent, node):
		return {"success": false, "error": "Cannot reparent: target is a descendant of the node"}

	var old_parent := node.get_parent()
	if old_parent:
		old_parent.remove_child(node)

	new_parent.add_child(node)

	# Re-set owner for scene persistence
	if root:
		node.owner = root
		_recurse_set_owner(node, root)

	return {"success": true, "data": "Reparented '%s' to '%s'" % [node.name, new_parent.name]}


func _is_descendant_of(potential_descendant: Node, ancestor: Node) -> bool:
	var current := potential_descendant
	while current:
		if current == ancestor:
			return true
		current = current.get_parent()
	return false


func _recurse_set_owner(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.owner = owner
		_recurse_set_owner(child, owner)


func _format_val(value) -> String:
	if value == null:
		return "null"
	match typeof(value):
		TYPE_VECTOR2:
			var v: Vector2 = value
			return "Vector2(%g, %g)" % [v.x, v.y]
		TYPE_VECTOR3:
			var v: Vector3 = value
			return "Vector3(%g, %g, %g)" % [v.x, v.y, v.z]
		TYPE_COLOR:
			var c: Color = value
			return "Color(%g, %g, %g, %g)" % [c.r, c.g, c.b, c.a]
		TYPE_OBJECT:
			if value is Resource:
				var res: Resource = value
				return "<%s: %s>" % [value.get_class(), res.resource_path if res.resource_path != "" else "inline"]
			return "<%s>" % value.get_class() if value else "null"
		_:
			return str(value)
