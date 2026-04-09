extends Control
## Integration test scene for chat flow

@onready var _output: RichTextLabel = $VBox/Output
@onready var _input: LineEdit = $VBox/InputRow/InputField
@onready var _send_btn: Button = $VBox/InputRow/SendBtn
@onready var _status_btn: Button = $VBox/StatusBtn

var _history: GCConversationHistory
var _tests_passed: int = 0
var _tests_failed: int = 0


func _ready() -> void:
	_send_btn.pressed.connect(_on_send)
	_status_btn.pressed.connect(_run_tests)
	_history = GCConversationHistory.new()
	_log("Chat Flow Test Scene loaded")


func _on_send() -> void:
	var text := _input.text.strip_edges()
	if text == "":
		return
	_input.text = ""
	_history.add_user_message(text)
	_log("[User] %s" % text)
	# Simulate assistant response
	var assistant := _history.add_assistant_message()
	assistant.add_text("Echo: %s" % text)
	_log("[Assistant] Echo: %s" % text)


func _run_tests() -> void:
	_tests_passed = 0
	_tests_failed = 0
	_log("\n== Running Chat Flow Tests ==")

	# Test 1: Message round trip
	_history.clear()
	_history.add_user_message("Test 1")
	var msg := _history.get_messages()[0] as GCMessageTypes.UserMessage
	_assert(msg.content == "Test 1", "User message content")

	# Test 2: Assistant with text
	var asst := _history.add_assistant_message()
	asst.add_text("Response text")
	_assert(asst.text_content == "Response text", "Assistant text content")

	# Test 3: API format
	var api := _history.to_api_messages()
	_assert(api.size() == 2, "API messages count")

	# Test 4: Serialization
	var data := _history.to_storage_array()
	var h2 := GCConversationHistory.new()
	h2.from_storage_array(data)
	_assert(h2.get_messages().size() == 2, "Round trip message count")

	_log("\n== Results: %d passed, %d failed ==" % [_tests_passed, _tests_failed])


func _assert(condition: bool, description: String) -> void:
	if condition:
		_tests_passed += 1
		_log("  PASS: %s" % description)
	else:
		_tests_failed += 1
		_log("  FAIL: %s" % description)


func _log(text: String) -> void:
	_output.append_text(text + "\n")
