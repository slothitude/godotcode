extends GdUnitTestSuite
## Tests for GCGrepTool


func test_grep_find_pattern() -> void:
	var tool := GCGrepTool.new()
	DirAccess.make_dir_recursive_absolute("user://test_grep_dir/")
	var file := FileAccess.open("user://test_grep_dir/code.gd", FileAccess.WRITE)
	file.store_string("extends Node\nfunc hello():\n    print('hello')\nfunc world():\n    print('world')")
	file.close()

	var result := tool.execute({
		"pattern": "hello",
		"path": ProjectSettings.globalize_path("user://test_grep_dir/"),
		"output_mode": "content"
	}, {})
	assert_bool(result.success).is_true()
	assert_str(result.data).contains("hello")


func test_grep_files_with_matches() -> void:
	var tool := GCGrepTool.new()
	DirAccess.make_dir_recursive_absolute("user://test_grep_files/")
	var file := FileAccess.open("user://test_grep_files/a.gd", FileAccess.WRITE)
	file.store_string("extends Node2D")
	file.close()
	var file2 := FileAccess.open("user://test_grep_files/b.gd", FileAccess.WRITE)
	file2.store_string("extends Control")
	file2.close()

	var result := tool.execute({
		"pattern": "extends",
		"path": ProjectSettings.globalize_path("user://test_grep_files/"),
		"output_mode": "files_with_matches"
	}, {})
	assert_bool(result.success).is_true()
	assert_str(result.data).contains("a.gd")
	assert_str(result.data).contains("b.gd")


func test_grep_count_mode() -> void:
	var tool := GCGrepTool.new()
	DirAccess.make_dir_recursive_absolute("user://test_grep_count/")
	var file := FileAccess.open("user://test_grep_count/test.gd", FileAccess.WRITE)
	file.store_string("var a = 1\nvar b = 2\nvar c = 3")
	file.close()

	var result := tool.execute({
		"pattern": "var",
		"path": ProjectSettings.globalize_path("user://test_grep_count/"),
		"output_mode": "count"
	}, {})
	assert_bool(result.success).is_true()
	assert_str(result.data).contains("3")


func test_grep_case_insensitive() -> void:
	var tool := GCGrepTool.new()
	DirAccess.make_dir_recursive_absolute("user://test_grep_case/")
	var file := FileAccess.open("user://test_grep_case/test.gd", FileAccess.WRITE)
	file.store_string("Func Hello():\n    Print('hi')")
	file.close()

	var result := tool.execute({
		"pattern": "func",
		"path": ProjectSettings.globalize_path("user://test_grep_case/"),
		"-i": true,
		"output_mode": "content"
	}, {})
	assert_bool(result.success).is_true()
	assert_str(result.data).contains("Func")


func test_grep_no_matches() -> void:
	var tool := GCGrepTool.new()
	DirAccess.make_dir_recursive_absolute("user://test_grep_nomatch/")
	var file := FileAccess.open("user://test_grep_nomatch/test.gd", FileAccess.WRITE)
	file.store_string("extends Node")
	file.close()

	var result := tool.execute({
		"pattern": "nonexistent_pattern_xyz",
		"path": ProjectSettings.globalize_path("user://test_grep_nomatch/")
	}, {})
	assert_bool(result.success).is_true()
	assert_str(result.data).contains("No matches")


func test_validate_input() -> void:
	var tool := GCGrepTool.new()
	assert_bool(tool.validate_input({}).valid).is_false()
	assert_bool(tool.validate_input({"pattern": "test"}).valid).is_true()
