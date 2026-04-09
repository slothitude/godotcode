extends GdUnitTestSuite
## Tests for GCFileReadTool


func test_read_existing_file() -> void:
	var tool := GCFileReadTool.new()
	# Create a temp file
	var path := "user://test_read_file.txt"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("Hello World\nLine 2\nLine 3")
	file.close()

	var result := tool.execute({"file_path": ProjectSettings.globalize_path(path)}, {})
	assert_bool(result.success).is_true()
	assert_str(result.data).contains("Hello World")


func test_read_with_offset() -> void:
	var tool := GCFileReadTool.new()
	var path := "user://test_offset.txt"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("Line 1\nLine 2\nLine 3\nLine 4\nLine 5")
	file.close()

	var result := tool.execute({
		"file_path": ProjectSettings.globalize_path(path),
		"offset": 2,
		"limit": 2
	}, {})
	assert_bool(result.success).is_true()
	assert_str(result.data).contains("Line 2")
	assert_str(result.data).contains("Line 3")
	assert_str(result.data).does_not_contain("Line 1")


func test_read_nonexistent_file() -> void:
	var tool := GCFileReadTool.new()
	var result := tool.execute({"file_path": "/nonexistent/path/file.txt"}, {})
	assert_bool(result.success).is_false()
	assert_str(result.error).contains("not found")


func test_validate_input_missing_path() -> void:
	var tool := GCFileReadTool.new()
	var result := tool.validate_input({})
	assert_bool(result.valid).is_false()


func test_validate_input_valid() -> void:
	var tool := GCFileReadTool.new()
	var result := tool.validate_input({"file_path": "/some/file.txt"})
	assert_bool(result.valid).is_true()


func test_tool_is_read_only() -> void:
	var tool := GCFileReadTool.new()
	assert_bool(tool.is_read_only).is_true()
