class_name GCVisualDiff
extends RefCounted
## Auto-capture before/after screenshots around scene mutations


var _before_image: String = ""  # base64
var _after_image: String = ""   # base64
var _last_tool_name: String = ""
var _last_tool_input: Dictionary = {}


func capture_before(tool_name: String, tool_input: Dictionary) -> void:
	## Screenshot current viewport before a mutation
	if not Engine.is_editor_hint():
		return

	_before_image = ""
	_after_image = ""
	_last_tool_name = tool_name
	_last_tool_input = tool_input

	var viewport := EditorInterface.get_editor_viewport_3d(0)
	if not viewport:
		# Try 2D viewport
		var edited_scene := EditorInterface.get_edited_scene_root()
		if edited_scene and edited_scene.get_viewport():
			viewport = edited_scene.get_viewport()

	if viewport:
		var image := viewport.get_texture().get_image()
		if image:
			if image.get_width() > 960:
				var scale := 960.0 / image.get_width()
				image.resize(960, int(image.get_height() * scale))
			_before_image = Marshalls.raw_to_base64(image.save_png_to_buffer())


func capture_after() -> Dictionary:
	## Screenshot after mutation, return both images
	if not Engine.is_editor_hint():
		return {"has_diff": false}

	var viewport := EditorInterface.get_editor_viewport_3d(0)
	if not viewport:
		var edited_scene := EditorInterface.get_edited_scene_root()
		if edited_scene and edited_scene.get_viewport():
			viewport = edited_scene.get_viewport()

	if viewport:
		var image := viewport.get_texture().get_image()
		if image:
			if image.get_width() > 960:
				var scale := 960.0 / image.get_width()
				image.resize(960, int(image.get_height() * scale))
			_after_image = Marshalls.raw_to_base64(image.save_png_to_buffer())

	return {
		"has_diff": _before_image != "" and _after_image != "",
		"before": _before_image,
		"after": _after_image,
		"tool_name": _last_tool_name,
	}


func get_before_image() -> String:
	return _before_image


func get_after_image() -> String:
	return _after_image


func has_before() -> bool:
	return _before_image != ""
