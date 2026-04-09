extends GdUnitTestSuite
## Tests for GCFileWriteTool


func test_write_new_file() -> void:
	var tool := GCFileWriteTool.new()
	var path := ProjectSettings.globalize_path("user://test_write_new.txt")
	var result := tool.execute({"file_path": path, "content": "Hello Write"}, {})
	assert_bool(result.success).is_true()
	assert_bool(FileAccess.file_exists(path))


func test_write_overwrites_existing() -> void:
	var tool := GCFileWriteTool.new()
	var path := ProjectSettings.globalize_path("user://test_overwrite.txt")
	# Write initial content
	tool.execute({"file_path": path, "content": "Initial"}, {})
	# Overwrite
	tool.execute({"file_path": path, "content": "Overwritten"}, {})

	var file := FileAccess.open(path, FileAccess.READ)
	var content := file.get_as_text()
	file.close()
	assert_str(content).is_equal("Overwritten")


func test_write_creates_directories() -> void:
	var tool := GCFileWriteTool.new()
	var path := ProjectSettings.globalize_path("user://test_dir/sub/file.txt")
	var result := tool.execute({"file_path": path, "content": "Nested"}, {})
	assert_bool(result.success).is_true()


func test_validate_input_missing_path() -> void:
	var tool := GCFileWriteTool.new()
	assert_bool(tool.validate_input({"content": "test"}).valid).is_false()


func test_validate_input_missing_content() -> void:
	var tool := GCFileWriteTool.new()
	assert_bool(tool.validate_input({"file_path": "test.txt"}).valid).is_false()


func test_tool_is_not_read_only() -> void:
	var tool := GCFileWriteTool.new()
	assert_bool(tool.is_read_only).is_false()
