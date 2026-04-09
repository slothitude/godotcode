extends GdUnitTestSuite
## Tests for GCConversationHistory

const history_path := "res://addons/godotcode/core/conversation_history.gd"


func test_add_user_message() -> void:
	var history := GCConversationHistory.new()
	history.add_user_message("Hello")
	assert_int(history.get_messages().size()).is_equal(1)
	var msg := history.get_messages()[0]
	assert_str(msg.content).is_equal("Hello")


func test_add_assistant_message() -> void:
	var history := GCConversationHistory.new()
	var msg := history.add_assistant_message()
	msg.add_text("Hi there")
	assert_int(history.get_messages().size()).is_equal(1)


func test_add_tool_result() -> void:
	var history := GCConversationHistory.new()
	history.add_tool_result("tool_1", "file content")
	var msg := history.get_messages()[0]
	assert_str(msg.tool_use_id).is_equal("tool_1")
	assert_str(msg.content).is_equal("file content")


func test_to_api_messages_user_only() -> void:
	var history := GCConversationHistory.new()
	history.add_user_message("Hello")
	history.add_assistant_message().add_text("Hi")
	history.add_user_message("How are you?")

	var api := history.to_api_messages()
	assert_int(api.size()).is_equal(3)
	assert_str(api[0].role).is_equal("user")
	assert_str(api[1].role).is_equal("assistant")
	assert_str(api[2].role).is_equal("user")


func test_to_api_messages_merges_tool_results() -> void:
	var history := GCConversationHistory.new()
	history.add_user_message("Read files")
	var assistant := history.add_assistant_message()
	assistant.add_tool_use("t1", "Read", {"file_path": "a.txt"})
	assistant.add_tool_use("t2", "Read", {"file_path": "b.txt"})
	history.add_tool_result("t1", "content a")
	history.add_tool_result("t2", "content b")

	var api := history.to_api_messages()
	# Should have: user, assistant, merged tool_results (1 user msg)
	assert_int(api.size()).is_equal(3)
	var tool_msg: Dictionary = api[2]
	assert_str(tool_msg.role).is_equal("user")
	var content: Array = tool_msg.content
	assert_int(content.size()).is_equal(2)


func test_clear() -> void:
	var history := GCConversationHistory.new()
	history.add_user_message("Test")
	history.clear()
	assert_int(history.get_messages().size()).is_equal(0)


func test_compact() -> void:
	var history := GCConversationHistory.new()
	for i in range(10):
		history.add_user_message("Message %d" % i)
	history.compact(4)
	assert_int(history.get_messages().size()).is_equal(4)


func test_serialization_round_trip() -> void:
	var history := GCConversationHistory.new()
	history.add_user_message("Hello")
	var assistant := history.add_assistant_message()
	assistant.add_text("Hi")
	history.add_user_message("Read test.txt")
	assistant = history.add_assistant_message()
	assistant.add_tool_use("t1", "Read", {"file_path": "test.txt"})
	history.add_tool_result("t1", "file contents")

	var data := history.to_storage_array()
	var history2 := GCConversationHistory.new()
	history2.from_storage_array(data)

	assert_int(history2.get_messages().size()).is_equal(5)


func test_get_display_messages() -> void:
	var history := GCConversationHistory.new()
	history.add_user_message("Hello")
	var assistant := history.add_assistant_message()
	assistant.add_text("Hi there")
	assistant.add_tool_use("t1", "Read", {"file_path": "test.txt"})

	var display := history.get_display_messages()
	assert_int(display.size()).is_equal(3)  # user, assistant text, tool


func test_system_prompt() -> void:
	var history := GCConversationHistory.new()
	history.set_system_prompt("You are helpful")
	assert_str(history.get_system_prompt()).is_equal("You are helpful")
