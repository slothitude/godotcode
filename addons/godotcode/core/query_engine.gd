class_name GCQueryEngine
extends RefCounted
## Core query loop: send -> stream -> parse tool calls -> execute -> repeat

enum State { IDLE, STREAMING, TOOL_EXECUTING, COMPLETE, ERROR }

signal message_received(message: Dictionary)
signal stream_text_delta(text: String)
signal stream_tool_call_received(tool_name: String, tool_input: Dictionary)
signal query_complete(result: Dictionary)
signal query_error(error: Dictionary)
signal permission_requested(tool_name: String, tool_input: Dictionary, callback: Callable)
signal status_update(message: String)
signal tool_vision_result(tool_name: String, base64_data: String, media_type: String, description: String)

var state: State = State.IDLE
var _api_client: GCApiClient
var _tool_registry: GCToolRegistry
var _conversation_history: GCConversationHistory
var _permission_manager: GCPermissionManager
var _cost_tracker: GCCostTracker
var _context_manager: GCContextManager
var _settings: GCSettings

# Phase 1: Undo stack
var _undo_stack: GCUndoStack

# Phase 2: Visual diff
var _visual_diff: GCVisualDiff

# Phase 3: Hooks manager
var _hooks_manager: GCHooksManager

# Phase 3: Model router
var _model_router: GCModelRouter

# Phase 1: Session auto-save
var _session_manager: GCSessionManager

# Phase 1: Memory manager (passed through for tool context)
var _memory_manager: GCMemoryManager

# Phase 2: Runtime monitor (passed through for tool context)
var _runtime_monitor: GCRuntimeMonitor

# Phase 2: Asset manager (passed through for tool context)
var _asset_manager: GCAssetManager

# Phase 3: MCP client (passed through for tool context)
var _mcp_client: GCMCPClient

var _pending_tool_calls: Array = []  # {name, id, input}
var _current_assistant: GCMessageTypes.AssistantMessage
var _iteration_count: int = 0
var _max_iterations: int = 50
var _last_vision_data: String = ""
var _last_vision_media_type: String = "image/png"


func submit_message(prompt: String) -> void:
	if state != State.IDLE:
		query_error.emit({"message": "Query engine busy (state=%d)" % state})
		return

	# Phase 3: Fire pre_query hook
	if _hooks_manager:
		var hook_result := _hooks_manager.fire("pre_query", {"prompt": prompt})
		if not hook_result.get("proceed", true):
			query_error.emit({"message": "Blocked by hook: " + str(hook_result.get("messages", []))})
			return

	# Add user message if non-empty
	if prompt != "":
		_conversation_history.add_user_message(prompt)

	# Build system prompt with context
	var system_prompt := _build_system_prompt()

	_iteration_count = 0

	# Phase 3: Model router overrides
	var model_overrides := {}
	if _model_router:
		model_overrides = _model_router.resolve_model("", {}, _build_context())

	_start_stream(system_prompt, model_overrides)


func _start_stream(system_prompt: String, model_overrides: Dictionary = {}) -> void:
	state = State.STREAMING
	_current_assistant = _conversation_history.add_assistant_message()
	_pending_tool_calls.clear()
	status_update.emit("Thinking...")

	# Pass internal message objects — the API client converts per provider
	var messages := _conversation_history.get_messages()
	var tools_array: Array = _tool_registry.get_all_tools().values()

	# Connect API signals (will auto-disconnect when complete)
	if not _api_client.stream_text_delta.is_connected(_on_stream_text):
		_api_client.stream_text_delta.connect(_on_stream_text)
	if not _api_client.stream_tool_use_start.is_connected(_on_stream_tool_start):
		_api_client.stream_tool_use_start.connect(_on_stream_tool_start)
	if not _api_client.stream_tool_input_delta.is_connected(_on_stream_tool_input):
		_api_client.stream_tool_input_delta.connect(_on_stream_tool_input)
	if not _api_client.stream_complete.is_connected(_on_stream_complete):
		_api_client.stream_complete.connect(_on_stream_complete)
	if not _api_client.stream_error.is_connected(_on_stream_error):
		_api_client.stream_error.connect(_on_stream_error)

	# Phase 3: Pass model overrides to API client
	if model_overrides.is_empty():
		_api_client.send_message_streaming(messages, system_prompt, tools_array)
	else:
		_api_client.send_message_streaming_with_overrides(messages, system_prompt, tools_array, model_overrides)


func _on_stream_text(text: String) -> void:
	if _current_assistant:
		_current_assistant.add_text(text)
	stream_text_delta.emit(text)


func _on_stream_tool_start(tool_name: String, tool_use_id: String) -> void:
	_pending_tool_calls.append({"name": tool_name, "id": tool_use_id, "input": {}})


func _on_stream_tool_input(tool_use_id: String, partial_json: String) -> void:
	# Accumulate tool input JSON — parse on complete
	for tc in _pending_tool_calls:
		if tc.id == tool_use_id:
			tc["_raw_input"] = tc.get("_raw_input", "") + partial_json
			break


func _on_stream_complete(usage: Dictionary, stop_reason: String) -> void:
	# Track costs
	if _cost_tracker:
		_cost_tracker.add_usage(usage)

	# Parse accumulated tool input JSON
	for tc in _pending_tool_calls:
		var raw: String = tc.get("_raw_input", "")
		if raw != "":
			var json := JSON.new()
			if json.parse(raw) == OK:
				tc.input = json.data
			else:
				tc.input = {}

	# Disconnect signals
	if _api_client:
		if _api_client.stream_text_delta.is_connected(_on_stream_text):
			_api_client.stream_text_delta.disconnect(_on_stream_text)
		if _api_client.stream_tool_use_start.is_connected(_on_stream_tool_start):
			_api_client.stream_tool_use_start.disconnect(_on_stream_tool_start)
		if _api_client.stream_tool_input_delta.is_connected(_on_stream_tool_input):
			_api_client.stream_tool_input_delta.disconnect(_on_stream_tool_input)
		if _api_client.stream_complete.is_connected(_on_stream_complete):
			_api_client.stream_complete.disconnect(_on_stream_complete)
		if _api_client.stream_error.is_connected(_on_stream_error):
			_api_client.stream_error.disconnect(_on_stream_error)

	# Finalize current assistant message
	if _current_assistant:
		for tc in _pending_tool_calls:
			_current_assistant.add_tool_use(tc.id, tc.name, tc.input)
		message_received.emit({"role": "assistant", "content": _current_assistant.text_content})

	# Process tool calls or complete
	if _pending_tool_calls.size() > 0:
		state = State.TOOL_EXECUTING
		_execute_tool_calls_async()
	else:
		state = State.COMPLETE
		query_complete.emit({"usage": usage, "stop_reason": stop_reason})

		# Phase 3: Fire post_query hook
		if _hooks_manager:
			_hooks_manager.fire("post_query", {"usage": usage})

		state = State.IDLE


func _on_stream_error(error: Dictionary) -> void:
	state = State.ERROR

	# Phase 3: Fire on_error hook
	if _hooks_manager:
		_hooks_manager.fire("on_error", error)

	query_error.emit(error)
	state = State.IDLE


func _execute_tool_calls() -> void:
	_iteration_count += 1
	if _iteration_count > _max_iterations:
		state = State.ERROR
		query_error.emit({"message": "Max iterations exceeded (%d)" % _max_iterations})
		return

	for tc in _pending_tool_calls:
		var tool: GCBaseTool = _tool_registry.get_tool(tc.name)

		if not tool:
			_conversation_history.add_tool_result(tc.id, "Unknown tool: %s" % tc.name, true)
			continue

		# Check permissions
		var perm := tool.check_permissions(tc.input, _build_context())
		var behavior: String = perm.get("behavior", "ask")

		match behavior:
			"deny":
				_conversation_history.add_tool_result(tc.id, "Permission denied: " + perm.get("message", ""), true)
			"ask":
				var mode := _permission_manager.get_current_mode() if _permission_manager else "default"
				if mode == "bypass":
					_execute_single_tool(tool, tc)
				else:
					permission_requested.emit(tc.name, tc.input, func(approved: bool):
						if approved:
							_execute_single_tool(tool, tc)
						else:
							_conversation_history.add_tool_result(tc.id, "User denied permission", true)
					)
			"allow":
				_execute_single_tool(tool, tc)

	_pending_tool_calls.clear()

	# Re-query with tool results
	var system_prompt := _build_system_prompt()
	_start_stream(system_prompt)


func _execute_tool_calls_async() -> void:
	_iteration_count += 1
	if _iteration_count > _max_iterations:
		state = State.ERROR
		query_error.emit({"message": "Max iterations exceeded (%d)" % _max_iterations})
		return

	status_update.emit("Executing tools...")
	for tc in _pending_tool_calls:
		var tool: GCBaseTool = _tool_registry.get_tool(tc.name)

		if not tool:
			_conversation_history.add_tool_result(tc.id, "Unknown tool: %s" % tc.name, true)
			continue

		# Phase 3: Fire pre_tool hook
		if _hooks_manager:
			var hook_ctx := {"tool_name": tc.name, "file_path": str(tc.input.get("file_path", tc.input.get("path", "")))}
			var hook_result := _hooks_manager.fire("pre_tool", hook_ctx)
			if not hook_result.get("proceed", true):
				_conversation_history.add_tool_result(tc.id, "Blocked by hook: " + str(hook_result.get("messages", [])), true)
				continue

		# Check permissions
		var perm := tool.check_permissions(tc.input, _build_context())
		var behavior: String = perm.get("behavior", "ask")

		match behavior:
			"deny":
				_conversation_history.add_tool_result(tc.id, "Permission denied: " + perm.get("message", ""), true)
			"ask":
				var mode := _permission_manager.get_current_mode() if _permission_manager else "default"
				if mode == "bypass":
					await _execute_single_tool_async(tool, tc)
				else:
					permission_requested.emit(tc.name, tc.input, func(approved: bool):
						if approved:
							await _execute_single_tool_async(tool, tc)
						else:
							_conversation_history.add_tool_result(tc.id, "User denied permission", true)
					)
			"allow":
				await _execute_single_tool_async(tool, tc)

	_pending_tool_calls.clear()

	# Re-query with tool results
	var system_prompt := _build_system_prompt()

	# Phase 3: Model router — resolve per-tool
	var model_overrides := {}
	if _model_router:
		model_overrides = _model_router.resolve_model("", {}, _build_context())

	_start_stream(system_prompt, model_overrides)


func _execute_single_tool(tool: GCBaseTool, tool_call: Dictionary) -> void:
	stream_tool_call_received.emit(tool_call.name, tool_call.input)

	# Phase 1: Push to undo stack before write/edit
	_pre_tool_undo(tool_call.name, tool_call.input)

	# Phase 2: Capture before for visual diff
	_pre_tool_visual_diff(tool_call.name, tool_call.input)

	var result := tool.execute(tool_call.input, _build_context())

	# Phase 2: Capture after for visual diff
	_post_tool_visual_diff()

	# Phase 3: Fire post_tool hook
	if _hooks_manager:
		_hooks_manager.fire("post_tool", {"tool_name": tool_call.name, "result": result})

	# Check if tool returned vision content
	if tool.has_vision_result(result) and result.get("success", false):
		_last_vision_data = result.get("vision_data", "")
		_last_vision_media_type = result.get("media_type", "image/png")
		# Build vision content blocks for the API
		var vision_blocks: Array = [
			{
				"type": "image",
				"source": {
					"type": "base64",
					"media_type": result.get("media_type", "image/png"),
					"data": result.get("vision_data", "")
				}
			},
			{
				"type": "text",
				"text": str(result.get("data", ""))
			}
		]
		_conversation_history.add_tool_result(tool_call.id, vision_blocks, false)
		tool_vision_result.emit(
			tool_call.name,
			result.get("vision_data", ""),
			result.get("media_type", "image/png"),
			str(result.get("data", ""))
		)
	else:
		var tool_result := tool.to_api_result(result, tool_call.id)
		_conversation_history.add_tool_result(
			tool_call.id,
			tool_result.get("content", ""),
			tool_result.get("is_error", false)
		)


func _execute_single_tool_async(tool: GCBaseTool, tool_call: Dictionary) -> void:
	stream_tool_call_received.emit(tool_call.name, tool_call.input)

	# Phase 1: Push to undo stack before write/edit
	_pre_tool_undo(tool_call.name, tool_call.input)

	# Phase 2: Capture before for visual diff
	_pre_tool_visual_diff(tool_call.name, tool_call.input)

	var result = await tool.execute(tool_call.input, _build_context())

	# Phase 2: Capture after for visual diff
	_post_tool_visual_diff()

	# Phase 3: Fire post_tool hook
	if _hooks_manager:
		_hooks_manager.fire("post_tool", {"tool_name": tool_call.name, "result": result})

	# Check if tool returned vision content
	if tool.has_vision_result(result) and result.get("success", false):
		_last_vision_data = result.get("vision_data", "")
		_last_vision_media_type = result.get("media_type", "image/png")
		var vision_blocks: Array = [
			{
				"type": "image",
				"source": {
					"type": "base64",
					"media_type": result.get("media_type", "image/png"),
					"data": result.get("vision_data", "")
				}
			},
			{
				"type": "text",
				"text": str(result.get("data", ""))
			}
		]
		_conversation_history.add_tool_result(tool_call.id, vision_blocks, false)
		tool_vision_result.emit(
			tool_call.name,
			result.get("vision_data", ""),
			result.get("media_type", "image/png"),
			str(result.get("data", ""))
		)
	else:
		var tool_result := tool.to_api_result(result, tool_call.id)
		_conversation_history.add_tool_result(
			tool_call.id,
			tool_result.get("content", ""),
			tool_result.get("is_error", false)
		)


## Phase 1: Undo — push file content before write/edit operations
func _pre_tool_undo(tool_name: String, tool_input: Dictionary) -> void:
	if not _undo_stack:
		return
	if tool_name in ["Write", "Edit"]:
		var file_path: String = str(tool_input.get("file_path", ""))
		if file_path != "":
			if file_path.begins_with("res://"):
				file_path = ProjectSettings.globalize_path(file_path)
			_undo_stack.push(file_path, tool_name)


## Phase 2: Visual diff — capture before screenshot for scene mutations
func _pre_tool_visual_diff(tool_name: String, tool_input: Dictionary) -> void:
	if not _visual_diff:
		return
	if tool_name in ["SceneTree", "NodeProperty"]:
		var action: String = str(tool_input.get("action", ""))
		# Only capture for write operations
		if action in ["set", "add_child", "remove_child", "move", "reparent"]:
			_visual_diff.capture_before(tool_name, tool_input)


## Phase 2: Visual diff — capture after screenshot
func _post_tool_visual_diff() -> void:
	if _visual_diff and _visual_diff.has_before():
		_visual_diff.capture_after()


func _build_system_prompt() -> String:
	var prompt := ""
	if _context_manager:
		prompt = _context_manager.build_system_prompt()
	if _conversation_history:
		var sp := _conversation_history.get_system_prompt()
		if sp != "":
			if prompt != "":
				prompt += "\n\n"
			prompt += sp
	return prompt


func _build_context() -> Dictionary:
	return {
		"project_path": ProjectSettings.globalize_path("res://"),
		"conversation_history": _conversation_history,
		"tool_registry": _tool_registry,
		"settings": _settings,
		"last_vision_data": _last_vision_data,
		"last_vision_media_type": _last_vision_media_type,
		# Phase 1: Memory manager
		"memory_manager": _memory_manager,
		# Phase 2: Runtime monitor
		"runtime_monitor": _runtime_monitor,
		# Phase 2: Visual diff
		"visual_diff": _visual_diff,
		# Phase 2: Asset manager
		"asset_manager": _asset_manager,
		# Phase 3: MCP client
		"mcp_client": _mcp_client,
	}
