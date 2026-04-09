class_name GCNodePropertyTool
extends GCBaseTool
## Get, set, and list properties on live scene tree nodes


func _init() -> void:
	super._init(
		"NodeProperty",
		"Get, set, or list properties on live nodes in the edited scene. Use node paths like 'RootName/ChildName'.",
		{
			"action": {
				"type": "string",
				"description": "'get' to read a property, 'set' to write a property, 'list_properties' to list all properties",
				"enum": ["get", "set", "list_properties"]
			},
			"node_path": {
				"type": "string",
				"description": "Path to the node (e.g. 'Root/Player/Sprite3D')"
			},
			"property": {
				"type": "string",
				"description": "Property name for get/set"
			},
			"value": {
				"type": "string",
				"description": "Value to set (as string, will be parsed to correct type)"
			}
		}
	)
	is_read_only = false


func validate_input(input: Dictionary) -> Dictionary:
	var action: String = input.get("action", "")
	if action == "":
		return {"valid": false, "error": "action is required"}
	if action not in ["get", "set", "list_properties"]:
		return {"valid": false, "error": "Invalid action: %s" % action}
	if not input.has("node_path"):
		return {"valid": false, "error": "node_path is required"}
	if action in ["get", "set"] and not input.has("property"):
		return {"valid": false, "error": "property is required for get/set"}
	if action == "set" and not input.has("value"):
		return {"valid": false, "error": "value is required for set"}
	return {"valid": true}


func check_permissions(input: Dictionary, context: Dictionary) -> Dictionary:
	var action: String = input.get("action", "")
	# Read actions are safe
	if action in ["get", "list_properties"]:
		return {"behavior": "allow"}
	# Set requires approval
	return {"behavior": "ask", "message": "NodeProperty 'set' modifies node: %s.%s" % [input.get("node_path", ""), input.get("property", "")]}


func execute(input: Dictionary, context: Dictionary) -> Dictionary:
	if not Engine.is_editor_hint():
		return {"success": false, "error": "NodeProperty only works in the editor"}

	var node := _get_node(input.get("node_path", ""))
	if node == null:
		return {"success": false, "error": "Node not found: %s" % input.get("node_path", "")}

	var action: String = input.get("action", "")

	match action:
		"get":
			return _get_property(node, input.get("property", ""))
		"set":
			return _set_property(node, input.get("property", ""), input.get("value", ""))
		"list_properties":
			return _list_properties(node)
		_:
			return {"success": false, "error": "Unknown action: %s" % action}


func _get_node(path: String) -> Node:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return null

	# Handle bare root name or full path
	if path == root.name or path == "/":
		return root

	# Try as child path
	if root.has_node(path):
		return root.get_node(path)

	# Try with root name prepended (user might give absolute path)
	var full_path := root.name + "/" + path
	if root.has_node(full_path):
		return root.get_node(full_path)

	# Try scene tree directly
	var tree := root.get_tree()
	if tree and tree.root.has_node(path):
		return tree.root.get_node(path)

	return null


func _get_property(node: Node, property: String) -> Dictionary:
	if not property in node:
		return {"success": false, "error": "Property '%s' not found on %s (%s)" % [property, node.name, node.get_class()]}
	var value = node.get(property)
	return {"success": true, "data": "%s.%s = %s" % [node.name, property, _format_value(value)]}


func _set_property(node: Node, property: String, value_str: String) -> Dictionary:
	if not property in node:
		return {"success": false, "error": "Property '%s' not found on %s (%s)" % [property, node.name, node.get_class()]}

	var parsed = _parse_value(value_str, node, property)
	if parsed == null:
		return {"success": false, "error": "Could not parse value: %s" % value_str}

	var old_value = node.get(property)
	node.set(property, parsed)
	var new_value = node.get(property)

	return {"success": true, "data": "Set %s.%s: %s -> %s" % [node.name, property, _format_value(old_value), _format_value(new_value)]}


func _list_properties(node: Node) -> Dictionary:
	var props := node.get_property_list()
	var lines: Array = []
	var relevant_usage := PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_STORAGE

	for p in props:
		var usage: int = p.get("usage", 0)
		if usage & relevant_usage:
			var name: String = p.get("name", "")
			var type: int = p.get("type", 0)
			var value = node.get(name)
			lines.append("%s (%s) = %s" % [name, type_string(type), _format_value(value)])

	return {"success": true, "data": "## Properties of %s [%s]\n%s" % [node.name, node.get_class(), "\n".join(lines)]}


func _format_value(value) -> String:
	if value == null:
		return "null"
	var t := typeof(value)
	match t:
		TYPE_VECTOR2:
			var v: Vector2 = value
			return "Vector2(%s, %s)" % [v.x, v.y]
		TYPE_VECTOR3:
			var v: Vector3 = value
			return "Vector3(%s, %s, %s)" % [v.x, v.y, v.z]
		TYPE_COLOR:
			var c: Color = value
			return "Color(%s, %s, %s, %s)" % [c.r, c.g, c.b, c.a]
		TYPE_RECT2:
			var r: Rect2 = value
			return "Rect2(%s, %s, %s, %s)" % [r.position.x, r.position.y, r.size.x, r.size.y]
		TYPE_QUATERNION:
			var q: Quaternion = value
			return "Quaternion(%s, %s, %s, %s)" % [q.x, q.y, q.z, q.w]
		TYPE_ARRAY:
			return str(value)
		TYPE_DICTIONARY:
			return str(value)
		TYPE_OBJECT:
			if value is Resource:
				return "<%s: %s>" % [value.get_class(), value.resource_path if value.resource_path != "" else value.get_instance_id()]
			return "<%s>" % value.get_class() if value else "null"
		_:
			return str(value)


func _parse_value(value_str: String, node: Node, property: String):
	# Try to determine expected type from property list
	var expected_type: int = TYPE_NIL
	var props := node.get_property_list()
	for p in props:
		if p.get("name", "") == property:
			expected_type = p.get("type", TYPE_NIL)
			break

	# Type-specific parsing
	value_str = value_str.strip_edges()

	match expected_type:
		TYPE_BOOL:
			if value_str.to_lower() in ["true", "1", "yes"]:
				return true
			if value_str.to_lower() in ["false", "0", "no"]:
				return false
		TYPE_INT:
			if value_str.is_valid_int():
				return value_str.to_int()
		TYPE_FLOAT:
			if value_str.is_valid_float():
				return value_str.to_float()
		TYPE_STRING:
			return value_str
		TYPE_VECTOR2:
			return _parse_vector2(value_str)
		TYPE_VECTOR3:
			return _parse_vector3(value_str)
		TYPE_COLOR:
			return _parse_color(value_str)
		TYPE_RECT2:
			return _parse_rect2(value_str)
		TYPE_QUATERNION:
			return _parse_quaternion(value_str)

	# Fallback: use Godot's built-in variant parser
	var parsed = str_to_var(value_str)
	if parsed != null:
		return parsed

	# If expected type is string, just return as-is
	if expected_type == TYPE_STRING:
		return value_str

	return null


func _parse_vector2(s: String) -> Variant:
	s = s.strip_edges().trim_prefix("Vector2").trim_prefix("(").trim_suffix(")")
	var parts := s.split(",")
	if parts.size() == 2:
		return Vector2(parts[0].strip_edges().to_float(), parts[1].strip_edges().to_float())
	return null


func _parse_vector3(s: String) -> Variant:
	s = s.strip_edges().trim_prefix("Vector3").trim_prefix("(").trim_suffix(")")
	var parts := s.split(",")
	if parts.size() == 3:
		return Vector3(parts[0].strip_edges().to_float(), parts[1].strip_edges().to_float(), parts[2].strip_edges().to_float())
	return null


func _parse_color(s: String) -> Variant:
	s = s.strip_edges().trim_prefix("Color").trim_prefix("(").trim_suffix(")")
	var parts := s.split(",")
	match parts.size():
		3:
			return Color(parts[0].strip_edges().to_float(), parts[1].strip_edges().to_float(), parts[2].strip_edges().to_float())
		4:
			return Color(parts[0].strip_edges().to_float(), parts[1].strip_edges().to_float(), parts[2].strip_edges().to_float(), parts[3].strip_edges().to_float())
		1:
			# Try as hex color
			return Color.html(parts[0].strip_edges())
	return null


func _parse_rect2(s: String) -> Variant:
	s = s.strip_edges().trim_prefix("Rect2").trim_prefix("(").trim_suffix(")")
	var parts := s.split(",")
	if parts.size() == 4:
		return Rect2(parts[0].strip_edges().to_float(), parts[1].strip_edges().to_float(), parts[2].strip_edges().to_float(), parts[3].strip_edges().to_float())
	return null


func _parse_quaternion(s: String) -> Variant:
	s = s.strip_edges().trim_prefix("Quaternion").trim_prefix("(").trim_suffix(")")
	var parts := s.split(",")
	if parts.size() == 4:
		return Quaternion(parts[0].strip_edges().to_float(), parts[1].strip_edges().to_float(), parts[2].strip_edges().to_float(), parts[3].strip_edges().to_float())
	return null
