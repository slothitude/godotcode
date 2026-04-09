class_name GCScreenshotTool
extends GCBaseTool
## Capture screenshots of editor viewports for vision-capable AI models


func _init() -> void:
	super._init(
		"Screenshot",
		"Capture a screenshot of the current editor viewport. Returns image data for visual analysis.",
		{
			"viewport": {
				"type": "integer",
				"description": "Viewport index (default 0)"
			},
			"width": {
				"type": "integer",
				"description": "Optional resize width (max 1920)"
			},
			"height": {
				"type": "integer",
				"description": "Optional resize height (max 1080)"
			}
		}
	)
	is_read_only = true


func validate_input(input: Dictionary) -> Dictionary:
	var vp: int = input.get("viewport", 0)
	if vp < 0 or vp > 3:
		return {"valid": false, "error": "viewport index must be 0-3"}
	return {"valid": true}


func execute(input: Dictionary, context: Dictionary) -> Dictionary:
	if not Engine.is_editor_hint():
		return {"success": false, "error": "Screenshot only works in the editor"}

	var vp_index: int = input.get("viewport", 0)

	# Try 3D viewport first
	var viewport := EditorInterface.get_editor_viewport_3d(vp_index)
	var image: Image = null

	if viewport:
		await RenderingServer.frame_post_draw
		image = viewport.get_texture().get_image()

	# Fallback: try to get the 2D viewport
	if image == null:
		var edited_scene := EditorInterface.get_edited_scene_root()
		if edited_scene and edited_scene.get_viewport():
			await RenderingServer.frame_post_draw
			image = edited_scene.get_viewport().get_texture().get_image()

	if image == null:
		return {"success": false, "error": "No viewport available for capture. Open a 3D or 2D viewport."}

	# Resize if requested
	var target_w: int = input.get("width", 0)
	var target_h: int = input.get("height", 0)
	if target_w > 0 or target_h > 0:
		target_w = mini(target_w, 1920)
		target_h = mini(target_h, 1080)
		if target_w == 0:
			target_w = int(image.get_width() * float(target_h) / image.get_height())
		if target_h == 0:
			target_h = int(image.get_height() * float(target_w) / image.get_width())
		image.resize(target_w, target_h)

	# Encode as PNG
	var png_data := image.save_png_to_buffer()
	var base64_str := Marshalls.raw_to_base64(png_data)

	return {
		"success": true,
		"data": "Screenshot captured (%dx%d, %d bytes)" % [image.get_width(), image.get_height(), png_data.size()],
		"is_vision": true,
		"vision_data": base64_str,
		"media_type": "image/png"
	}
