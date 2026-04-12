class_name GCAssetManager
extends RefCounted
## Generate → Import → Place → Iterate asset workflow


func import_image(base64_data: String, path: String, media_type: String) -> Dictionary:
	## Decode base64 image, save to project, trigger resource scan
	if base64_data == "":
		return {"success": false, "error": "No image data provided"}

	# Ensure path is res://
	if not path.begins_with("res://"):
		path = "res://" + path

	# Determine format
	var ext := ".png"
	if media_type == "image/jpeg" or media_type == "image/jpg":
		ext = ".jpg"
	if not path.ends_with(ext) and not path.ends_with(".png") and not path.ends_with(".jpg"):
		path += ext

	# Decode base64
	var raw_data := Marshalls.base64_to_raw(base64_data)
	if raw_data.size() == 0:
		return {"success": false, "error": "Failed to decode base64 data"}

	# Create image from buffer
	var image := Image.new()
	var err := Error.OK
	if ext == ".jpg":
		err = image.load_jpg_from_buffer(raw_data)
	else:
		err = image.load_png_from_buffer(raw_data)

	if err != OK:
		return {"success": false, "error": "Failed to load image from buffer (error %d)" % err}

	# Save to project
	var global_path := ProjectSettings.globalize_path(path)
	var save_err := image.save_png(global_path) if ext == ".png" else image.save_jpg(global_path)
	if save_err != OK:
		return {"success": false, "error": "Failed to save image to %s" % path}

	# Trigger resource filesystem scan
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()

	return {"success": true, "data": "Image imported to %s (%dx%d)" % [path, image.get_width(), image.get_height()], "path": path}


func apply_to_node(node_path: String, property: String, resource_path: String) -> Dictionary:
	## Load a resource and apply it to a node property
	if not Engine.is_editor_hint():
		return {"success": false, "error": "Only works in editor"}

	var edited_scene := EditorInterface.get_edited_scene_root()
	if not edited_scene:
		return {"success": false, "error": "No scene is currently being edited"}

	var node := edited_scene.get_node_or_null(node_path)
	if not node:
		return {"success": false, "error": "Node not found: %s" % node_path}

	# Load resource
	var resource := load(resource_path)
	if not resource:
		return {"success": false, "error": "Failed to load resource: %s" % resource_path}

	# Set property
	if not property in node:
		return {"success": false, "error": "Property '%s' not found on %s" % [property, node.get_class()]}

	node.set(property, resource)
	return {"success": true, "data": "Applied %s to %s.%s" % [resource_path.get_file(), node_path, property]}


func create_material(config: Dictionary) -> String:
	## Create a StandardMaterial3D as .tres, return path
	var name: String = config.get("name", "new_material")
	var path: String = "res://%s.tres" % name

	var mat := StandardMaterial3D.new()

	# Apply common properties
	if config.has("albedo_color"):
		mat.albedo_color = Color(str(config.albedo_color))
	if config.has("albedo_texture"):
		var tex := load(str(config.albedo_texture))
		if tex:
			mat.albedo_texture = tex
	if config.has("metallic"):
		mat.metallic = float(config.metallic)
	if config.has("roughness"):
		mat.roughness = float(config.roughness)
	if config.has("emission"):
		mat.emission_enabled = true
		mat.emission = Color(str(config.emission))
	if config.has("normal_texture"):
		var tex := load(str(config.normal_texture))
		if tex:
			mat.normal_texture = tex
			mat.normal_enabled = true

	var err := ResourceSaver.save(mat, path)
	if err != OK:
		return ""

	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()

	return path
