extends GdUnitTestSuite
## Tests for GCFileEditTool


func test_edit_replace_string() -> void:
	var tool := GCFileEditTool.new()
	var path := ProjectSettings.globalize_path("user://test_edit.txt")
	# Setup file
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("Hello World\nSecond line")
	file.close()

	var result := tool.execute({
		"file_path": path,
		"old_string": "Hello World",
		"new_string": "Hello GodotCode"
	}, {})
	assert_bool(result.success).is_true()

	var read_file := FileAccess.open(path, FileAccess.READ)
	var content := read_file.get_as_text()
	read_file.close()
	assert_str(content).contains("Hello GodotCode")
	assert_str(content).does_not_contain("Hello World")


func test_edit_replace_all() -> void:
	var tool := GCFileEditTool.new()
	var path := ProjectSettings.globalize_path("user://test_edit_all.txt")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("foo bar foo baz foo")
	file.close()

	var result := tool.execute({
		"file_path": path,
		"old_string": "foo",
		"new_string": "qux",
		"replace_all": true
	}, {})
	assert_bool(result.success).is_true()

	var read_file := FileAccess.open(path, FileAccess.READ)
	var content := read_file.get_as_text()
	read_file.close()
	assert_str(content).is_equal("qux bar qux baz qux")


func test_edit_rejects_non_unique() -> void:
	var tool := GCFileEditTool.new()
	var path := ProjectSettings.globalize_path("user://test_edit_nonunique.txt")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("foo bar foo")
	file.close()

	var result := tool.execute({
		"file_path": path,
		"old_string": "foo",
		"new_string": "baz"
	}, {})
	assert_bool(result.success).is_false()
	assert_str(result.error).contains("not unique")


func test_edit_not_found() -> void:
	var tool := GCFileEditTool.new()
	var path := ProjectSettings.globalize_path("user://test_edit_notfound.txt")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("Hello World")
	file.close()

	var result := tool.execute({
		"file_path": path,
		"old_string": "DoesNotExist",
		"new_string": "Replacement"
	}, {})
	assert_bool(result.success).is_false()
	assert_str(result.error).contains("not found")


func test_edit_nonexistent_file() -> void:
	var tool := GCFileEditTool.new()
	var result := tool.execute({
		"file_path": "/nonexistent/edit.txt",
		"old_string": "old",
		"new_string": "new"
	}, {})
	assert_bool(result.success).is_false()


func test_validate_input() -> void:
	var tool := GCFileEditTool.new()
	assert_bool(tool.validate_input({}).valid).is_false()
	assert_bool(tool.validate_input({"file_path": "a"}).valid).is_false()
	assert_bool(tool.validate_input({"file_path": "a", "old_string": "b"}).valid).is_false()
	assert_bool(tool.validate_input({"file_path": "a", "old_string": "b", "new_string": "c"}).valid).is_true()
