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

# Phase 1: Foundation
var _undo_stack: GCUndoStack
var _memory_manager: GCMemoryManager
var _session_manager: GCSessionManager

# Phase 2: Godot Superpowers
var _runtime_monitor: GCRuntimeMonitor
var _visual_diff: GCVisualDiff
var _asset_manager: GCAssetManager

# Phase 3: Ecosystem
var _hooks_manager: GCHooksManager
var _mcp_client: GCMCPClient
var _model_router: GCModelRouter

# Session tracking
var _current_session_id: String = ""


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

	# Phase 1: Undo stack
	_undo_stack = GCUndoStack.new()

	# Phase 1: Memory system
	_memory_manager = GCMemoryManager.new()

	# Phase 1: Session manager
	_session_manager = GCSessionManager.new()

	# Phase 2: Runtime monitor
	_runtime_monitor = GCRuntimeMonitor.new()

	# Phase 2: Visual diff
	_visual_diff = GCVisualDiff.new()

	# Phase 2: Asset manager
	_asset_manager = GCAssetManager.new()

	# Phase 3: Hooks
	_hooks_manager = GCHooksManager.new()

	# Phase 3: Model router
	_model_router = GCModelRouter.new()

	# Context manager (needs memory_manager)
	_context_manager = GCContextManager.new()
	_context_manager._memory_manager = _memory_manager
	_context_manager._runtime_monitor = _runtime_monitor

	_api_client = GCApiClient.new()
	_api_client._settings = _settings
	add_child(_api_client)

	# Phase 3: MCP client (needs Node for HTTPRequest)
	_mcp_client = GCMCPClient.new()
	add_child(_mcp_client)
	var mcp_servers = _settings.get_setting(GCSettings.MCP_SERVERS, [])
	if mcp_servers is Array and mcp_servers.size() > 0:
		_mcp_client.configure_servers(mcp_servers)

	_query_engine = GCQueryEngine.new()
	_query_engine._api_client = _api_client
	_query_engine._tool_registry = _tool_registry
	_query_engine._conversation_history = _conversation_history
	_query_engine._permission_manager = _permission_manager
	_query_engine._cost_tracker = _cost_tracker
	_query_engine._context_manager = _context_manager
	_query_engine._settings = _settings
	# Phase 1: Wire undo stack
	_query_engine._undo_stack = _undo_stack
	# Phase 2: Wire visual diff
	_query_engine._visual_diff = _visual_diff
	# Phase 3: Wire hooks
	_query_engine._hooks_manager = _hooks_manager
	# Phase 3: Wire model router
	_query_engine._model_router = _model_router
	# Phase 1: Wire session manager for auto-save
	_query_engine._session_manager = _session_manager
	# Wire direct references for tool context
	_query_engine._memory_manager = _memory_manager
	_query_engine._runtime_monitor = _runtime_monitor
	_query_engine._asset_manager = _asset_manager
	_query_engine._mcp_client = _mcp_client

	# Register built-in tools
	_register_tools()

	# Phase 3: Discover MCP tools (deferred since it's async)
	if mcp_servers is Array and mcp_servers.size() > 0:
		_discover_mcp_tools.call_deferred()

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
	_dock._session_manager = _session_manager
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)


func _exit_tree() -> void:
	if _dock:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null
	if _api_client:
		_api_client.queue_free()
		_api_client = null
	if _mcp_client:
		_mcp_client.queue_free()
		_mcp_client = null


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
	var image_gen := GCImageGenTool.new()
	var image_fetch := GCImageFetchTool.new()

	_tool_registry.register(error_monitor)
	_tool_registry.register(node_property)
	_tool_registry.register(scene_tree)
	_tool_registry.register(screenshot)
	_tool_registry.register(plugin_writer)
	_tool_registry.register(image_gen)
	_tool_registry.register(image_fetch)

	# Phase 1: Git tool
	var git_tool := GCGitTool.new()
	_tool_registry.register(git_tool)

	# Phase 1: Memory tool
	var memory_tool := GCMemoryTool.new()
	_tool_registry.register(memory_tool)

	# Phase 2: Runtime state tool
	var runtime_state := GCRuntimeStateTool.new()
	_tool_registry.register(runtime_state)

	# Phase 2: Visual diff tool
	var visual_diff_tool := GCVisualDiffTool.new()
	_tool_registry.register(visual_diff_tool)

	# Phase 2: Asset pipeline tool
	var asset_pipeline := GCAssetPipelineTool.new()
	_tool_registry.register(asset_pipeline)

	# Phase 2: Shader tool
	var shader_tool := GCShaderTool.new()
	_tool_registry.register(shader_tool)

	# Phase 3: MCP direct call tool
	var mcp_tool := GCMCPTool.new()
	mcp_tool._mcp_client = _mcp_client
	_tool_registry.register(mcp_tool)

	# Phase 4: Workflow automation tools
	# Tier 1: Quick Wins
	var project_scaffold := GCProjectScaffoldTool.new()
	_tool_registry.register(project_scaffold)

	var ui_builder := GCUIBuilderTool.new()
	_tool_registry.register(ui_builder)

	var export_tool := GCExportTool.new()
	_tool_registry.register(export_tool)

	var input_mapper := GCInputMapperTool.new()
	_tool_registry.register(input_mapper)

	# Tier 2: Scene Power-Ups
	var animation_tool := GCAnimationTool.new()
	_tool_registry.register(animation_tool)

	var collision_tool := GCCollisionTool.new()
	_tool_registry.register(collision_tool)

	var audio_tool := GCAudioTool.new()
	_tool_registry.register(audio_tool)

	var test_generator := GCTestGeneratorTool.new()
	_tool_registry.register(test_generator)

	# Tier 3: Advanced Workflows
	var level_tool := GCLevelTool.new()
	_tool_registry.register(level_tool)

	var npc_dialogue := GCNPCDialogueTool.new()
	_tool_registry.register(npc_dialogue)

	var localization := GCLocalizationTool.new()
	_tool_registry.register(localization)

	var performance := GCPerformanceTool.new()
	_tool_registry.register(performance)


func _register_commands() -> void:
	var commands: Array[GCBaseCommand] = [
		GCCompactCommand.new(),
		GCCommitCommand.new(),
		GCReviewCommand.new(),
		GCDoctorCommand.new(),
		GCMemoryCommand.new(),
		# Phase 1: Undo command
		GCUndoCommand.new(),
		# Phase 1: Session command
		GCSessionCommand.new(),
	]
	for cmd in commands:
		_command_map[cmd.command_name] = cmd

	# Phase 3: Load custom commands from project
	var custom_loader := GCCustomCommandLoader.new()
	var custom_commands := custom_loader.load_commands()
	for cmd in custom_commands:
		if cmd and cmd.command_name != "":
			_command_map[cmd.command_name] = cmd


func _discover_mcp_tools() -> void:
	## Async MCP tool discovery — called deferred from _enter_tree
	if _mcp_client and _tool_registry:
		_mcp_client.discover_and_register(_tool_registry)
