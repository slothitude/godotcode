@tool
extends EditorPlugin
## GodotCode Editor Plugin — AI assistant dock for Godot 4.6

const ChatPanelScene := preload("ui/chat_panel.tscn")

var _dock: Control
var _settings: GCSettings
var _api_client: GCApiClient
var _query_engine: GCQueryEngine
var _tool_registry: GCToolRegistry
var _conversation_history: GCConversationHistory
var _permission_manager: GCPermissionManager
var _cost_tracker: GCCostTracker
var _context_manager: GCContextManager
var _command_map: Dictionary = {}

func _get_plugin_name() -> String:
	return "GodotCode"

func _enter_tree() -> void:
	# Initialize core systems
	_settings = GCSettings.new()
	_settings.initialize()

	_cost_tracker = GCCostTracker.new()
	_conversation_history = GCConversationHistory.new()
	_conversation_history._settings = _settings

	_permission_manager = GCPermissionManager.new()
	_permission_manager._settings = _settings

	_tool_registry = GCToolRegistry.new()

	_context_manager = GCContextManager.new()

	_api_client = GCApiClient.new()
	_api_client._settings = _settings
	add_child(_api_client)

	_query_engine = GCQueryEngine.new()
	_query_engine._api_client = _api_client
	_query_engine._tool_registry = _tool_registry
	_query_engine._conversation_history = _conversation_history
	_query_engine._permission_manager = _permission_manager
	_query_engine._cost_tracker = _cost_tracker
	_query_engine._context_manager = _context_manager

	# Register built-in tools
	_register_tools()

	# Register slash commands
	_register_commands()

	# Create and add dock panel
	_dock = ChatPanelScene.instantiate()
	_dock._plugin = self
	_dock._query_engine = _query_engine
	_dock._settings = _settings
	_dock._conversation_history = _conversation_history
	_dock._cost_tracker = _cost_tracker
	_dock._command_map = _command_map
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)


func _exit_tree() -> void:
	if _dock:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null
	if _api_client:
		_api_client.queue_free()
		_api_client = null


func _register_tools() -> void:
	var file_read := GCFileReadTool.new()
	var file_write := GCFileWriteTool.new()
	var file_edit := GCFileEditTool.new()
	var glob := GCGlobTool.new()
	var grep := GCGrepTool.new()
	var bash := GCBashTool.new()
	var web_search := GCWebSearchTool.new()
	var web_fetch := GCWebFetchTool.new()
	var agent := GCAgentTool.new()
	var plan_mode := GCPlanModeTool.new()
	var task_tools := GCTaskTools.new()
	var schedule_tools := GCScheduleTools.new()
	var sleep_tool := GCSleepTool.new()

	_tool_registry.register(file_read)
	_tool_registry.register(file_write)
	_tool_registry.register(file_edit)
	_tool_registry.register(glob)
	_tool_registry.register(grep)
	_tool_registry.register(bash)
	_tool_registry.register(web_search)
	_tool_registry.register(web_fetch)
	_tool_registry.register(agent)
	_tool_registry.register(plan_mode)
	_tool_registry.register(task_tools)
	_tool_registry.register(schedule_tools)
	_tool_registry.register(sleep_tool)

	# Live editor tools
	var error_monitor := GCErrorMonitorTool.new()
	var node_property := GCNodePropertyTool.new()
	var scene_tree := GCSceneTreeTool.new()
	var screenshot := GCScreenshotTool.new()
	var plugin_writer := GCPluginWriterTool.new()

	_tool_registry.register(error_monitor)
	_tool_registry.register(node_property)
	_tool_registry.register(scene_tree)
	_tool_registry.register(screenshot)
	_tool_registry.register(plugin_writer)


func _register_commands() -> void:
	var commands: Array[GCBaseCommand] = [
		GCCompactCommand.new(),
		GCCommitCommand.new(),
		GCReviewCommand.new(),
		GCDoctorCommand.new(),
		GCMemoryCommand.new(),
	]
	for cmd in commands:
		_command_map[cmd.command_name] = cmd
