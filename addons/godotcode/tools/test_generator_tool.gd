class_name GCTestGeneratorTool
extends GCBaseTool
## Generate GDUnit4 test files from existing scripts


func _init() -> void:
	super._init(
		"TestGenerator",
		"Generate GDUnit4 test files for scripts. Actions: generate, list_tests, suggest_cases.",
		{
			"action": {
				"type": "string",
				"description": "Action: generate (create test file), list_tests (find existing tests), suggest_cases (analyze and suggest test cases)",
				"enum": ["generate", "list_tests", "suggest_cases"]
			},
			"script_path": {
				"type": "string",
				"description": "Path to the script to generate tests for (e.g. res://scripts/player.gd)"
			},
			"test_path": {
				"type": "string",
				"description": "Output path for test file (default: addons/godotcode/tests/unit/test_<name>.gd)"
			},
			"test_cases": {
				"type": "array",
				"description": "Specific test case names to generate (e.g. ['test_jump', 'test_take_damage'])"
			},
			"include_edge_cases": {
				"type": "boolean",
				"description": "Include edge case tests (default: true)"
			},
			"framework": {
				"type": "string",
				"description": "Test framework: gdunit4, headless (default: gdunit4)",
				"enum": ["gdunit4", "headless"]
			}
		}
	)
	is_read_only = false


func validate_input(input: Dictionary) -> Dictionary:
	var action: String = input.get("action", "")
	if action == "":
		return {"valid": false, "error": "action is required"}
	if action in ["generate", "suggest_cases"] and input.get("script_path", "") == "":
		return {"valid": false, "error": "script_path is required for %s" % action}
	return {"valid": true}


func check_permissions(input: Dictionary, context: Dictionary) -> Dictionary:
	var action: String = input.get("action", "")
	if action == "list_tests":
		return {"behavior": "allow"}
	return {"behavior": "ask", "message": "Test Generator: %s" % action}


func execute(input: Dictionary, context: Dictionary) -> Dictionary:
	var action: String = input.get("action", "")
	var project_path: String = context.get("project_path", "")

	match action:
		"generate":
			return _generate(input, project_path)
		"list_tests":
			return _list_tests(project_path)
		"suggest_cases":
			return _suggest_cases(input)
		_:
			return {"success": false, "error": "Unknown action: %s" % action}


func _generate(input: Dictionary, project_path: String) -> Dictionary:
	var script_path: String = input.get("script_path", "")
	var framework: String = input.get("framework", "gdunit4")
	var include_edge: bool = input.get("include_edge_cases", true)

	# Read source script
	var global_path := script_path
	if script_path.begins_with("res://") and project_path != "":
		global_path = project_path + "/" + script_path.replace("res://", "")

	var fa := FileAccess.open(global_path, FileAccess.READ)
	if not fa:
		return {"success": false, "error": "Cannot read script: %s" % script_path}

	var source: String = fa.get_as_text()
	fa.close()

	var analysis := _analyze_script(source)
	var test_content: String = ""

	if framework == "gdunit4":
		test_content = _generate_gdunit4(analysis, input, include_edge)
	else:
		test_content = _generate_headless(analysis, input, include_edge)

	# Determine output path
	var test_path: String = input.get("test_path", "")
	if test_path == "":
		var script_name: String = script_path.get_file().replace(".gd", "")
		test_path = "addons/godotcode/tests/unit/test_%s.gd" % script_name

	var global_test_path := test_path
	if test_path.begins_with("res://") and project_path != "":
		global_test_path = project_path + "/" + test_path.replace("res://", "")

	# Ensure directory exists
	DirAccess.make_dir_recursive_absolute(global_test_path.get_base_dir())

	var tfa := FileAccess.open(global_test_path, FileAccess.WRITE)
	if not tfa:
		return {"success": false, "error": "Cannot write test file: %s" % global_test_path}
	tfa.store_string(test_content)
	tfa.close()

	return {"success": true, "data": "Generated test file: %s (%d test cases)" % [test_path, analysis.test_count], "path": test_path}


func _list_tests(project_path: String) -> Dictionary:
	var test_dirs := ["addons/godotcode/tests/unit/", "addons/godotcode/tests/", "test/", "tests/"]
	var tests: Array = []

	for test_dir in test_dirs:
		var dir_path: String = project_path + "/" + test_dir
		_scan_test_files(dir_path, tests)

	if tests.is_empty():
		return {"success": true, "data": "No test files found"}

	return {"success": true, "data": "Test files:\n" + "\n".join(tests), "count": tests.size()}


func _suggest_cases(input: Dictionary) -> Dictionary:
	var script_path: String = input.get("script_path", "")
	var fa := FileAccess.open(script_path, FileAccess.READ)
	if not fa:
		# Try with project path
		fa = FileAccess.open(script_path, FileAccess.READ)
	if not fa:
		return {"success": false, "error": "Cannot read: %s" % script_path}

	var source: String = fa.get_as_text()
	fa.close()

	var analysis := _analyze_script(source)
	var suggestions: Array = []

	for func_name in analysis.functions:
		suggestions.append("test_%s" % func_name)
		if input.get("include_edge_cases", true):
			suggestions.append("test_%s_edge_cases" % func_name)

	# Add general suggestions
	if analysis.has_ready:
		suggestions.append("test_initialization")
	if analysis.has_physics:
		suggestions.append("test_physics_movement")
	if analysis.has_signals:
		for sig in analysis.signals:
			suggestions.append("test_signal_%s" % sig)

	return {"success": true, "data": "Suggested test cases:\n" + "\n".join(suggestions), "suggestions": suggestions}


class _ScriptAnalysis:
	var class_name_str: String = ""
	var functions: Array = []
	var signals: Array = []
	var variables: Array = []
	var exports: Array = []
	var has_ready: bool = false
	var has_physics: bool = false
	var has_signals: bool = false
	var test_count: int = 0


func _analyze_script(source: String) -> _ScriptAnalysis:
	var analysis := _ScriptAnalysis.new()
	var lines := source.split("\n")

	for line in lines:
		var stripped: String = line.strip_edges()

		# Class name
		if stripped.begins_with("class_name "):
			analysis.class_name_str = stripped.substr(11).strip_edges()

		# Functions
		if stripped.begins_with("func "):
			var func_name: String = stripped.substr(5).split("(")[0].strip_edges()
			if func_name != "":
				analysis.functions.append(func_name)
				if func_name == "_ready":
					analysis.has_ready = true
				elif func_name.begins_with("_physics") or func_name.begins_with("_process"):
					analysis.has_physics = true

		# Signals
		if stripped.begins_with("signal "):
			var sig_name: String = stripped.substr(7).split("(")[0].strip_edges()
			if sig_name != "":
				analysis.signals.append(sig_name)
				analysis.has_signals = true

		# Variables
		if stripped.begins_with("var ") and not stripped.begins_with("var _"):
			var var_name: String = stripped.substr(4).split(":")[0].split("=")[0].strip_edges()
			if var_name != "":
				analysis.variables.append(var_name)

		# Exports
		if stripped.begins_with("@export"):
			var rest: String = stripped.substr(stripped.find("var ") + 4)
			var var_name: String = rest.split(":")[0].split("=")[0].strip_edges()
			if var_name != "":
				analysis.exports.append(var_name)

	return analysis


func _generate_gdunit4(analysis: _ScriptAnalysis, input: Dictionary, include_edge: bool) -> String:
	var subject_name: String = analysis.class_name_str
	if subject_name == "":
		subject_name = "TestSubject"

	var test_cases: Array = input.get("test_cases", [])
	if test_cases.is_empty():
		test_cases = _auto_generate_cases(analysis, include_edge)

	analysis.test_count = test_cases.size()

	var content := "extends GDScript\n"
	content += "## Auto-generated tests for %s\n\n" % subject_name
	content += "var subject: %s\n\n" % subject_name
	content += "func before_test() -> void:\n\tpass\n\n"
	content += "func after_test() -> void:\n\tpass\n\n"

	for test_name in test_cases:
		var tn: String = str(test_name)
		if not tn.begins_with("test_"):
			tn = "test_" + tn
		content += "func %s() -> void:\n" % tn
		content += "\tassert_true(true, \"Placeholder: implement %s\")\n\n" % tn

	return content


func _generate_headless(analysis: _ScriptAnalysis, input: Dictionary, include_edge: bool) -> String:
	var subject_name: String = analysis.class_name_str
	if subject_name == "":
		subject_name = "TestSubject"

	var test_cases: Array = input.get("test_cases", [])
	if test_cases.is_empty():
		test_cases = _auto_generate_cases(analysis, include_edge)

	analysis.test_count = test_cases.size()

	var content := "extends SceneTree\n"
	content += "## Headless test runner for %s\n\n" % subject_name
	content += "var _pass_count: int = 0\n"
	content += "var _fail_count: int = 0\n\n"
	content += "func _initialize() -> void:\n"
	content += "\tprint(\"\\n=== Tests for %s ===\\n\")\n" % subject_name

	for test_name in test_cases:
		var tn: String = str(test_name)
		if not tn.begins_with("test_"):
			tn = "test_" + tn
		content += "\t%s()\n" % tn

	content += "\t_print_results()\n\tquit()\n\n"
	content += "func _assert_true(condition: bool, test_name: String, message: String = \"\") -> void:\n"
	content += "\tif condition:\n\t\t_pass_count += 1\n"
	content += "\t\tprint(\"  PASS: %s\" % test_name)\n"
	content += "\telse:\n\t\t_fail_count += 1\n"
	content += "\t\tprint(\"  FAIL: %s\" % test_name)\n\n"
	content += "func _print_results() -> void:\n"
	content += "\tprint(\"\\n=== Results ===\")\n"
	content += "\tprint(\"Passed: %d / %d\" % [_pass_count, _pass_count + _fail_count])\n\n"

	for test_name in test_cases:
		var tn: String = str(test_name)
		if not tn.begins_with("test_"):
			tn = "test_" + tn
		content += "func %s() -> void:\n" % tn
		content += "\t_assert_true(true, \"%s\", \"Placeholder\")\n\n" % tn

	return content


func _auto_generate_cases(analysis: _ScriptAnalysis, include_edge: bool) -> Array:
	var cases: Array = []

	for func_name in analysis.functions:
		if func_name.begins_with("_"):
			continue  # Skip private functions for basic tests
		cases.append("test_%s" % func_name)

	if analysis.has_ready:
		cases.append("test_initialization")

	if analysis.has_physics:
		cases.append("test_physics_movement")

	for sig in analysis.signals:
		cases.append("test_signal_%s_emitted" % sig)

	for var_name in analysis.variables:
		cases.append("test_%s_default_value" % var_name)

	if include_edge:
		if analysis.has_physics:
			cases.append("test_zero_delta")
			cases.append("test_negative_values")
		cases.append("test_boundary_conditions")

	return cases


func _scan_test_files(dir_path: String, results: Array) -> void:
	var da := DirAccess.open(dir_path)
	if not da:
		return
	da.list_dir_begin()
	var f := da.get_next()
	while f != "":
		if f.begins_with("."):
			f = da.get_next()
			continue
		var full := dir_path + f
		if da.current_is_dir():
			_scan_test_files(full + "/", results)
		elif f.begins_with("test_") and f.ends_with(".gd"):
			results.append(full)
		f = da.get_next()
	da.list_dir_end()
