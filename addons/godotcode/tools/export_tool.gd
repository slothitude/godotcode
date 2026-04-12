class_name GCExportTool
extends GCBaseTool
## Export game builds for multiple platforms via Godot CLI


func _init() -> void:
	super._init(
		"Export",
		"Export Godot projects for multiple platforms. Actions: list_presets, detect_platforms, create_preset, export, export_all, status.",
		{
			"action": {
				"type": "string",
				"description": "Action: list_presets, detect_platforms, create_preset, export, export_all, status",
				"enum": ["list_presets", "detect_platforms", "create_preset", "export", "export_all", "status"]
			},
			"platform": {
				"type": "string",
				"description": "Target platform: windows, linux, macos, web, android",
				"enum": ["windows", "linux", "macos", "web", "android"]
			},
			"preset_name": {
				"type": "string",
				"description": "Name for the export preset (default: auto-generated from platform)"
			},
			"output_path": {
				"type": "string",
				"description": "Output directory for the export (default: build/)"
			},
			"godot_path": {
				"type": "string",
				"description": "Path to Godot editor executable (auto-detected if not provided)"
			},
			"release": {
				"type": "boolean",
				"description": "Export in release mode (default: true). false = debug export."
			}
		}
	)
	is_read_only = false


func validate_input(input: Dictionary) -> Dictionary:
	var action: String = input.get("action", "")
	if action == "":
		return {"valid": false, "error": "action is required"}
	if action in ["create_preset", "export"] and input.get("platform", "") == "":
		return {"valid": false, "error": "platform is required for %s" % action}
	return {"valid": true}


func check_permissions(input: Dictionary, context: Dictionary) -> Dictionary:
	var action: String = input.get("action", "")
	if action in ["list_presets", "detect_platforms", "status"]:
		return {"behavior": "allow"}
	return {"behavior": "ask", "message": "Export: %s for %s" % [action, input.get("platform", "all")]}


func execute(input: Dictionary, context: Dictionary) -> Dictionary:
	var action: String = input.get("action", "")
	var project_path: String = context.get("project_path", "")

	match action:
		"list_presets":
			return _list_presets(project_path)
		"detect_platforms":
			return _detect_platforms()
		"create_preset":
			return _create_preset(input, project_path)
		"export":
			return _export(input, project_path)
		"export_all":
			return _export_all(input, project_path)
		"status":
			return _status(project_path)
		_:
			return {"success": false, "error": "Unknown action: %s" % action}


func _get_godot_path(input: Dictionary) -> String:
	var path: String = input.get("godot_path", "")
	if path != "":
		return path
	# Try common locations
	var candidates := [
		"C:/Users/aaron/Godot/Godot_v4.6.1-stable_win64.exe",
		"/usr/local/bin/godot",
		"/snap/bin/godot",
	]
	for candidate in candidates:
		if FileAccess.file_exists(candidate):
			return candidate
	return ""


func _list_presets(project_path: String) -> Dictionary:
	var config_path: String = project_path + "/export_presets.cfg"
	if not FileAccess.file_exists(config_path):
		return {"success": true, "data": "No export presets found. Use create_preset to add one."}

	var config := ConfigFile.new()
	if config.load(config_path) != OK:
		return {"success": false, "error": "Cannot read export_presets.cfg"}

	var presets: Array = []
	var sections := config.get_sections()
	for section in sections:
		if section.begins_with("preset."):
			var name: String = config.get_value(section, "name", "Unknown")
			var platform: String = config.get_value(section, "platform", "Unknown")
			presets.append({"name": name, "platform": platform})

	if presets.is_empty():
		return {"success": true, "data": "No export presets configured."}

	var lines: Array = []
	for p in presets:
		lines.append("  %s (%s)" % [p.name, p.platform])
	return {"success": true, "data": "Export presets:\n" + "\n".join(lines), "presets": presets}


func _detect_platforms() -> Dictionary:
	var platforms: Array = []
	if OS.get_name() == "Windows":
		platforms.append("windows")
	platforms.append("linux")
	platforms.append("web")
	platforms.append("android")
	platforms.append("macos")
	return {"success": true, "data": "Available platforms: %s" % ", ".join(platforms), "platforms": platforms}


func _platform_config(platform: String) -> Dictionary:
	var configs := {
		"windows": {
			"platform": "Windows Desktop",
			"extension": ".exe",
		},
		"linux": {
			"platform": "Linux",
			"extension": ".x86_64",
		},
		"macos": {
			"platform": "macOS",
			"extension": ".zip",
		},
		"web": {
			"platform": "Web",
			"extension": ".html",
		},
		"android": {
			"platform": "Android",
			"extension": ".apk",
		}
	}
	return configs.get(platform, {})


func _create_preset(input: Dictionary, project_path: String) -> Dictionary:
	var platform: String = input.get("platform", "")
	var config := _platform_config(platform)
	if config.is_empty():
		return {"success": false, "error": "Unknown platform: %s" % platform}

	var preset_name: String = input.get("preset_name", platform.capitalize())
	var config_path: String = project_path + "/export_presets.cfg"

	var cfg := ConfigFile.new()
	cfg.load(config_path)

	# Find next preset index
	var max_idx := -1
	for section in cfg.get_sections():
		if section.begins_with("preset."):
			var idx: int = section.substr(7).to_int()
			if idx > max_idx:
				max_idx = idx
	var idx := max_idx + 1
	var section := "preset.%d" % idx

	cfg.set_value(section, "name", preset_name)
	cfg.set_value(section, "platform", config.platform)
	cfg.set_value(section, "runnable", true)
	cfg.set_value(section, "dedicated_server", false)
	cfg.set_value(section, "custom_features", "")
	cfg.set_value(section, "export_filter", "all_resources")
	cfg.set_value(section, "include_filter", "")
	cfg.set_value(section, "exclude_filter", "")
	cfg.set_value(section, "encrypt_filter", "")
	cfg.set_value(section, "encryption_include_filters", "")
	cfg.set_value(section, "encryption_exclude_filters", "")
	cfg.set_value(section, "encrypt_pck", false)
	cfg.set_value(section, "encrypt_directory", false)
	cfg.set_value(section, "script_export_mode", 2)

	# Platform-specific options
	var opt_section := "preset.%d.options" % idx
	if platform == "windows":
		cfg.set_value(opt_section, "binary_format/64_bits", true)
		cfg.set_value(opt_section, "custom_template/debug", "")
		cfg.set_value(opt_section, "custom_template/release", "")
		cfg.set_value(opt_section, "codesign/enable", false)
		cfg.set_value(opt_section, "application/icon", "")
		cfg.set_value(opt_section, "application/file_version", "")
		cfg.set_value(opt_section, "application/product_version", "")
		cfg.set_value(opt_section, "application/company_name", "")
		cfg.set_value(opt_section, "application/product_name", "")
	elif platform == "web":
		cfg.set_value(opt_section, "custom_template/debug", "")
		cfg.set_value(opt_section, "custom_template/release", "")
		cfg.set_value(opt_section, "variant/extensions_enabled", false)
		cfg.set_value(opt_section, "html/export_icon", true)
		cfg.set_value(opt_section, "html/canvas_resize_policy", 2)
		cfg.set_value(opt_section, "html/focus_canvas_on_start", true)
		cfg.set_value(opt_section, "html/experimental_virtual_keyboard", false)
	elif platform == "linux":
		cfg.set_value(opt_section, "binary_format/architecture", "x86_64")
		cfg.set_value(opt_section, "custom_template/debug", "")
		cfg.set_value(opt_section, "custom_template/release", "")
	elif platform == "android":
		cfg.set_value(opt_section, "custom_template/debug", "")
		cfg.set_value(opt_section, "custom_template/release", "")
		cfg.set_value(opt_section, "gradle_build/use_gradle_build", false)
		cfg.set_value(opt_section, "package/unique_name", "com.example.game")
		cfg.set_value(opt_section, "package/name", "")
		cfg.set_value(opt_section, "architectures/armeabi-v7a", false)
		cfg.set_value(opt_section, "architectures/arm64-v8a", true)
		cfg.set_value(opt_section, "architectures/x86", false)
		cfg.set_value(opt_section, "architectures/x86_64", false)
	elif platform == "macos":
		cfg.set_value(opt_section, "custom_template/debug", "")
		cfg.set_value(opt_section, "custom_template/release", "")
		cfg.set_value(opt_section, "application/icon", "")
		cfg.set_value(opt_section, "application/bundle_identifier", "com.example.game")
		cfg.set_value(opt_section, "application/sign_identity", "")

	# Set export path
	var output_path: String = input.get("output_path", "build/")
	var ext: String = config.get("extension", "")
	var export_path := output_path + preset_name.to_snake_case() + ext
	cfg.set_value(section, "export_path", export_path)

	var err := cfg.save(config_path)
	if err != OK:
		return {"success": false, "error": "Failed to write export_presets.cfg (error %d)" % err}

	return {"success": true, "data": "Created export preset '%s' for %s at %s" % [preset_name, platform, export_path]}


func _export(input: Dictionary, project_path: String) -> Dictionary:
	var godot_path: String = _get_godot_path(input)
	if godot_path == "":
		return {"success": false, "error": "Godot executable not found. Set godot_path parameter."}

	var platform: String = input.get("platform", "")
	var release: bool = input.get("release", true)
	var preset_name: String = input.get("preset_name", platform)

	# Resolve output path from preset's export_path in export_presets.cfg
	var output_path: String = input.get("output_path", "")
	if output_path == "":
		output_path = _get_preset_export_path(preset_name, project_path)
	if output_path == "":
		# Fallback: derive from platform
		var config := _platform_config(platform)
		output_path = "build/" + preset_name.to_snake_case() + config.get("extension", "")

	# Ensure output directory exists
	var global_output := output_path
	if not global_output.is_absolute_path():
		global_output = project_path + "/" + output_path
	DirAccess.make_dir_recursive_absolute(global_output.get_base_dir())

	var export_flag := "--export-release" if release else "--export-debug"

	var exit_code := -1
	var thread := Thread.new()
	var thread_result: Dictionary = {}

	thread.start(func():
		var o: PackedByteArray = []
		var args := PackedStringArray([
			"--headless",
			export_flag, preset_name, output_path,
			"--path", project_path
		])
		exit_code = OS.execute(godot_path, args, o, true)
		thread_result["stdout"] = o.get_string_from_utf8() if o.size() > 0 else ""
		thread_result["exit_code"] = exit_code
	)

	var start_time := Time.get_ticks_msec()
	while thread.is_alive():
		if Time.get_ticks_msec() - start_time > 120000:
			return {"success": false, "error": "Export timed out after 120 seconds"}
		OS.delay_msec(100)

	thread.wait_to_finish()

	exit_code = thread_result.get("exit_code", -1)
	var stdout: String = thread_result.get("stdout", "")

	if exit_code != 0:
		# Try fallback with --editor --headless if plain --headless failed
		# (Godot requires editor init to load export presets in some versions)
		if "Invalid export preset" in stdout or "0 presets" in stdout:
			return _export_via_editor(godot_path, export_flag, preset_name, output_path, project_path)
		return {"success": false, "error": "Export failed (exit %d): %s" % [exit_code, stdout]}

	return {"success": true, "data": "Successfully exported '%s' (%s)" % [preset_name, platform], "output": output_path}


func _export_via_editor(godot_path: String, export_flag: String, preset_name: String, output_path: String, project_path: String) -> Dictionary:
	## Fallback: write a temporary export script and run via --editor --headless
	var script_path := project_path + "/.godotcode_export_temp.gd"
	var script_content := "extends SceneTree\n\nfunc _initialize() -> void:\n"
	script_content += "\tvar o: PackedByteArray = []\n"
	script_content += "\tvar ec: int = OS.execute(OS.get_executable_path(), PackedStringArray([\n"
	script_content += "\t\t\"--headless\",\n"
	script_content += "\t\t\"%s\", \"%s\", \"%s\",\n" % [export_flag, preset_name, output_path]
	script_content += "\t\t\"--path\", \"%s\"\n" % project_path
	script_content += "\t]), o, false)\n"
	script_content += "\tvar s: String = o.get_string_from_utf8() if o.size() > 0 else \"\"\n"
	script_content += "\tprint(s)\n"
	script_content += "\tquit(ec)\n"

	var fa := FileAccess.open(script_path, FileAccess.WRITE)
	if not fa:
		return {"success": false, "error": "Cannot write temp export script"}
	fa.store_string(script_content)
	fa.close()

	var exit_code: int = -1
	var o: PackedByteArray = []
	var args := PackedStringArray([
		"--editor", "--headless",
		"--script", script_path,
		"--path", project_path
	])
	exit_code = OS.execute(godot_path, args, o, true)
	var stdout_str: String = o.get_string_from_utf8() if o.size() > 0 else ""

	# Cleanup temp script
	DirAccess.remove_absolute(script_path)

	if exit_code != 0:
		return {"success": false, "error": "Export failed via editor (exit %d): %s" % [exit_code, stdout_str]}
	return {"success": true, "data": "Successfully exported '%s'" % preset_name, "output": output_path}


func _get_preset_export_path(preset_name: String, project_path: String) -> String:
	var config_path: String = project_path + "/export_presets.cfg"
	var config := ConfigFile.new()
	if config.load(config_path) != OK:
		return ""
	for section in config.get_sections():
		if config.get_value(section, "name", "") == preset_name:
			return config.get_value(section, "export_path", "")
	return ""


func _export_all(input: Dictionary, project_path: String) -> Dictionary:
	var godot_path: String = _get_godot_path(input)
	if godot_path == "":
		return {"success": false, "error": "Godot executable not found. Set godot_path parameter."}

	# Read configured presets
	var presets_result := _list_presets(project_path)
	var presets: Array = presets_result.get("presets", [])
	if presets.is_empty():
		return {"success": false, "error": "No export presets found. Use create_preset first."}

	var results: Array = []
	for preset in presets:
		var preset_name: String = preset.get("name", "")
		var platform: String = preset.get("platform", "")
		var output_path: String = _get_preset_export_path(preset_name, project_path)
		var export_input := {
			"platform": platform,
			"preset_name": preset_name,
			"output_path": output_path,
			"release": input.get("release", true),
			"godot_path": godot_path,
		}
		var result := _export(export_input, project_path)
		results.append(result)

	var successes := results.filter(func(r): return r.get("success", false))
	var failures := results.filter(func(r): return not r.get("success", false))

	var msg := "Exported %d/%d presets successfully" % [successes.size(), results.size()]
	if not failures.is_empty():
		msg += "\nFailures:\n"
		for f in failures:
			msg += "  - %s\n" % str(f.get("error", "Unknown"))

	return {"success": failures.is_empty(), "data": msg}


func _status(project_path: String) -> Dictionary:
	var lines: Array = []

	# Check for export presets
	var config_path: String = project_path + "/export_presets.cfg"
	if FileAccess.file_exists(config_path):
		lines.append("export_presets.cfg: found")
		var presets_result := _list_presets(project_path)
		lines.append("  Presets: %d" % presets_result.get("presets", []).size())
	else:
		lines.append("export_presets.cfg: not found")

	# Check for build directory
	var build_dir: String = project_path + "/build"
	if DirAccess.dir_exists_absolute(build_dir):
		var da := DirAccess.open(build_dir)
		if da:
			var files: Array = []
			da.list_dir_begin()
			var f := da.get_next()
			while f != "":
				if not da.current_is_dir():
					files.append(f)
				f = da.get_next()
			da.list_dir_end()
			lines.append("build/: %d files" % files.size())
			for file in files:
				lines.append("  %s" % file)
	else:
		lines.append("build/: not found")

	return {"success": true, "data": "\n".join(lines)}
