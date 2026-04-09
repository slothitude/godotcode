extends GdUnitTestSuite
## Tests for GCMessageTypes

const msg_path := "res://addons/godotcode/core/message_types.gd"


func test_user_message_creation() -> void:
	var msg := GCMessageTypes.UserMessage.new("Hello GodotCode")
	assert_str(msg.role).is_equal("user")
	assert_str(msg.content).is_equal("Hello GodotCode")


func test_user_message_api_format() -> void:
	var msg := GCMessageTypes.UserMessage.new("Test message")
	var api := msg.to_api_dict()
	assert_str(api.role).is_equal("user")
	assert_str(api.content).is_equal("Test message")


func test_user_message_serialization() -> void:
	var msg := GCMessageTypes.UserMessage.new("Serialize me")
	var d := msg.to_storage_dict()
	assert_str(d.role).is_equal("user")
	assert_str(d.content).is_equal("Serialize me")
	assert_has(d, "timestamp")


func test_user_message_deserialization() -> void:
	var data := {"role": "user", "content": "Deserialized", "timestamp": 12345}
	var msg := GCMessageTypes.UserMessage.from_storage(data)
	assert_str(msg.content).is_equal("Deserialized")
	assert_int(msg.timestamp).is_equal(12345)


func test_assistant_message_creation() -> void:
	var msg := GCMessageTypes.AssistantMessage.new()
	assert_str(msg.role).is_equal("assistant")
	assert_str(msg.text_content).is_equal("")
	assert_array(msg.tool_uses).is_empty()


func test_assistant_message_add_text() -> void:
	var msg := GCMessageTypes.AssistantMessage.new()
	msg.add_text("Hello ")
	msg.add_text("world")
	assert_str(msg.text_content).is_equal("Hello world")


func test_assistant_message_add_tool_use() -> void:
	var msg := GCMessageTypes.AssistantMessage.new()
	msg.add_tool_use("tool_123", "Read", {"file_path": "/test.txt"})
	assert_array(msg.tool_uses).has_size(1)
	assert_str(msg.tool_uses[0].id).is_equal("tool_123")
	assert_str(msg.tool_uses[0].name).is_equal("Read")


func test_assistant_message_api_format() -> void:
	var msg := GCMessageTypes.AssistantMessage.new()
	msg.add_text("I will read a file")
	msg.add_tool_use("tool_456", "Read", {"file_path": "/test.txt"})

	var api := msg.to_api_dict()
	assert_str(api.role).is_equal("assistant")
	var content: Array = api.content
	assert_int(content.size()).is_equal(2)
	assert_str(content[0].type).is_equal("text")
	assert_str(content[1].type).is_equal("tool_use")


func test_assistant_message_serialization_round_trip() -> void:
	var msg := GCMessageTypes.AssistantMessage.new()
	msg.add_text("Test text")
	msg.add_tool_use("id1", "Write", {"file_path": "test.txt"})

	var d := msg.to_storage_dict()
	var restored := GCMessageTypes.AssistantMessage.from_storage(d)

	assert_str(restored.text_content).is_equal("Test text")
	assert_array(restored.tool_uses).has_size(1)
	assert_str(restored.tool_uses[0].name).is_equal("Write")


func test_tool_result_message_creation() -> void:
	var msg := GCMessageTypes.ToolResultMessage.new("tool_789", "File contents here")
	assert_str(msg.tool_use_id).is_equal("tool_789")
	assert_str(msg.content).is_equal("File contents here")
	assert_bool(msg.is_error).is_false()


func test_tool_result_message_error() -> void:
	var msg := GCMessageTypes.ToolResultMessage.new("tool_err", "File not found", true)
	assert_bool(msg.is_error).is_true()
	var api := msg.to_api_dict()
	var content: Array = api.content
	assert_bool(content[0].is_error).is_true()


func test_tool_result_message_api_format() -> void:
	var msg := GCMessageTypes.ToolResultMessage.new("tool_abc", "result data")
	var api := msg.to_api_dict()
	assert_str(api.role).is_equal("user")
	var content: Array = api.content
	assert_str(content[0].type).is_equal("tool_result")
	assert_str(content[0].tool_use_id).is_equal("tool_abc")
	assert_str(content[0].content).is_equal("result data")


func test_from_storage_user_message() -> void:
	var data := {"role": "user", "content": "Test", "timestamp": 0}
	var msg := GCMessageTypes.from_storage(data)
	assert_not_null(msg)
	assert_bool(msg is GCMessageTypes.UserMessage).is_true()


func test_from_storage_assistant_message() -> void:
	var data := {"role": "assistant", "text_content": "Response", "tool_uses": [], "timestamp": 0}
	var msg := GCMessageTypes.from_storage(data)
	assert_not_null(msg)
	assert_bool(msg is GCMessageTypes.AssistantMessage).is_true()


func test_from_storage_tool_result() -> void:
	var data := {"role": "user", "msg_type": "tool_result", "tool_use_id": "t1", "content": "ok", "timestamp": 0}
	var msg := GCMessageTypes.from_storage(data)
	assert_not_null(msg)
	assert_bool(msg is GCMessageTypes.ToolResultMessage).is_true()
