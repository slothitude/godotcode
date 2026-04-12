class_name GCAssetPipelineTool
extends GCBaseTool
## Generate → Import → Place → Iterate closed-loop creative workflow


var _asset_manager: GCAssetManager


func _init() -> void:
	super._init(
		"AssetPipeline",
		"Import images, apply textures to nodes, create materials, and manage project assets. Actions: import_image, apply_texture, create_material, list_assets.",
		{
			"action": {
				"type": "string",
				"description": "Action: import_image, apply_texture, create_material, list_assets",
				"enum": ["import_image", "apply_texture", "create_material", "list_assets"]
			},
			"base64_data": {
				"type": "string",
				"description": "Base64-encoded image data (for import_image)"
			},
			"path": {
				"type": "string",
				"description": "Destination path in project (e.g. res://textures/my_image.png)"
			},
			"media_type": {
				"type": "string",
				"description": "Image MIME type: image/png or image/jpeg (default image/png)"
			},
			"node_path": {
				"type": "string",
				"description": "Scene tree node path (for apply_texture)"
			},
			"property": {
				"type": "string",
				"description": "Property name to set (for apply_texture, default: texture)"
			},
			"resource_path": {
				"type": "string",
				"description": "Resource path to apply (for apply_texture)"
			},
			"name": {
				"type": "string",
				"description": "Material name (for create_material)"
			},
			"albedo_color": {
				"type": "string",
				"description": "Albedo color hex (for create_material, e.g. '#ff0000')"
			},
			"metallic": {
				"type": "number",
				"description": "Metallic value 0-1 (for create_material)"
			},
			"roughness": {
				"type": "number",
				"description": "Roughness value 0-1 (for create_material)"
			}
		}
	)
	is_read_only = false


func validate_input(input: Dictionary) -> Dictionary:
	var action: String = input.get("action", "")
	if action == "":
		return {"valid": false, "error": "action is required"}
	return {"valid": true}


func check_permissions(input: Dictionary, context: Dictionary) -> Dictionary:
	return {"behavior": "ask", "message": "Asset pipeline: %s" % input.get("action", "")}


func execute(input: Dictionary, context: Dictionary) -> Dictionary:
	if not _asset_manager:
		_asset_manager = context.get("asset_manager")
	if not _asset_manager:
		_asset_manager = GCAssetManager.new()

	var action: String = input.get("action", "")

	match action:
		"import_image":
			return _import_image(input)
		"apply_texture":
			return _apply_texture(input)
		"create_material":
			return _create_material(input)
		"list_assets":
			return _list_assets()
		_:
			return {"success": false, "error": "Unknown action: %s" % action}


func _import_image(input: Dictionary) -> Dictionary:
	var base64: String = input.get("base64_data", "")
	var path: String = input.get("path", "res://textures/imported.png")
	var media_type: String = input.get("media_type", "image/png")

	if base64 == "":
		return {"success": false, "error": "base64_data is required for import_image"}

	# Check for recent vision data from context
	if base64 == "<last_vision>" and input.has("_context"):
		var ctx: Dictionary = input["_context"]
		base64 = ctx.get("last_vision_data", "")

	return _asset_manager.import_image(base64, path, media_type)


func _apply_texture(input: Dictionary) -> Dictionary:
	var node_path: String = input.get("node_path", "")
	var property: String = input.get("property", "texture")
	var resource_path: String = input.get("resource_path", "")

	if node_path == "" or resource_path == "":
		return {"success": false, "error": "node_path and resource_path are required"}

	return _asset_manager.apply_to_node(node_path, property, resource_path)


func _create_material(input: Dictionary) -> Dictionary:
	var config := {
		"name": input.get("name", "new_material"),
	}
	if input.has("albedo_color"):
		config["albedo_color"] = input.albedo_color
	if input.has("metallic"):
		config["metallic"] = input.metallic
	if input.has("roughness"):
		config["roughness"] = input.roughness

	var path := _asset_manager.create_material(config)
	if path == "":
		return {"success": false, "error": "Failed to create material"}

	# Apply to node if specified
	if input.has("node_path"):
		var result := _asset_manager.apply_to_node(input.node_path, "material_override", path)
		if result.get("success", false):
			return {"success": true, "data": "Material created at %s and applied to %s" % [path, input.node_path]}

	return {"success": true, "data": "Material created at %s" % path, "path": path}


func _list_assets() -> Dictionary:
	if not Engine.is_editor_hint():
		return {"success": false, "error": "Only works in editor"}

	var files: Array = []
	_scan_dir("res://", files, ["*.png", "*.jpg", "*.tres", "*.glb", "*.obj", "*.wav", "*.ogg"])
	files = files.slice(0, 50)

	if files.is_empty():
		return {"success": true, "data": "No assets found in project"}

	return {"success": true, "data": "Assets:\n" + "\n".join(files)}


func _scan_dir(path: String, results: Array, patterns: Array, depth: int = 0) -> void:
	if depth > 4:
		return
	var da := DirAccess.open(path)
	if not da:
		return
	da.list_dir_begin()
	var f := da.get_next()
	while f != "":
		if f.begins_with(".") or f == ".git" or f == ".godot":
			f = da.get_next()
			continue
		var full := path + f
		if da.current_is_dir():
			_scan_dir(full + "/", results, patterns, depth + 1)
		else:
			for p in patterns:
				if f.ends_with(p.right(p.length() - 1)):
					results.append(full)
					break
		f = da.get_next()
	da.list_dir_end()
