extends Control
## Streaming integration test — requires a valid API key

@onready var _output: RichTextLabel = $VBox/Output
@onready var _input: LineEdit = $VBox/InputRow/MsgInput
@onready var _send_btn: Button = $VBox/InputRow/SendBtn

var _api_client: Node  # GCApiClient (needs to be in tree)
var _history: GCConversationHistory


func _ready() -> void:
	_send_btn.pressed.connect(_on_send)
	_history = GCConversationHistory.new()
	_log("Streaming Test loaded. Enter a message to test API streaming.")


func _on_send() -> void:
	var text := _input.text.strip_edges()
	if text == "":
		return
	_input.text = ""
	_history.add_user_message(text)
	_log("[You] %s" % text)

	if not _api_client:
		_api_client = GCApiClient.new()
		_api_client._settings = GCSettings.new()
		_api_client._settings.initialize()
		_api_client.stream_text_delta.connect(_on_text_delta)
		_api_client.stream_complete.connect(_on_complete)
		_api_client.stream_error.connect(_on_error)
		add_child(_api_client)

	_log("[GodotCode] ")
	_api_client.send_message_streaming(_history.to_api_messages(), "You are a helpful assistant.", [])


func _on_text_delta(text: String) -> void:
	_output.append_text(text)


func _on_complete(usage: Dictionary, stop_reason: String) -> void:
	_log("\n[Complete] stop_reason=%s tokens=%s" % [stop_reason, str(usage)])


func _on_error(error: Dictionary) -> void:
	_log("\n[Error] %s" % str(error.get("message", "unknown")))


func _log(text: String) -> void:
	_output.append_text(text + "\n")
