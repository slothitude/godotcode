class_name GCImageFetchTool
extends GCBaseTool
## Fetch an image from a URL and return it as a vision result for display in chat


func _init() -> void:
	super._init(
		"ImageFetch",
		"Fetch an image from a URL and display it in the chat. Supports PNG, JPEG, and WebP images.",
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

	var fetch_result: Dictionary = await _fetch_bytes(url)
	var http_code: int = fetch_result.get("code", 0)
	var image_bytes: PackedByteArray = fetch_result.get("data", PackedByteArray())
	var content_type: String = fetch_result.get("content_type", "")

	if image_bytes.is_empty():
		if http_code > 0:
			return {"success": false, "error": "HTTP %d returned empty response from: %s" % [http_code, url]}
		return {"success": false, "error": "Failed to fetch image from: %s" % url}

	# Reject obvious non-image responses
	if content_type.find("text/") != -1 or content_type.find("html") != -1:
		return {"success": false, "error": "URL returned %s (not an image). Need a direct image link." % content_type}

	# Try loading the image, trying all formats
	var load_result := _load_image(image_bytes, content_type)
	if load_result.get("error", "") != "":
		return {"success": false, "error": load_result["error"]}

	var image: Image = load_result["image"]
	var media_type: String = load_result["media_type"]

	var base64_str := Marshalls.raw_to_base64(image_bytes)
	var desc := "Image from %s (%dx%d, %d bytes)" % [url, image.get_width(), image.get_height(), image_bytes.size()]

	return {
		"success": true,
		"data": desc,
		"is_vision": true,
		"vision_data": base64_str,
		"media_type": media_type
	}


func _fetch_bytes(url: String) -> Dictionary:
	var http := HTTPRequest.new()
	var root: Node = (Engine.get_main_loop() as SceneTree).root
	root.add_child(http)
	http.timeout = 30.0

	var state: Dictionary = {"data": PackedByteArray(), "code": 0, "content_type": "", "done": false}

	var headers := PackedStringArray([
		"User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
		"Accept: image/*,*/*;q=0.8"
	])
	var err := http.request(url, headers, HTTPClient.METHOD_GET, "")
	if err != OK:
		if http.is_inside_tree():
			http.queue_free()
		return {}

	http.request_completed.connect(func(_result, code: int, response_headers: PackedStringArray, body: PackedByteArray):
		state["code"] = code
		state["data"] = body
		# Extract content-type from response headers
		for h in response_headers:
			if h.to_lower().begins_with("content-type:"):
				state["content_type"] = h.substr(len("content-type:")).strip_edges().to_lower()
				break
		state["done"] = true
	)

	var start := Time.get_ticks_msec()
	while not state["done"]:
		if Time.get_ticks_msec() - start > 35000:
			break
		await Engine.get_main_loop().process_frame

	if http.is_inside_tree():
		http.queue_free()

	return state


func _load_image(image_bytes: PackedByteArray, content_type: String) -> Dictionary:
	# Detect format from magic bytes (most reliable)
	# PNG: 89 50 4E 47
	# JPEG: FF D8 FF
	# WebP: 52 49 46 46 ... 57 45 42 50
	var is_png := image_bytes.size() >= 4 and image_bytes[0] == 0x89 and image_bytes[1] == 0x50
	var is_jpg := image_bytes.size() >= 3 and image_bytes[0] == 0xFF and image_bytes[1] == 0xD8 and image_bytes[2] == 0xFF
	var is_webp := image_bytes.size() >= 12 and \
		image_bytes[0] == 0x52 and image_bytes[1] == 0x49 and \
		image_bytes[2] == 0x46 and image_bytes[3] == 0x46 and \
		image_bytes[8] == 0x57 and image_bytes[9] == 0x45 and \
		image_bytes[10] == 0x42 and image_bytes[11] == 0x50

	var image := Image.new()
	var err := OK
	var media_type := "image/png"

	if is_png:
		err = image.load_png_from_buffer(image_bytes)
		media_type = "image/png"
	elif is_jpg:
		err = image.load_jpg_from_buffer(image_bytes)
		media_type = "image/jpeg"
	elif is_webp:
		err = image.load_webp_from_buffer(image_bytes)
		media_type = "image/webp"
	else:
		# Unknown magic bytes — try all formats
		err = image.load_png_from_buffer(image_bytes)
		if err != OK:
			err = image.load_jpg_from_buffer(image_bytes)
			if err == OK:
				media_type = "image/jpeg"
		if err != OK:
			err = image.load_webp_from_buffer(image_bytes)
			if err == OK:
				media_type = "image/webp"

	if err != OK:
		var hint := ""
		if image_bytes.size() < 4:
			hint = " Response too small (%d bytes), likely an error page." % image_bytes.size()
		elif image_bytes.size() > 0:
			var preview := ""
			for i in range(mini(image_bytes.size(), 50)):
				preview += "%02x " % image_bytes[i]
			hint = " First bytes: [%s]" % preview.strip_edges()
		return {"error": "Downloaded data is not a valid image (error %d).%s" % [err, hint]}

	return {"image": image, "media_type": media_type}
