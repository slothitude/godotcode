extends SceneTree
## Headless test for image display, vision signal pipeline, and image gen tool

var _passed: int = 0
var _failed: int = 0

# Lazy-loaded scripts
var _ImageGenTool: GDScript
var _ConversationHistory: GDScript
var _Settings: GDScript
var _QueryEngine: GDScript
var _ToolRegistry: GDScript
var _BaseTool: GDScript


func _init() -> void:
	# Load scripts explicitly (--script mode doesn't autoload class_names)
	_ImageGenTool = load("res://addons/godotcode/tools/image_gen_tool.gd")
	_ConversationHistory = load("res://addons/godotcode/core/conversation_history.gd")
	_Settings = load("res://addons/godotcode/core/settings.gd")
	_QueryEngine = load("res://addons/godotcode/core/query_engine.gd")
	_ToolRegistry = load("res://addons/godotcode/core/tool_registry.gd")
	_BaseTool = load("res://addons/godotcode/tools/base_tool.gd")

	print("\n========== Image Display & Vision Pipeline Tests ==========\n")
	_run_tests()
	print("\n========== Results: %d passed, %d failed ==========" % [_passed, _failed])
	quit()


func _run_tests() -> void:
	test_image_gen_tool_registration()
	test_image_gen_tool_validate()
	test_image_display_round_trip()
	test_conversation_history_vision()
	test_settings_image_gen()
	test_vision_signal_emission()
	test_conversation_history_text_still_works()


func test_image_gen_tool_registration() -> void:
	_log("Test: ImageGen tool registration")
	var registry := _ToolRegistry.new()
	var image_gen := _ImageGenTool.new()
	registry.register(image_gen)
	_assert(registry.has_tool("ImageGen"), "ImageGen tool registered in registry")
	var tool_def: Dictionary = image_gen.to_tool_definition()
	_assert(tool_def["name"] == "ImageGen", "Tool definition name is ImageGen")
	_assert(tool_def["input_schema"]["properties"].has("prompt"), "Schema has prompt param")
	_assert(tool_def["input_schema"]["properties"].has("provider"), "Schema has provider param")


func test_image_gen_tool_validate() -> void:
	_log("Test: ImageGen input validation")
	var tool := _ImageGenTool.new()
	var result: Dictionary = tool.validate_input({})
	_assert(not result["valid"], "Empty input rejected")
	result = tool.validate_input({"prompt": ""})
	_assert(not result["valid"], "Empty prompt rejected")
	result = tool.validate_input({"prompt": "a cat"})
	_assert(result["valid"], "Valid prompt accepted")


func test_image_display_round_trip() -> void:
	_log("Test: Image encode/decode round trip")

	# Create a small 4x4 red PNG image in memory
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color.RED)
	var png_bytes := image.save_png_to_buffer()
	var base64_str := Marshalls.raw_to_base64(png_bytes)
	_assert(base64_str.length() > 0, "Base64 encoding produced output")

	# Round-trip decode
	var decoded := Marshalls.base64_to_raw(base64_str)
	_assert(decoded.size() == png_bytes.size(), "Round-trip base64 decode matches original size")

	# Load image from buffer
	var loaded := Image.new()
	var err := loaded.load_png_from_buffer(decoded)
	_assert(err == OK, "Image loads from decoded PNG buffer")
	_assert(loaded.get_width() == 4, "Decoded image width is 4")
	_assert(loaded.get_height() == 4, "Decoded image height is 4")


func test_conversation_history_vision() -> void:
	_log("Test: Conversation history vision metadata")
	var history := _ConversationHistory.new()

	# Add a tool result with vision content blocks
	var vision_blocks: Array = [
		{
			"type": "image",
			"source": {
				"type": "base64",
				"media_type": "image/png",
				"data": "fake_base64_data_here"
			}
		},
		{
			"type": "text",
			"text": "Screenshot captured (1920x1080, 123456 bytes)"
		}
	]
	history.add_tool_result("tool_123", vision_blocks, false)

	var display = history.get_display_messages()
	_assert(display.size() == 1, "One display message from vision tool result")
	var msg: Dictionary = display[0]
	_assert(msg.get("role") == "vision", "Display message role is 'vision'")
	_assert(msg.get("base64_data") == "fake_base64_data_here", "base64_data extracted correctly")
	_assert(msg.get("media_type") == "image/png", "media_type extracted correctly")
	_assert(msg.get("description") == "Screenshot captured (1920x1080, 123456 bytes)", "description extracted correctly")

	# Test serialization round-trip
	var storage = history.to_storage_array()
	_assert(storage.size() == 1, "One message in storage array")
	_assert(storage[0].get("msg_type") == "tool_result", "Storage msg_type is tool_result")

	# Reload from storage
	var history2 := _ConversationHistory.new()
	history2.from_storage_array(storage)
	var display2 = history2.get_display_messages()
	_assert(display2.size() == 1, "Reloaded one display message")
	_assert(display2[0].get("role") == "vision", "Reloaded message role is 'vision'")
	_assert(display2[0].get("base64_data") == "fake_base64_data_here", "Reloaded base64_data preserved")


func test_conversation_history_text_still_works() -> void:
	_log("Test: Non-vision tool results still work")
	var history := _ConversationHistory.new()

	history.add_user_message("Read test.txt")
	history.add_tool_result("tool_456", "Simple text result", false)

	var display = history.get_display_messages()
	_assert(display.size() == 2, "Two display messages (user + tool result)")
	_assert(display[1].get("role") == "tool", "Text tool result has role 'tool'")
	_assert(str(display[1].get("content")) == "Simple text result", "Text content preserved")


func test_settings_image_gen() -> void:
	_log("Test: Image gen settings constants")
	var settings_script: GDScript = _Settings
	_assert(settings_script.IMAGE_GEN_PROVIDER == "image_gen_provider", "IMAGE_GEN_PROVIDER constant correct")
	_assert(settings_script.IMAGE_GEN_MODEL == "image_gen_model", "IMAGE_GEN_MODEL constant correct")
	_assert(settings_script.OLLAMA_URL == "ollama_url", "OLLAMA_URL constant correct")
	_assert(settings_script.DEFAULT_IMAGE_GEN_PROVIDER == "ollama", "Default provider is ollama")
	_assert(settings_script.DEFAULT_IMAGE_GEN_MODEL == "llava", "Default model is llava")
	_assert(settings_script.DEFAULT_OLLAMA_URL == "http://localhost:11434", "Default Ollama URL correct")


func test_vision_signal_emission() -> void:
	_log("Test: Vision signal wiring")

	# Verify the signal exists on query engine
	var engine := _QueryEngine.new()
	var signal_list = engine.get_signal_list()
	var has_vision_signal := false
	for sig in signal_list:
		if sig["name"] == "tool_vision_result":
			has_vision_signal = true
			_assert(sig["args"].size() == 4, "tool_vision_result has 4 args")
			break
	_assert(has_vision_signal, "tool_vision_result signal exists on query engine")

	# Verify has_vision_result on base tool
	var tool := _ImageGenTool.new()
	_assert(tool.has_vision_result({"is_vision": true, "success": true}), "has_vision_result detects vision")
	_assert(not tool.has_vision_result({"is_vision": false}), "has_vision_result rejects non-vision")
	_assert(not tool.has_vision_result({}), "has_vision_result handles missing key")


func _log(text: String) -> void:
	print("  " + text)


func _assert(condition: bool, description: String) -> void:
	if condition:
		_passed += 1
		print("    PASS: %s" % description)
	else:
		_failed += 1
		push_error("    FAIL: %s" % description)
