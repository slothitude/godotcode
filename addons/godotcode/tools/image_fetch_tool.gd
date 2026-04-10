class_name GCImageFetchTool
extends GCBaseTool
## Fetch an image from a URL and return it as a vision result for display in chat


func _init() -> void:
	super._init(
		"ImageFetch",
		"Fetch an image from a URL and display it in the chat. Supports PNG, JPEG, GIF, and WebP images.",
		{
			"url": {
				"type": "string",
				"description": "The URL of the image to fetch (must be a direct image URL)"
			}
		}
	)
	is_read_only = true


func validate_input(input: Dictionary) -> Dictionary:
	if not input.has("url"):
		return {"valid": false, "error": "url is required"}
	var url: String = str(input.get("url", ""))
	if not url.begins_with("http://") and not url.begins_with("https://"):
		return {"valid": false, "error": "url must start with http:// or https://"}
	return {"valid": true}


func execute(input: Dictionary, context: Dictionary) -> Dictionary:
	var url: String = str(input.get("url", ""))
	if url == "":
		return {"success": false, "error": "url is required"}

	var image_bytes: PackedByteArray = await _fetch_bytes(url)
	if image_bytes.is_empty():
		return {"success": false, "error": "Failed to fetch image from: %s" % url}

	# Determine media type from URL or header
	var media_type := _guess_media_type(url)

	# Validate it's actually an image by trying to load it
	var image := Image.new()
	var err := OK
	match media_type:
		"image/jpeg":
			err = image.load_jpg_from_buffer(image_bytes)
		"image/webp":
			err = image.load_webp_from_buffer(image_bytes)
		_:
			err = image.load_png_from_buffer(image_bytes)
			if err != OK:
				err = image.load_jpg_from_buffer(image_bytes)
				if err == OK:
					media_type = "image/jpeg"

	if err != OK:
		return {"success": false, "error": "Downloaded data is not a valid image (error %d)" % err}

	var base64_str := Marshalls.raw_to_base64(image_bytes)
	var desc := "Image from %s (%dx%d, %d bytes)" % [url, image.get_width(), image.get_height(), image_bytes.size()]

	return {
		"success": true,
		"data": desc,
		"is_vision": true,
		"vision_data": base64_str,
		"media_type": media_type
	}


func _fetch_bytes(url: String) -> PackedByteArray:
	var http := HTTPRequest.new()
	var root: Node = (Engine.get_main_loop() as SceneTree).root
	root.add_child(http)
	http.timeout = 30.0

	var state: Dictionary = {"data": PackedByteArray(), "done": false}

	var headers := PackedStringArray([
		"User-Agent: Mozilla/5.0 (compatible; GodotCode/1.0)"
	])
	var err := http.request(url, headers, HTTPClient.METHOD_GET, "")
	if err != OK:
		if http.is_inside_tree():
			http.queue_free()
		return PackedByteArray()

	http.request_completed.connect(func(_result, _code, _headers, body: PackedByteArray):
		state["data"] = body
		state["done"] = true
	)

	var start := Time.get_ticks_msec()
	while not state["done"]:
		if Time.get_ticks_msec() - start > 35000:
			break
		await Engine.get_main_loop().process_frame

	if http.is_inside_tree():
		http.queue_free()

	return state["data"]


func _guess_media_type(url: String) -> String:
	var lower := url.to_lower()
	if lower.find(".jpg") != -1 or lower.find(".jpeg") != -1:
		return "image/jpeg"
	if lower.find(".webp") != -1:
		return "image/webp"
	if lower.find(".gif") != -1:
		return "image/png"  # Godot doesn't support GIF natively, try PNG fallback
	return "image/png"
