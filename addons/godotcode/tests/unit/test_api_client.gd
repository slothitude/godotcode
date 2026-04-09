extends GdUnitTestSuite
## Tests for GCApiClient SSE parsing

const api_path := "res://addons/godotcode/core/api_client.gd"


func test_sse_event_parsing_text_delta() -> void:
	var client := GCApiClient.new()
	# Test the SSE parsing logic by calling the internal method
	var sse_response := """event: message_start
data: {"type":"message_start","message":{"id":"msg_1","type":"message","role":"assistant","content":[],"model":"claude-sonnet-4-20250514","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":10,"output_tokens":1}}}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" world"}}

event: content_block_stop
data: {"type":"content_block_stop","index":0}

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":5}}

event: message_stop
data: {"type":"message_stop"}"""

	var texts: Array = []
	client.stream_text_delta.connect(func(t: String): texts.append(t))
	client.stream_complete.connect(func(_u, _s): pass)

	client._parse_sse_response(sse_response)
	assert_array(texts).has_size(2)
	assert_str(texts[0]).is_equal("Hello")
	assert_str(texts[1]).is_equal(" world")


func test_sse_event_parsing_tool_use() -> void:
	var client := GCApiClient.new()
	var sse_response := """event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_123","name":"Read"}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\\"file_path\\":"}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"\\"test.txt\\"}"}}

event: message_stop
data: {"type":"message_stop"}"""

	var tool_names: Array = []
	client.stream_tool_use_start.connect(func(name, id): tool_names.append(name))
	client._parse_sse_response(sse_response)
	assert_array(tool_names).has_size(1)
	assert_str(tool_names[0]).is_equal("Read")


func test_non_streaming_response() -> void:
	var client := GCApiClient.new()
	var response_text := """{"id":"msg_1","type":"message","role":"assistant","content":[{"type":"text","text":"Hello!"}],"model":"claude-sonnet-4-20250514","stop_reason":"end_turn","usage":{"input_tokens":10,"output_tokens":5}}"""

	var texts: Array = []
	client.stream_text_delta.connect(func(t: String): texts.append(t))

	var json := JSON.new()
	json.parse(response_text)
	client._handle_full_response(json.data)

	assert_array(texts).has_size(1)
	assert_str(texts[0]).is_equal("Hello!")
