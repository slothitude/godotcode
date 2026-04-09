extends GdUnitTestSuite
## Tests for GCToolRegistry


func test_register_tool() -> void:
	var registry := GCToolRegistry.new()
	var tool := GCBaseTool.new("TestTool", "A test tool", {})
	registry.register(tool)
	assert_bool(registry.has_tool("TestTool")).is_true()


func test_unregister_tool() -> void:
	var registry := GCToolRegistry.new()
	var tool := GCBaseTool.new("TestTool", "A test tool", {})
	registry.register(tool)
	registry.unregister("TestTool")
	assert_bool(registry.has_tool("TestTool")).is_false()


func test_get_tool() -> void:
	var registry := GCToolRegistry.new()
	var tool := GCBaseTool.new("TestTool", "A test tool", {})
	registry.register(tool)
	var retrieved := registry.get_tool("TestTool")
	assert_not_null(retrieved)
	assert_str(retrieved.tool_name).is_equal("TestTool")


func test_get_nonexistent_tool() -> void:
	var registry := GCToolRegistry.new()
	assert_null(registry.get_tool("DoesNotExist"))


func test_to_api_format() -> void:
	var registry := GCToolRegistry.new()
	var tool := GCBaseTool.new("Read", "Read a file", {
		"file_path": {"type": "string", "description": "Path"}
	})
	registry.register(tool)

	var api_format := registry.to_api_format()
	assert_int(api_format.size()).is_equal(1)
	assert_str(api_format[0].name).is_equal("Read")
	assert_str(api_format[0].description).is_equal("Read a file")
	assert_has(api_format[0], "input_schema")


func test_multiple_tools() -> void:
	var registry := GCToolRegistry.new()
	registry.register(GCBaseTool.new("Tool1", "First", {}))
	registry.register(GCBaseTool.new("Tool2", "Second", {}))
	registry.register(GCBaseTool.new("Tool3", "Third", {}))

	assert_int(registry.get_tool_names().size()).is_equal(3)
	assert_int(registry.to_api_format().size()).is_equal(3)
