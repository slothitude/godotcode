class_name GCShaderTool
extends GCBaseTool
## Write shaders with live visual feedback — write → apply → screenshot → iterate


func _init() -> void:
	super._init(
		"Shader",
		"Write, apply, preview, and remove shaders on nodes. Write shader code, apply it to a mesh, and get visual feedback.",
		{
			"action": {
				"type": "string",
				"description": "Action: write (save shader file), apply (apply to node), preview (apply + screenshot), remove (restore original)",
				"enum": ["write", "apply", "preview", "remove"]
			},
			"shader_code": {
				"type": "string",
				"description": "Full shader code to write (for write action)"
			},
			"path": {
				"type": "string",
				"description": "Shader file path (e.g. res://shaders/my_shader.gdshader)"
			},
			"node_path": {
				"type": "string",
				"description": "Scene tree node path to apply shader to (MeshInstance3D)"
			},
			"shader_params": {
				"type": "object",
				"description": "Shader uniform parameters to set {name: value}"
			}
		}
	)
	is_read_only = false


func validate_input(input: Dictionary) -> Dictionary:
	var action: String = input.get("action", "")
	if action == "":
		return {"valid": false, "error": "action is required"}
	if action == "write" and not input.has("shader_code"):
		return {"valid": false, "error": "shader_code is required for write action"}
	return {"valid": true}


func check_permissions(input: Dictionary, context: Dictionary) -> Dictionary:
	return {"behavior": "ask", "message": "Shader %s" % input.get("action", "")}


func execute(input: Dictionary, context: Dictionary) -> Dictionary:
	var action: String = input.get("action", "")

	match action:
		"write":
			return _write_shader(input)
		"apply":
			return await _apply_shader(input)
		"preview":
			return await _preview_shader(input)
		"remove":
			return _remove_shader(input)
		_:
			return {"success": false, "error": "Unknown action: %s" % action}


func _write_shader(input: Dictionary) -> Dictionary:
	var path: String = input.get("path", "res://shaders/new_shader.gdshader")
	var code: String = input.get("shader_code", "")

	if code == "":
		return {"success": false, "error": "shader_code is required"}

	if not path.begins_with("res://"):
		path = "res://" + path

	# Ensure directory exists
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)

	var global_path := ProjectSettings.globalize_path(path)
	var file := FileAccess.open(global_path, FileAccess.WRITE)
	if not file:
		return {"success": false, "error": "Cannot write to %s" % path}

	file.store_string(code)
	file.close()

	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()

	return {"success": true, "data": "Shader written to %s (%d bytes)" % [path, code.length()], "path": path}


func _apply_shader(input: Dictionary) -> Dictionary:
	if not Engine.is_editor_hint():
		return {"success": false, "error": "Only works in editor"}

	var path: String = input.get("path", "")
	var node_path: String = input.get("node_path", "")

	if path == "" or node_path == "":
		return {"success": false, "error": "path and node_path are required"}

	var edited_scene := EditorInterface.get_edited_scene_root()
	if not edited_scene:
		return {"success": false, "error": "No scene is currently being edited"}

	var node := edited_scene.get_node_or_null(node_path)
	if not node:
		return {"success": false, "error": "Node not found: %s" % node_path}
	if not node is MeshInstance3D:
		return {"success": false, "error": "Node must be a MeshInstance3D, got %s" % node.get_class()}

	# Load shader
	var shader := load(path) as Shader
	if not shader:
		# Force reimport
		if Engine.is_editor_hint():
			EditorInterface.get_resource_filesystem().scan()
			await Engine.get_main_loop().process_frame
			await Engine.get_main_loop().process_frame
			shader = load(path) as Shader
	if not shader:
		return {"success": false, "error": "Failed to load shader: %s" % path}

	# Store original material for restore
	var mat := ShaderMaterial.new()
	mat.shader = shader

	# Set shader params if provided
	var params: Dictionary = input.get("shader_params", {})
	for key in params:
		mat.set_shader_parameter(key, params[key])

	# Save original material reference on the node metadata
	var mesh_inst: MeshInstance3D = node
	mesh_inst.set_meta("_original_material", mesh_inst.get_surface_override_material(0))
	mesh_inst.set_surface_override_material(0, mat)

	return {"success": true, "data": "Shader applied to %s" % node_path}


func _preview_shader(input: Dictionary) -> Dictionary:
	## Apply + await frame + screenshot → return vision result
	var apply_result := await _apply_shader(input)
	if not apply_result.get("success", false):
		return apply_result

	# Wait for render
	await RenderingServer.frame_post_draw
	await Engine.get_main_loop().process_frame
	await RenderingServer.frame_post_draw

	# Capture screenshot
	var viewport := EditorInterface.get_editor_viewport_3d(0)
	if not viewport:
		return {"success": true, "data": "Shader applied but no viewport available for preview"}

	var image := viewport.get_texture().get_image()
	if not image:
		return {"success": true, "data": "Shader applied but screenshot failed"}

	if image.get_width() > 1280:
		var scale := 1280.0 / image.get_width()
		image.resize(1280, int(image.get_height() * scale))

	var png_data := image.save_png_to_buffer()
	var base64_str := Marshalls.raw_to_base64(png_data)

	return {
		"success": true,
		"data": "Shader preview (%dx%d)" % [image.get_width(), image.get_height()],
		"is_vision": true,
		"vision_data": base64_str,
		"media_type": "image/png"
	}


func _remove_shader(input: Dictionary) -> Dictionary:
	if not Engine.is_editor_hint():
		return {"success": false, "error": "Only works in editor"}

	var node_path: String = input.get("node_path", "")
	if node_path == "":
		return {"success": false, "error": "node_path is required"}

	var edited_scene := EditorInterface.get_edited_scene_root()
	if not edited_scene:
		return {"success": false, "error": "No scene being edited"}

	var node := edited_scene.get_node_or_null(node_path)
	if not node:
		return {"success": false, "error": "Node not found: %s" % node_path}

	var mesh_inst: MeshInstance3D = node

	# Restore original material
	if mesh_inst.has_meta("_original_material"):
		var original = mesh_inst.get_meta("_original_material")
		mesh_inst.set_surface_override_material(0, original)
		mesh_inst.remove_meta("_original_material")
		return {"success": true, "data": "Shader removed, original material restored on %s" % node_path}
	else:
		mesh_inst.set_surface_override_material(0, null)
		return {"success": true, "data": "Shader removed from %s" % node_path}
