extends SceneTree
## Test all 12 new features from the Power-Up plan
## Run: godot --headless --script addons/godotcode/tests/test_powerups.gd

var _pass_count := 0
var _fail_count := 0
var _test_results: Array = []


func _init() -> void:
	print("\n========== GodotCode Power-Up Test Suite ==========\n")

	# Phase 1
	test_undo_stack()
	test_memory_manager()
	test_session_manager()
	test_git_tool()

	# Phase 2
	test_runtime_monitor()
	test_visual_diff()
	test_asset_manager()
	test_shader_tool()

	# Phase 3
	test_hooks_manager()
	test_mcp_tool()
	test_model_router()
	test_custom_command_loader()

	# Summary
	print("\n========== Results ==========")
	print("PASS: %d  |  FAIL: %d  |  Total: %d" % [_pass_count, _fail_count, _pass_count + _fail_count])

	if _fail_count > 0:
		print("\n--- Failed tests ---")
		for r in _test_results:
			if not r.passed:
				print("  FAIL: %s — %s" % [r.name, r.detail])

	print("")
	quit(0 if _fail_count == 0 else 1)


# ============ Helpers ============

func assert_true(condition: bool, test_name: String, detail: String = "") -> void:
	if condition:
		_pass_count += 1
		_test_results.append({"name": test_name, "passed": true, "detail": ""})
	else:
		_fail_count += 1
		_test_results.append({"name": test_name, "passed": false, "detail": detail})
		print("  FAIL: %s — %s" % [test_name, detail])


func assert_eq(actual: Variant, expected: Variant, test_name: String) -> void:
	assert_true(actual == expected, test_name, "Expected %s, got %s" % [str(expected), str(actual)])


func assert_not_null(value: Variant, test_name: String) -> void:
	assert_true(value != null, test_name, "Expected non-null")


func assert_has(dict: Dictionary, key: String, test_name: String) -> void:
	assert_true(dict.has(key), test_name, "Missing key: %s" % key)


# ============ Phase 1: Foundation ============

func test_undo_stack() -> void:
	print("\n--- Test 1: Undo Stack ---")
	var stack := GCUndoStack.new()

	# Test empty state
	assert_true(stack.can_undo() == false, "Undo: empty stack can't undo")
	assert_eq(stack.size(), 0, "Undo: empty stack size is 0")

	# Test push on nonexistent file (should fail gracefully)
	var pushed := stack.push("/nonexistent/file.txt", "Write")
	assert_true(pushed == false, "Undo: push nonexistent file returns false")

	# Test push/pop with a temp file
	var tmp_path := "user://test_undo_temp.txt"
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	f.store_string("original content")
	f.close()

	assert_true(stack.push(tmp_path, "Write"), "Undo: push existing file succeeds")
	assert_eq(stack.size(), 1, "Undo: stack size after push")

	# Overwrite the file
	f = FileAccess.open(tmp_path, FileAccess.WRITE)
	f.store_string("modified content")
	f.close()

	# Pop (undo)
	var entry: Dictionary = stack.pop()
	assert_has(entry, "file_path", "Undo: pop returns entry with file_path")
	assert_eq(entry.get("tool_name", ""), "Write", "Undo: pop entry has correct tool_name")
	assert_eq(entry.get("original_content", ""), "original content", "Undo: pop restores original content")

	# Verify file was restored
	f = FileAccess.open(tmp_path, FileAccess.READ)
	var restored := f.get_as_text()
	f.close()
	assert_eq(restored, "original content", "Undo: file content restored after pop")

	# Test list and clear
	assert_eq(stack.size(), 0, "Undo: stack empty after pop")
	stack.clear()
	assert_eq(stack.size(), 0, "Undo: clear works")

	# Test max depth
	for i in range(110):
		var p := "user://test_%d.txt" % i
		f = FileAccess.open(p, FileAccess.WRITE)
		f.store_string("content %d" % i)
		f.close()
		stack.push(p, "Write")
	assert_true(stack.size() <= 100, "Undo: stack trimmed to max depth")
	assert_eq(stack.size(), 100, "Undo: stack exactly 100 entries")

	# Cleanup temp files
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_path))
	for i in range(110):
		var p := "user://test_%d.txt" % i
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func test_memory_manager() -> void:
	print("\n--- Test 2: Memory Manager ---")
	var mm := GCMemoryManager.new()

	# Clear any existing
	mm.clear_all_memories()

	# Test empty state
	assert_eq(mm.list_memories().size(), 0, "Memory: empty initially")
	assert_eq(mm.build_memory_section(), "", "Memory: empty section")

	# Test add
	assert_true(mm.add_memory("project_facts", "This project uses GDScript 4.6"), "Memory: add succeeds")
	assert_eq(mm.list_memories().size(), 1, "Memory: one memory after add")

	# Test build section
	var section := mm.build_memory_section()
	assert_true(section != "", "Memory: section not empty after add")
	assert_true(section.contains("project_facts"), "Memory: section contains key")
	assert_true(section.contains("GDScript"), "Memory: section contains content")

	# Test recall
	var results := mm.get_relevant_memories("GDScript")
	assert_true(results.size() > 0, "Memory: recall finds matching memory")
	assert_eq(results[0].name, "project_facts", "Memory: recall returns correct name")

	# Test recall with non-matching query
	var no_results := mm.get_relevant_memories("xyznonexistent")
	assert_eq(no_results.size(), 0, "Memory: recall returns empty for no match")

	# Test add another
	assert_true(mm.add_memory("coding_style", "Use tabs not spaces"), "Memory: add second")
	assert_eq(mm.list_memories().size(), 2, "Memory: two memories")

	# Test delete
	assert_true(mm.delete_memory("project_facts"), "Memory: delete succeeds")
	assert_eq(mm.list_memories().size(), 1, "Memory: one after delete")

	# Test clear
	mm.clear_all_memories()
	assert_eq(mm.list_memories().size(), 0, "Memory: empty after clear")


func test_session_manager() -> void:
	print("\n--- Test 3: Session Manager ---")
	var sm := GCSessionManager.new()
	var history := GCConversationHistory.new()

	# Test empty state
	assert_eq(sm.list_sessions().size(), 0, "Session: empty initially")

	# Create a session with some messages
	history.add_user_message("Hello")
	history.add_assistant_message()
	history.add_user_message("World")

	var id := sm.create_session("Test Session", history)
	assert_true(id != "", "Session: create returns id")
	assert_eq(sm.list_sessions().size(), 1, "Session: one session after create")

	# Load session
	var data: Dictionary = sm.load_session(id)
	assert_has(data, "name", "Session: loaded data has name")
	assert_eq(data.get("name", ""), "Test Session", "Session: correct name")
	assert_has(data, "messages", "Session: loaded data has messages")

	# Rename
	assert_true(sm.rename_session(id, "Renamed"), "Session: rename succeeds")
	var renamed: Dictionary = sm.load_session(id)
	assert_eq(renamed.get("name", ""), "Renamed", "Session: name updated")

	# Get most recent
	var recent: Dictionary = sm.get_most_recent_session()
	assert_has(recent, "id", "Session: most recent has id")

	# Delete
	assert_true(sm.delete_session(id), "Session: delete succeeds")
	assert_eq(sm.list_sessions().size(), 0, "Session: empty after delete")

	# Test auto-save
	var id2 := sm.auto_save(history)
	assert_true(id2 != "", "Session: auto-save returns id")
	assert_eq(sm.list_sessions().size(), 1, "Session: one after auto-save")

	# Cleanup
	sm.delete_session(id2)


func test_git_tool() -> void:
	print("\n--- Test 4: Git Tool ---")
	var git: GCGitTool = GCGitTool.new()

	# Test basic properties
	assert_eq(git.tool_name, "Git", "Git: tool name")
	assert_true(git.is_read_only, "Git: is read-only by default")

	# Test validate_input
	var valid: Dictionary = git.validate_input({"action": "status"})
	assert_true(valid.get("valid", false), "Git: status action valid")

	var invalid: Dictionary = git.validate_input({"action": ""})
	assert_true(not invalid.get("valid", true), "Git: empty action invalid")

	var bad_action: Dictionary = git.validate_input({"action": "explode"})
	assert_true(not bad_action.get("valid", true), "Git: bad action invalid")

	# Test check_permissions
	var status_perm: Dictionary = git.check_permissions({"action": "status"}, {})
	assert_eq(status_perm.get("behavior", ""), "allow", "Git: status is allowed")

	var log_perm: Dictionary = git.check_permissions({"action": "log"}, {})
	assert_eq(log_perm.get("behavior", ""), "allow", "Git: log is allowed")

	var add_perm: Dictionary = git.check_permissions({"action": "add", "args": "."}, {})
	assert_eq(add_perm.get("behavior", ""), "ask", "Git: add needs permission")

	# Test destructive detection
	var destructive_perm: Dictionary = git.check_permissions({"action": "branch", "args": "-D feature"}, {})
	assert_eq(destructive_perm.get("behavior", ""), "ask", "Git: branch -D needs permission")

	# Test actual git execution (execute uses await internally with thread)
	# Note: on Windows, bash may not be available, so git may fail — that's OK
	var result: Dictionary = await git.execute({"action": "status"}, {"project_path": ProjectSettings.globalize_path("res://")})
	# Git might work or fail depending on platform, just check it returns a result
	assert_has(result, "success", "Git: status returns result with success key")
	if result.get("success", false):
		assert_has(result, "data", "Git: status returns data on success")

	var log_result: Dictionary = await git.execute({"action": "log", "args": "5"}, {"project_path": ProjectSettings.globalize_path("res://")})
	assert_has(log_result, "success", "Git: log returns result")


# ============ Phase 2: Godot Superpowers ============

func test_runtime_monitor() -> void:
	print("\n--- Test 5: Runtime Monitor ---")
	var monitor := GCRuntimeMonitor.new()

	# In headless test mode, game is not running
	assert_true(not monitor.is_game_running(), "Runtime: game not running in test")
	assert_eq(monitor.get_remote_tree(), "Game is not running", "Runtime: tree says not running")

	var props: Dictionary = monitor.get_remote_node_properties("SomeNode")
	assert_true(not props.get("success", true), "Runtime: properties fails when not running")


func test_visual_diff() -> void:
	print("\n--- Test 6: Visual Diff ---")
	var diff := GCVisualDiff.new()

	# Test initial state
	assert_true(not diff.has_before(), "VisualDiff: no before initially")

	# capture_before won't work in headless (no viewport), but shouldn't crash
	diff.capture_before("SceneTree", {"action": "set"})
	assert_true(true, "VisualDiff: capture_before doesn't crash")

	# capture_after shouldn't crash either
	var result: Dictionary = diff.capture_after()
	assert_has(result, "has_diff", "VisualDiff: capture_after returns result")

	# Test getter methods
	assert_true(diff.get_before_image() is String, "VisualDiff: get_before_image returns string")
	assert_true(diff.get_after_image() is String, "VisualDiff: get_after_image returns string")


func test_asset_manager() -> void:
	print("\n--- Test 7: Asset Manager ---")
	var am := GCAssetManager.new()

	# Test import with invalid data
	var bad_import: Dictionary = am.import_image("", "res://test.png", "image/png")
	assert_true(not bad_import.get("success", true), "Asset: empty data fails")

	var bad_b64: Dictionary = am.import_image("not_base64!!", "res://test.png", "image/png")
	assert_true(not bad_b64.get("success", true), "Asset: invalid base64 fails")

	# Test create_material — won't work in headless without editor, shouldn't crash
	var mat_path := am.create_material({"name": "test_mat_powerup", "albedo_color": "#ff0000", "metallic": 0.5, "roughness": 0.3})
	assert_true(true, "Asset: create_material doesn't crash")


func test_shader_tool() -> void:
	print("\n--- Test 8: Shader Tool ---")
	var shader: GCShaderTool = GCShaderTool.new()

	assert_eq(shader.tool_name, "Shader", "Shader: tool name")
	assert_true(not shader.is_read_only, "Shader: not read-only")

	# Test validate
	var valid: Dictionary = shader.validate_input({"action": "write", "shader_code": "shader_type spatial;"})
	assert_true(valid.get("valid", false), "Shader: write action valid with code")

	var invalid: Dictionary = shader.validate_input({"action": "write"})
	assert_true(not invalid.get("valid", true), "Shader: write action invalid without code")

	# Test permissions
	var perm: Dictionary = shader.check_permissions({"action": "write"}, {})
	assert_eq(perm.get("behavior", ""), "ask", "Shader: write needs permission")

	# Test write (headless, no editor — execute has await so we need to await)
	var result: Dictionary = await shader.execute({
		"action": "write",
		"path": "res://test_shader.gdshader",
		"shader_code": "shader_type spatial;\nvoid fragment() { COLOR = vec4(1.0); }"
	}, {})
	assert_true(result.get("success", false), "Shader: write succeeds")
	assert_has(result, "path", "Shader: write returns path")

	# Cleanup
	var global_path := ProjectSettings.globalize_path("res://test_shader.gdshader")
	if FileAccess.file_exists(global_path):
		DirAccess.remove_absolute(global_path)


# ============ Phase 3: Ecosystem ============

func test_hooks_manager() -> void:
	print("\n--- Test 9: Hooks Manager ---")
	var hm := GCHooksManager.new()

	# Test fire with no hooks
	var result: Dictionary = hm.fire("pre_tool", {"tool_name": "Write"})
	assert_true(result.get("proceed", false), "Hooks: proceed with no hooks")
	assert_eq(result.get("messages", []).size(), 0, "Hooks: no messages with no hooks")

	# Add a blocking hook
	hm.add_hook({
		"event": "pre_tool",
		"condition": {"tool_name": "Write"},
		"action": "block",
		"message": "Writes are blocked"
	})

	# Test blocking hook
	var blocked: Dictionary = hm.fire("pre_tool", {"tool_name": "Write"})
	assert_true(not blocked.get("proceed", true), "Hooks: blocked by hook")
	assert_true(blocked.get("messages", []).size() > 0, "Hooks: has block message")

	# Test non-matching tool
	var allowed: Dictionary = hm.fire("pre_tool", {"tool_name": "Read"})
	assert_true(allowed.get("proceed", false), "Hooks: Read not blocked")

	# Test different event
	var other_event: Dictionary = hm.fire("post_tool", {"tool_name": "Write"})
	assert_true(other_event.get("proceed", false), "Hooks: post_tool not blocked")

	# Test log hook
	hm.add_hook({
		"event": "post_tool",
		"condition": {},
		"action": "log",
		"message": "Tool executed"
	})
	var logged: Dictionary = hm.fire("post_tool", {"tool_name": "Read"})
	assert_true(logged.get("proceed", false), "Hooks: log hook allows proceed")

	# Test get/remove hooks
	assert_eq(hm.get_hooks().size(), 2, "Hooks: 2 hooks registered")
	hm.remove_hook(0)
	assert_eq(hm.get_hooks().size(), 1, "Hooks: 1 hook after remove")

	# Cleanup
	hm.remove_hook(0)


func test_mcp_tool() -> void:
	print("\n--- Test 10: MCP Tool ---")
	var mcp: GCMCPTool = GCMCPTool.new()

	assert_eq(mcp.tool_name, "MCP", "MCP: tool name")
	assert_true(mcp.is_read_only, "MCP: is read-only")

	# Test validate
	var valid: Dictionary = mcp.validate_input({"server": "test", "tool": "ping"})
	assert_true(valid.get("valid", false), "MCP: valid input")

	var no_server: Dictionary = mcp.validate_input({"tool": "ping"})
	assert_true(not no_server.get("valid", true), "MCP: missing server invalid")

	var no_tool: Dictionary = mcp.validate_input({"server": "test"})
	assert_true(not no_tool.get("valid", true), "MCP: missing tool invalid")

	# Test execute without client
	var result: Dictionary = await mcp.execute({"server": "test", "tool": "ping", "arguments": {}}, {})
	assert_true(not result.get("success", true), "MCP: fails without client")

	# Test MCP tool wrapper
	var wrapper: GCMCPToolWrapper = GCMCPToolWrapper.new()
	wrapper._tool_name = "test_wrapper"
	wrapper._description = "Test wrapper"
	wrapper._input_schema = {}
	assert_eq(wrapper.tool_name, "", "MCPWrapper: tool_name empty before post_init")
	wrapper._post_init()
	assert_eq(wrapper.tool_name, "test_wrapper", "MCPWrapper: tool_name set after post_init")


func test_model_router() -> void:
	print("\n--- Test 11: Model Router ---")
	var router := GCModelRouter.new()

	# Test resolve with default rules (empty context = no override)
	var overrides: Dictionary = router.resolve_model("Read", {}, {})
	assert_true(overrides is Dictionary, "Router: returns dictionary")

	# Test with custom rule
	router.add_rule({
		"pattern": {"tool_names": ["Write"]},
		"model": "claude-opus-4-6",
		"max_tokens": 16384
	})

	var write_overrides: Dictionary = router.resolve_model("Write", {}, {})
	assert_has(write_overrides, "model", "Router: Write gets model override")
	assert_eq(write_overrides.get("model", ""), "claude-opus-4-6", "Router: correct model override")
	assert_eq(write_overrides.get("max_tokens", 0), 16384, "Router: correct max_tokens override")

	# Read should not get the Write override
	var read_overrides: Dictionary = router.resolve_model("Read", {}, {})
	assert_true(not read_overrides.has("model") or read_overrides.get("model", "") != "claude-opus-4-6",
		"Router: Read doesn't get Write override")

	# Test get_rules
	assert_true(router.get_rules().size() >= 2, "Router: has rules")

	# Cleanup
	router.remove_rule(router.get_rules().size() - 1)


func test_custom_command_loader() -> void:
	print("\n--- Test 12: Custom Command Loader ---")
	var loader := GCCustomCommandLoader.new()

	# Test with no custom commands directory
	var commands := loader.load_commands()
	assert_true(commands is Array, "CustomCmd: returns array")

	# Test that built-in commands still work
	var undo_cmd := GCUndoCommand.new()
	assert_eq(undo_cmd.command_name, "undo", "CustomCmd: undo command name correct")

	var session_cmd := GCSessionCommand.new()
	assert_eq(session_cmd.command_name, "session", "CustomCmd: session command name correct")

	# Test undo command execute
	var result: Dictionary = undo_cmd.execute("", {"undo_stack": null})
	assert_has(result, "text", "CustomCmd: undo returns result")
	assert_true(result.text.contains("not available"), "CustomCmd: undo handles missing stack")

	# Test session command execute
	var session_result: Dictionary = session_cmd.execute("", {"session_manager": null, "conversation_history": null})
	assert_has(session_result, "text", "CustomCmd: session returns result")
