extends SceneTree
## Test NVIDIA image generation through GCImageGenTool with real API call

var _passed: int = 0
var _failed: int = 0


func _init() -> void:
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	print("\n========== NVIDIA Image Gen Live Test ==========\n")
	await _test_nvidia_gen()
	print("\n========== Results: %d passed, %d failed ==========" % [_passed, _failed])
	quit()


func _test_nvidia_gen() -> void:
	_log("Test: NVIDIA Flux.1-schnell direct API call")

	var url := "https://ai.api.nvidia.com/v1/genai/black-forest-labs/flux.1-schnell"
	var api_key := "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"
	var body := JSON.stringify({
		"prompt": "a simple coffee shop interior",
		"width": 1024,
		"height": 1024,
		"seed": 0,
		"steps": 4
	})

	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer %s" % api_key,
		"Accept: application/json"
	])

	var http := HTTPRequest.new()
	var root: Node = (Engine.get_main_loop() as SceneTree).root
	root.add_child(http)
	http.timeout = 60.0

	var state: Dictionary = {"output": {}, "done": false}

	var err := http.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		_assert(false, "Request failed: %s" % error_string(err))
		if http.is_inside_tree():
			http.queue_free()
		return

	_log("    Waiting for NVIDIA response...")
	http.request_completed.connect(func(_result, code: int, _headers, body_bytes: PackedByteArray):
		_log("    HTTP response code: %d, body size: %d" % [code, body_bytes.size()])
		var text := body_bytes.get_string_from_utf8()
		var json := JSON.new()
		if json.parse(text) == OK:
			state["output"] = json.data
		else:
			state["output"] = {"_raw": text.left(200)}
		state["done"] = true
	)

	var start := Time.get_ticks_msec()
	while not state["done"]:
		if Time.get_ticks_msec() - start > 65000:
			_assert(false, "Timed out waiting for response")
			if http.is_inside_tree():
				http.queue_free()
			return
		await Engine.get_main_loop().process_frame

	if http.is_inside_tree():
		http.queue_free()

	var output: Dictionary = state["output"]

	if output.has("_raw"):
		_assert(false, "Non-JSON response: %s" % str(output["_raw"]))
		return

	if output.has("detail"):
		_assert(false, "API error: %s" % str(output["detail"]))
		return

	_assert(output.has("artifacts"), "Response has artifacts array")

	var artifacts = output.get("artifacts", [])
	_assert(artifacts.size() > 0, "Has at least one artifact")

	var image_data: String = str(artifacts[0].get("base64", ""))
	_assert(image_data.length() > 1000, "Has base64 image data (%d chars)" % image_data.length())

	# Decode and verify
	var image_bytes := Marshalls.base64_to_raw(image_data)
	_assert(image_bytes.size() > 0, "Decoded to bytes (%d)" % image_bytes.size())

	var is_jpg := image_bytes.size() >= 3 and image_bytes[0] == 0xFF and image_bytes[1] == 0xD8 and image_bytes[2] == 0xFF
	_assert(is_jpg, "Magic bytes confirm JPEG format")

	var image := Image.new()
	err = image.load_jpg_from_buffer(image_bytes)
	_assert(err == OK, "JPEG loads successfully")
	_assert(image.get_width() > 0 and image.get_height() > 0, "Valid dimensions %dx%d" % [image.get_width(), image.get_height()])
	_log("    Generated: %dx%d, %d bytes" % [image.get_width(), image.get_height(), image_bytes.size()])


func _log(text: String) -> void:
	print("  " + text)


func _assert(condition: bool, description: String) -> void:
	if condition:
		_passed += 1
		print("    PASS: %s" % description)
	else:
		_failed += 1
		push_error("    FAIL: %s" % description)
