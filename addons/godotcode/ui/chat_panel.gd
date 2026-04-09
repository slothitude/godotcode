@tool
extends VBoxContainer
## Main dock panel for the GodotCode plugin

var _plugin: EditorPlugin
var _query_engine: GCQueryEngine
var _settings: GCSettings
var _conversation_history: GCConversationHistory
var _cost_tracker: GCCostTracker
var _command_map: Dictionary = {}
var _settings_dialog: AcceptDialog
var _streaming_label: RichTextLabel
var _is_streaming: bool = false

@onready var _send_btn: Button = %SendBtn if has_node("%SendBtn") else $InputArea/SendBtn
@onready var _input_field: TextEdit = $InputArea/InputField
@onready var _message_list: VBoxContainer = $MessageContainer/MessageList
@onready var _message_container: ScrollContainer = $MessageContainer
@onready var _status_label: Label = $StatusBar/StatusLabel
@onready var _cost_label: Label = $Header/CostLabel
@onready var _settings_btn: Button = $Header/SettingsBtn


func _ready() -> void:
	_send_btn.pressed.connect(_on_send)
	_settings_btn.pressed.connect(_on_settings)
	_input_field.gui_input.connect(_on_input_gui_input)

	if _query_engine:
		_query_engine.message_received.connect(_on_message_received)
		_query_engine.stream_text_delta.connect(_on_stream_delta)
		_query_engine.stream_tool_call_received.connect(_on_tool_call)
		_query_engine.query_complete.connect(_on_query_complete)
		_query_engine.query_error.connect(_on_query_error)
		_query_engine.permission_requested.connect(_on_permission_requested)

	_load_conversation()


func _on_input_gui_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_ENTER and not key_event.shift_pressed:
			if key_event.pressed:
				_on_send()
				_input_field.accept_event()


func _on_send() -> void:
	var text := _input_field.text.strip_edges()
	if text == "" or _is_streaming:
		return

	_input_field.text = ""

	# Check for slash commands
	if text.begins_with("/"):
		_handle_command(text)
		return

	# Add user message to display
	_add_message_bubble("user", text)

	# Submit to query engine
	_is_streaming = true
	_send_btn.disabled = true
	_status_label.text = "Thinking..."
	_query_engine.submit_message(text)


func _handle_command(text: String) -> void:
	var parts := text.split(" ", false, 1)
	var cmd_name := parts[0].lstrip("/")
	var args := parts[1] if parts.size() > 1 else ""

	if _command_map.has(cmd_name):
		var cmd: GCBaseCommand = _command_map[cmd_name]
		var result := cmd.execute(args, _build_command_context())
		if result.text != "":
			_add_message_bubble("system", result.text)
	else:
		_add_message_bubble("system", "Unknown command: /" + cmd_name)


func _build_command_context() -> Dictionary:
	return {
		"conversation_history": _conversation_history,
		"settings": _settings,
		"query_engine": _query_engine,
	}


func _on_message_received(message: Dictionary) -> void:
	if message.get("role") == "assistant":
		var content = message.get("content", "")
		if content is String and content != "":
			# If streaming label exists, it already has this content — just finalize it
			if _streaming_label:
				_streaming_label = null
			else:
				_add_message_bubble("assistant", content)


func _on_stream_delta(text: String) -> void:
	if not _streaming_label:
		_streaming_label = _create_message_label("assistant")
		_streaming_label.bbcode_text = ""
	_status_label.text = "Streaming..."
	_streaming_label.text += text
	# Auto-scroll
	await get_tree().process_frame
	_message_container.ensure_control_visible(_streaming_label)


func _on_tool_call(tool_name: String, tool_input: Dictionary) -> void:
	_add_message_bubble("tool", "[Tool: %s]" % tool_name)
	_status_label.text = "Running: %s" % tool_name


func _on_query_complete(result: Dictionary) -> void:
	_is_streaming = false
	_streaming_label = null
	_send_btn.disabled = false
	_status_label.text = "Ready"
	var cost := _cost_tracker.get_session_cost()
	_cost_label.text = "$%.2f" % cost
	_save_conversation()


func _on_query_error(error: Dictionary) -> void:
	_is_streaming = false
	_streaming_label = null
	_send_btn.disabled = false
	_status_label.text = "Error"
	var error_msg := str(error.get("message", "Unknown error"))
	_add_message_bubble("error", error_msg)


func _on_permission_requested(tool_name: String, tool_input: Dictionary, callback: Callable) -> void:
	var dialog := preload("tool_approval_dialog.tscn").instantiate()
	add_child(dialog)
	dialog.setup(tool_name, tool_input, callback)
	dialog.popup_centered(Vector2i(500, 300))


func _add_message_bubble(role: String, text: String) -> void:
	var label := _create_message_label(role)
	label.text = text
	# Auto-scroll
	await get_tree().process_frame
	if is_instance_valid(_message_container):
		_message_container.ensure_control_visible(label)


func _create_message_label(role: String) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.fit_content = true
	label.scroll_following = true
	label.bbcode_enabled = true
	label.custom_minimum_size = Vector2(0, 40)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	match role:
		"user":
			label.add_theme_color_override("default_color", Color(0.8, 0.9, 1.0))
		"assistant":
			label.add_theme_color_override("default_color", Color(1.0, 1.0, 1.0))
		"tool":
			label.add_theme_color_override("default_color", Color(0.7, 0.9, 0.7))
		"error":
			label.add_theme_color_override("default_color", Color(1.0, 0.5, 0.5))
		"system":
			label.add_theme_color_override("default_color", Color(0.9, 0.8, 0.5))

	_message_list.add_child(label)
	return label


func _on_settings() -> void:
	if not _settings_dialog:
		_settings_dialog = preload("settings_dialog.tscn").instantiate()
		_settings_dialog._settings = _settings
		add_child(_settings_dialog)
	_settings_dialog.popup_centered(Vector2i(450, 400))


func _load_conversation() -> void:
	if _conversation_history and _conversation_history.load_from_file():
		for msg in _conversation_history.get_display_messages():
			_add_message_bubble(msg.role, msg.content)


func _save_conversation() -> void:
	if _conversation_history:
		_conversation_history.save_to_file()


func _exit_tree() -> void:
	_save_conversation()
