extends GdUnitTestSuite
## Tests for GCGlobTool


func test_glob_find_gd_files() -> void:
	var tool := GCGlobTool.new()
	# Create test files
	DirAccess.make_dir_recursive_absolute("user://test_glob_dir/")
	var file := FileAccess.open("user://test_glob_dir/script.gd", FileAccess.WRITE)
	file.store_string("extends Node")
	file.close()
	var file2 := FileAccess.open("user://test_glob_dir/data.json", FileAccess.WRITE)
	file2.store_string("{}")
	file2.close()

	var result := tool.execute({
		"pattern": "*.gd",
		"path": ProjectSettings.globalize_path("user://test_glob_dir/")
	}, {})
	assert_bool(result.success).is_true()
	assert_str(result.data).contains("script.gd")
	assert_str(result.data).does_not_contain("data.json")


func test_glob_recursive() -> void:
	var tool := GCGlobTool.new()
	DirAccess.make_dir_recursive_absolute("user://test_glob_recursive/sub/")
	var file := FileAccess.open("user://test_glob_recursive/sub/deep.txt", FileAccess.WRITE)
	file.store_string("deep")
	file.close()

	var result := tool.execute({
		"pattern": "**/*.txt",
		"path": ProjectSettings.globalize_path("user://test_glob_recursive/")
	}, {})
	assert_bool(result.success).is_true()
	assert_str(result.data).contains("deep.txt")


func test_glob_nonexistent_dir() -> void:
	var tool := GCGlobTool.new()
	var result := tool.execute({
		"pattern": "*.txt",
		"path": "/nonexistent/dir/"
	}, {})
	assert_bool(result.success).is_false()


func test_validate_input() -> void:
	var tool := GCGlobTool.new()
	assert_bool(tool.validate_input({}).valid).is_false()
	assert_bool(tool.validate_input({"pattern": "*.gd"}).valid).is_true()
