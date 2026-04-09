extends Control
## Integration test scene for tool execution

@onready var _output: RichTextLabel = $VBox/Output
@onready var _run_btn: Button = $VBox/RunBtn

var _registry: GCToolRegistry
var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_run_btn.pressed.connect(_run_tests)
	_registry = GCToolRegistry.new()
	_registry.register(GCFileReadTool.new())
	_registry.register(GCFileWriteTool.new())
	_registry.register(GCFileEditTool.new())
	_registry.register(GCGlobTool.new())
	_registry.register(GCGrepTool.new())
	_log("Tool Execution Test Scene loaded")


func _run_tests() -> void:
	_passed = 0
	_failed = 0
	_log("\n== Running Tool Execution Tests ==")

	# Test registry
	_assert(_registry.has_tool("Read"), "Read tool registered")
	_assert(_registry.has_tool("Write"), "Write tool registered")
	_assert(_registry.has_tool("Edit"), "Edit tool registered")
	_assert(_registry.has_tool("Glob"), "Glob tool registered")
	_assert(_registry.has_tool("Grep"), "Grep tool registered")

	# Test file write + read round trip
	var write_tool := _registry.get_tool("Write") as GCFileWriteTool
	var test_path := ProjectSettings.globalize_path("user://tool_test_file.txt")
	var write_result := write_tool.execute({"file_path": test_path, "content": "Tool test content"}, {})
	_assert(write_result.success, "Write tool succeeded")

	var read_tool := _registry.get_tool("Read") as GCFileReadTool
	var read_result := read_tool.execute({"file_path": test_path}, {})
	_assert(read_result.success, "Read tool succeeded")
	_assert(str(read_result.data).contains("Tool test content"), "Read content matches written content")

	# Test edit
	var edit_tool := _registry.get_tool("Edit") as GCFileEditTool
	var edit_result := edit_tool.execute({
		"file_path": test_path,
		"old_string": "Tool test",
		"new_string": "Edited"
	}, {})
	_assert(edit_result.success, "Edit tool succeeded")

	var verify_result := read_tool.execute({"file_path": test_path}, {})
	_assert(str(verify_result.data).contains("Edited content"), "Edit verified in file")

	# Test API format
	var api_tools := _registry.to_api_format()
	_assert(api_tools.size() == 5, "API format has 5 tools")

	_log("\n== Results: %d passed, %d failed ==" % [_passed, _failed])


func _assert(condition: bool, description: String) -> void:
	if condition:
		_passed += 1
		_log("  PASS: %s" % description)
	else:
		_failed += 1
		_log("  FAIL: %s" % description)


func _log(text: String) -> void:
	_output.append_text(text + "\n")
