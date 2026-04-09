extends GdUnitTestSuite
## Tests for GCContextManager


func test_build_system_prompt_includes_project_name() -> void:
	var mgr := GCContextManager.new()
	var prompt := mgr.build_system_prompt()
	# Should contain basic prompt structure
	assert_str(prompt).contains("GodotCode")
	assert_str(prompt).contains("Godot")


func test_read_claude_md() -> void:
	var mgr := GCContextManager.new()
	# Create a test CLAUDE.md
	var file := FileAccess.open("res://CLAUDE.md", FileAccess.WRITE)
	file.store_string("This is a test instruction file.")
	file.close()

	var content := mgr._read_claude_md()
	assert_str(content).contains("test instruction")

	# Cleanup
	DirAccess.remove_absolute("res://CLAUDE.md")


func test_get_file_tree() -> void:
	var mgr := GCContextManager.new()
	var tree := mgr._get_file_tree()
	# Even in an empty project there should be some structure
	# Just verify it doesn't crash
	assert_not_null(tree)
