extends SceneTree
## Integration test: fetch a real image from the web and verify the full vision pipeline

var _passed: int = 0
var _failed: int = 0
var _ImageFetch: GDScript
var _ImageGen: GDScript
var _ConversationHistory: GDScript
var _QueryEngine: GDScript
var _ToolRegistry: GDScript
var _BaseTool: GDScript
var _Settings: GDScript


func _init() -> void:
	_ImageFetch = load("res://addons/godotcode/tools/image_fetch_tool.gd")
	_ImageGen = load("res://addons/godotcode/tools/image_gen_tool.gd")
	_ConversationHistory = load("res://addons/godotcode/core/conversation_history.gd")
	_QueryEngine = load("res://addons/godotcode/core/query_engine.gd")
	_ToolRegistry = load("res://addons/godotcode/core/tool_registry.gd")
	_BaseTool = load("res://addons/godotcode/tools/base_tool.gd")
	_Settings = load("res://addons/godotcode/core/settings.gd")

	# Defer until scene tree root is available
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	print("\n========== Image Fetch Integration Tests ==========\n")
	await _run_tests()
	print("\n========== Results: %d passed, %d failed ==========" % [_passed, _failed])
	quit()


func _run_tests() -> void:
	test_image_fetch_validation()
	test_image_fetch_real_url()
	test_vision_pipeline_end_to_end()
	test_image_display_with_real_image()


func test_image_fetch_validation() -> void:
	_log("Test: ImageFetch input validation")
	var tool := _ImageFetch.new()
	var result: Dictionary = tool.validate_input({})
	_assert(not result["valid"], "Missing url rejected")
	result = tool.validate_input({"url": "ftp://bad.com/img.png"})
	_assert(not result["valid"], "Non-http URL rejected")
	result = tool.validate_input({"url": "https://example.com/img.png"})
	_assert(result["valid"], "Valid https URL accepted")
	result = tool.validate_input({"url": "http://example.com/img.png"})
	_assert(result["valid"], "Valid http URL accepted")


func test_image_fetch_real_url() -> void:
	_log("Test: ImageFetch real URL download")
	var tool := _ImageFetch.new()
	# Use a well-known, stable image URL
	var result = await tool.execute({"url": "https://httpbin.org/image/png"}, {})
	if result.get("success", false):
		_assert(true, "Image fetch succeeded")
		_assert(result.get("is_vision") == true, "Result is vision")
		_assert(str(result.get("media_type", "")) == "image/png", "Media type is image/png")
		var vision_data: String = str(result.get("vision_data", ""))
		_assert(vision_data.length() > 100, "Has substantial base64 data (%d chars)" % vision_data.length())
		_assert(str(result.get("data", "")).find("bytes") != -1, "Description includes size info")

		# Verify we can decode the base64 back to an image
		var decoded := Marshalls.base64_to_raw(vision_data)
		_assert(decoded.size() > 0, "Base64 decodes to bytes")
		var img := Image.new()
		var err := img.load_png_from_buffer(decoded)
		_assert(err == OK, "Decoded bytes load as valid PNG image")
		_assert(img.get_width() > 0 and img.get_height() > 0, "Image has valid dimensions (%dx%d)" % [img.get_width(), img.get_height()])
		_log("    Downloaded image: %dx%d, %d bytes base64" % [img.get_width(), img.get_height(), vision_data.length()])
	else:
		_assert(false, "Image fetch failed: %s (network may be unavailable)" % str(result.get("error", "")))


func test_vision_pipeline_end_to_end() -> void:
	_log("Test: Full vision pipeline (tool -> signal -> history)")
	var registry := _ToolRegistry.new()
	registry.register(_ImageFetch.new())
	registry.register(_ImageGen.new())

	_assert(registry.has_tool("ImageFetch"), "ImageFetch registered")
	_assert(registry.has_tool("ImageGen"), "ImageGen registered")

	# Simulate what the query engine does when a vision tool returns
	var history := _ConversationHistory.new()
	history.add_user_message("Show me an image")

	# Simulate a vision tool result being stored
	var fake_base64 := Marshalls.raw_to_base64(PackedByteArray([0x89, 0x50, 0x4E, 0x47]))
	var vision_blocks: Array = [
		{
			"type": "image",
			"source": {
				"type": "base64",
				"media_type": "image/png",
				"data": fake_base64
			}
		},
		{
			"type": "text",
			"text": "Fetched image from https://example.com/img.png"
		}
	]
	history.add_tool_result("tool_001", vision_blocks, false)

	# Verify it shows up as a vision display message
	var display = history.get_display_messages()
	_assert(display.size() == 2, "Two display messages (user + vision)")
	_assert(display[1].get("role") == "vision", "Second message is vision role")
	_assert(display[1].get("base64_data") == fake_base64, "Vision data preserved")
	_assert(display[1].get("description") == "Fetched image from https://example.com/img.png", "Description preserved")

	# Verify API messages include vision blocks for the LLM
	var api = history.to_api_messages()
	_assert(api.size() >= 2, "API messages include all entries")

	# Verify serialization round-trip
	var storage = history.to_storage_array()
	var history2 := _ConversationHistory.new()
	history2.from_storage_array(storage)
	var display2 = history2.get_display_messages()
	_assert(display2[1].get("role") == "vision", "Reloaded vision message preserved")


func test_image_display_with_real_image() -> void:
	_log("Test: ImageDisplay with real fetched image")
	var tool := _ImageFetch.new()
	var result = await tool.execute({"url": "https://httpbin.org/image/png"}, {})

	if not result.get("success", false):
		_assert(false, "Fetch failed (network unavailable)")
		return

	var base64_data: String = str(result.get("vision_data", ""))
	var media_type: String = str(result.get("media_type", "image/png"))

	# Simulate what image_display.gd does in setup()
	var image_bytes := Marshalls.base64_to_raw(base64_data)
	_assert(image_bytes.size() > 0, "Base64 decoded to bytes")

	var image := Image.new()
	var err := image.load_png_from_buffer(image_bytes)
	_assert(err == OK, "PNG loaded from buffer")

	var texture := ImageTexture.create_from_image(image)
	_assert(texture != null, "ImageTexture created")
	_assert(texture.get_width() > 0, "Texture has width")
	_assert(texture.get_height() > 0, "Texture has height")

	# Test aspect ratio capping logic (same as image_display.gd)
	var aspect := float(image.get_width()) / float(image.get_height())
	var display_h := mini(image.get_height(), 300)
	var display_w := int(display_h * aspect)
	_assert(display_w > 0, "Display width calculated (%d)" % display_w)
	_assert(display_h <= 300, "Display height capped at 300 (%d)" % display_h)
	_log("    Display size: %dx%d (original %dx%d)" % [display_w, display_h, image.get_width(), image.get_height()])


func _log(text: String) -> void:
	print("  " + text)


func _assert(condition: bool, description: String) -> void:
	if condition:
		_passed += 1
		print("    PASS: %s" % description)
	else:
		_failed += 1
		push_error("    FAIL: %s" % description)
