class_name GCApiClient
extends Node
## Anthropic Messages API client with SSE streaming

signal stream_text_delta(text: String)
signal stream_tool_use_start(tool_name: String, tool_use_id: String)
signal stream_tool_input_delta(tool_use_id: String, partial_json: String)
signal stream_complete(usage: Dictionary, stop_reason: String)
signal stream_error(error: Dictionary)

var _settings: GCSettings
var _http_request: HTTPRequest
var _is_streaming: bool = false
var _stream_buffer: String = ""
var _current_tool_inputs: Dictionary = {}  # tool_use_id -> accumulated JSON string

# SSE parsing state
var _event_type: String = ""
var _event_data: String = ""


func send_message_streaming(messages: Array, system_prompt: String, tools: Array) -> void:
	if _is_streaming:
		stream_error.emit({"message": "Already streaming"})
		return

	if not _settings:
		stream_error.emit({"message": "Settings not initialized"})
		return

	var api_key := _settings.get_api_key()
	if api_key == "":
		stream_error.emit({"message": "API key not set. Open Settings to configure."})
		return

	_is_streaming = true
	_stream_buffer = ""
	_current_tool_inputs.clear()

	var url := _settings.get_base_url() + "/v1/messages"

	var body := {
		"model": _settings.get_model(),
		"max_tokens": _settings.get_max_tokens(),
		"stream": true,
		"messages": messages
	}

	if system_prompt != "":
		body["system"] = system_prompt

	if tools.size() > 0:
		body["tools"] = tools

	var headers := [
		"Content-Type: application/json",
		"x-api-key: %s" % api_key,
		"anthropic-version: 2023-06-01",
		"Accept: text/event-stream"
	]

	if not _http_request:
		_http_request = HTTPRequest.new()
		_http_request.request_completed.connect(_on_request_completed)
		add_child(_http_request)

	var json_body := JSON.stringify(body)
	var err := _http_request.request(url, headers, HTTPClient.METHOD_POST, json_body)
	if err != OK:
		_is_streaming = false
		stream_error.emit({"message": "HTTP request failed: %d" % err})


func send_message_sync(messages: Array, system_prompt: String, tools: Array) -> void:
	"""Non-streaming request — collects full response then emits signals."""
	if _is_streaming:
		stream_error.emit({"message": "Already streaming"})
		return

	var api_key := _settings.get_api_key()
	if api_key == "":
		stream_error.emit({"message": "API key not set"})
		return

	_is_streaming = true

	var url := _settings.get_base_url() + "/v1/messages"
	var body := {
		"model": _settings.get_model(),
		"max_tokens": _settings.get_max_tokens(),
		"messages": messages
	}

	if system_prompt != "":
		body["system"] = system_prompt

	if tools.size() > 0:
		body["tools"] = tools

	var headers := [
		"Content-Type: application/json",
		"x-api-key: %s" % api_key,
		"anthropic-version: 2023-06-01"
	]

	if not _http_request:
		_http_request = HTTPRequest.new()
		_http_request.request_completed.connect(_on_sync_request_completed)
		add_child(_http_request)

	var json_body := JSON.stringify(body)
	_http_request.request(url, headers, HTTPClient.METHOD_POST, json_body)


func _on_request_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_is_streaming = false

	if result != HTTPRequest.RESULT_SUCCESS:
		stream_error.emit({"message": "Request failed (result=%d)" % result})
		return

	if code >= 400:
		var body_text := body.get_string_from_utf8()
		var error_msg := "API error (HTTP %d)" % code
		var json := JSON.new()
		if json.parse(body_text) == OK:
			var data: Dictionary = json.data
			if data.has("error"):
				error_msg = str(data.error.get("message", error_msg))
		stream_error.emit({"message": error_msg, "code": code})
		return

	# Parse SSE response
	var response_text := body.get_string_from_utf8()
	_parse_sse_response(response_text)


func _on_sync_request_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_is_streaming = false

	if result != HTTPRequest.RESULT_SUCCESS:
		stream_error.emit({"message": "Request failed (result=%d)" % result})
		return

	if code >= 400:
		var body_text := body.get_string_from_utf8()
		stream_error.emit({"message": "API error (HTTP %d): %s" % [code, body_text]})
		return

	var response_text := body.get_string_from_utf8()
	var json := JSON.new()
	if json.parse(response_text) == OK:
		_handle_full_response(json.data)


func _handle_full_response(data: Dictionary) -> void:
	var content_blocks: Array = data.get("content", [])
	for block in content_blocks:
		if block.get("type") == "text":
			stream_text_delta.emit(block.get("text", ""))
		elif block.get("type") == "tool_use":
			stream_tool_use_start.emit(block.get("name", ""), block.get("id", ""))
			var input_json := JSON.stringify(block.get("input", {}))
			stream_tool_input_delta.emit(block.get("id", ""), input_json)

	var usage: Dictionary = data.get("usage", {})
	var stop_reason: String = data.get("stop_reason", "")
	stream_complete.emit(usage, stop_reason)


func _parse_sse_response(text: String) -> void:
	var lines := text.split("\n")
	_event_type = ""
	_event_data = ""

	for line in lines:
		if line == "":
			# Empty line = end of event
			if _event_type != "":
				_process_sse_event(_event_type, _event_data)
				_event_type = ""
				_event_data = ""
			continue

		if line.begins_with("event:"):
			_event_type = line.substr(6).strip_edges()
		elif line.begins_with("data:"):
			var data_str := line.substr(5).strip_edges()
			if _event_data != "":
				_event_data += "\n"
			_event_data += data_str
		# Ignore comments (lines starting with :)


func _process_sse_event(event_type: String, data_str: String) -> void:
	var json := JSON.new()
	if json.parse(data_str) != OK:
		return

	var data: Dictionary = json.data

	match event_type:
		"message_start":
			# Contains initial message metadata
			pass

		"content_block_start":
			var block: Dictionary = data.get("content_block", {})
			if block.get("type") == "tool_use":
				var tool_name: String = block.get("name", "")
				var tool_id: String = block.get("id", "")
				_current_tool_inputs[tool_id] = ""
				stream_tool_use_start.emit(tool_name, tool_id)
			# Text blocks start here but content comes in deltas

		"content_block_delta":
			var delta: Dictionary = data.get("delta", {})
			var delta_type: String = delta.get("type", "")
			match delta_type:
				"text_delta":
					stream_text_delta.emit(delta.get("text", ""))
				"input_json_delta":
					var tool_id: String = ""
					var index: int = data.get("index", 0)
					# Find tool_id by index from current inputs
					var keys := _current_tool_inputs.keys()
					if index < keys.size():
						tool_id = str(keys[index])
					var partial: String = delta.get("partial_json", "")
					if tool_id != "" and _current_tool_inputs.has(tool_id):
						_current_tool_inputs[tool_id] += partial
					stream_tool_input_delta.emit(tool_id, partial)

		"content_block_stop":
			pass

		"message_delta":
			var delta: Dictionary = data.get("delta", {})
			# stop_reason comes here

		"message_stop":
			var usage: Dictionary = {}
			if data.has("usage"):
				usage = data.get("usage", {})
			# Finalize tool inputs by parsing accumulated JSON
			for tool_id in _current_tool_inputs:
				var raw_json: String = _current_tool_inputs[tool_id]
				stream_tool_input_delta.emit(tool_id, raw_json)
			stream_complete.emit(usage, data.get("delta", {}).get("stop_reason", ""))

		"ping":
			pass

		"error":
			stream_error.emit(data.get("error", {"message": "SSE error"}))
