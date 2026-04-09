extends Control
## Permission system integration test

@onready var _output: RichTextLabel = $VBox/Output
@onready var _run_btn: Button = $VBox/RunBtn

var _perm_mgr: GCPermissionManager
var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_run_btn.pressed.connect(_run_tests)
	_perm_mgr = GCPermissionManager.new()


func _run_tests() -> void:
	_passed = 0
	_failed = 0
	_log("\n== Running Permission Tests ==")

	# Test read-only tools auto-approve
	var read_perm := _perm_mgr.check_tool_permission("Read", {}, {})
	_assert(read_perm.behavior == "allow", "Read tool auto-approved")

	var glob_perm := _perm_mgr.check_tool_permission("Glob", {}, {})
	_assert(glob_perm.behavior == "allow", "Glob tool auto-approved")

	# Test write tools require approval
	var write_perm := _perm_mgr.check_tool_permission("Write", {}, {})
	_assert(write_perm.behavior == "ask", "Write tool requires approval")

	var bash_perm := _perm_mgr.check_tool_permission("Bash", {"command": "echo hi"}, {})
	_assert(bash_perm.behavior == "ask", "Bash tool requires approval")

	# Test custom rules
	_perm_mgr.set_rule("Read", "deny")
	var denied := _perm_mgr.check_tool_permission("Read", {}, {})
	_assert(denied.behavior == "deny", "Read tool denied after rule change")
	_perm_mgr.set_rule("Read", "allow")  # Reset

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
