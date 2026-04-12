class_name GCLocalizationTool
extends GCBaseTool
## Extract translatable strings and generate translation files


func _init() -> void:
	super._init(
		"Localization",
		"Extract translatable strings, generate translation files, and manage locales. Actions: extract, translate, list_locales, set_locale, add_locale.",
		{
			"action": {
				"type": "string",
				"description": "Action: extract (find all tr() strings), translate (generate translations), list_locales, set_locale, add_locale",
				"enum": ["extract", "translate", "list_locales", "set_locale", "add_locale"]
			},
			"target_locale": {
				"type": "string",
				"description": "Target locale code (e.g. 'es', 'fr', 'de', 'ja', 'zh_CN', 'pt_BR')"
			},
			"locales": {
				"type": "array",
				"description": "Array of locale codes to translate to (for translate action)"
			},
			"source_locale": {
				"type": "string",
				"description": "Source locale code (default: 'en')"
			},
			"strings": {
				"type": "object",
				"description": "Manual translation map: {english: translated} for translate action"
			},
			"scan_path": {
				"type": "string",
				"description": "Path to scan for tr() strings (default: res://)"
			}
		}
	)
	is_read_only = false


func validate_input(input: Dictionary) -> Dictionary:
	var action: String = input.get("action", "")
	if action == "":
		return {"valid": false, "error": "action is required"}
	match action:
		"translate":
			if input.get("target_locale", "") == "" and input.get("locales", []) is not Array:
				return {"valid": false, "error": "target_locale or locales is required"}
		"set_locale", "add_locale":
			if input.get("target_locale", "") == "":
				return {"valid": false, "error": "target_locale is required"}
	return {"valid": true}


func check_permissions(input: Dictionary, context: Dictionary) -> Dictionary:
	var action: String = input.get("action", "")
	if action in ["extract", "list_locales"]:
		return {"behavior": "allow"}
	return {"behavior": "ask", "message": "Localization: %s" % action}


func execute(input: Dictionary, context: Dictionary) -> Dictionary:
	var action: String = input.get("action", "")
	var project_path: String = context.get("project_path", "")

	match action:
		"extract":
			return _extract(input, project_path)
		"translate":
			return _translate(input, project_path)
		"list_locales":
			return _list_locales(project_path)
		"set_locale":
			return _set_locale(input, project_path)
		"add_locale":
			return _add_locale(input, project_path)
		_:
			return {"success": false, "error": "Unknown action: %s" % action}


func _extract(input: Dictionary, project_path: String) -> Dictionary:
	var scan_path: String = input.get("scan_path", "")
	if scan_path == "":
		scan_path = project_path
	elif scan_path.begins_with("res://"):
		scan_path = project_path + "/" + scan_path.replace("res://", "")

	var strings: Dictionary = {}  # string -> array of file locations
	_scan_for_tr_strings(scan_path, strings, 0)

	if strings.is_empty():
		return {"success": true, "data": "No translatable strings found (looking for tr() calls)"}

	var lines: Array = ["Extracted %d translatable strings:" % strings.size(), ""]
	for s in strings:
		var locations: Array = strings[s]
		var truncated: String = s if s.length() < 60 else s.substr(0, 57) + "..."
		lines.append("  \"%s\" (%d files)" % [truncated, locations.size()])

	# Save extraction result
	var extraction_path: String = project_path + "/localization/extracted_strings.json"
	DirAccess.make_dir_recursive_absolute(extraction_path.get_base_dir())
	var fa := FileAccess.open(extraction_path, FileAccess.WRITE)
	if fa:
		fa.store_string(JSON.stringify(strings, "\t"))
		fa.close()

	return {"success": true, "data": "\n".join(lines), "strings": strings, "count": strings.size()}


func _translate(input: Dictionary, project_path: String) -> Dictionary:
	var target_locale: String = input.get("target_locale", "")
	var locales: Array = input.get("locales", [])
	var manual_strings: Dictionary = input.get("strings", {})

	if locales.is_empty() and target_locale != "":
		locales = [target_locale]

	if locales.is_empty():
		return {"success": false, "error": "Specify target_locale or locales"}

	# Extract strings first
	var extract_result := _extract(input, project_path)
	var source_strings: Dictionary = extract_result.get("strings", {})
	if source_strings.is_empty():
		# Try loading from previous extraction
		var extraction_path: String = project_path + "/localization/extracted_strings.json"
		if FileAccess.file_exists(extraction_path):
			var fa := FileAccess.open(extraction_path, FileAccess.READ)
			if fa:
				var json := JSON.new()
				json.parse(fa.get_as_text())
				source_strings = json.data if json.data is Dictionary else {}
				fa.close()

	if source_strings.is_empty():
		return {"success": false, "error": "No strings to translate. Use extract first."}

	var created: Array = []

	for locale in locales:
		var locale_str: String = str(locale)
		var translations: Dictionary = {}

		# Use manual translations if provided
		for eng_string in source_strings:
			if manual_strings.has(eng_string) and manual_strings[eng_string] is Dictionary:
				translations[eng_string] = manual_strings[eng_string].get(locale_str, "")
			elif manual_strings.has(eng_string) and manual_strings[eng_string] is String:
				translations[eng_string] = manual_strings[eng_string]
			else:
				# Generate placeholder translation
				translations[eng_string] = "[%s] %s" % [locale_str.to_upper(), eng_string]

		# Generate CSV format for Godot
		var csv_path: String = project_path + "/localization/%s.csv" % locale_str
		DirAccess.make_dir_recursive_absolute(csv_path.get_base_dir())

		var csv_content: String = ""
		for eng_string in translations:
			var translated: String = str(translations[eng_string])
			# CSV escaping
			eng_string = _csv_escape(str(eng_string))
			translated = _csv_escape(translated)
			csv_content += "%s,%s\n" % [eng_string, translated]

		var fa := FileAccess.open(csv_path, FileAccess.WRITE)
		if fa:
			fa.store_string(csv_content)
			fa.close()
			created.append(locale_str)

	return {"success": true, "data": "Created translation files for: %s" % ", ".join(created), "locales": created}


func _list_locales(project_path: String) -> Dictionary:
	var loc_dir: String = project_path + "/localization/"
	var locales: Array = []

	if DirAccess.dir_exists_absolute(loc_dir):
		var da := DirAccess.open(loc_dir)
		if da:
			da.list_dir_begin()
			var f := da.get_next()
			while f != "":
				if f.ends_with(".csv"):
					locales.append(f.replace(".csv", ""))
				f = da.get_next()
			da.list_dir_end()

	# Also check project.godot settings
	var config := ConfigFile.new()
	config.load(project_path + "/project.godot")
	var setting_locale: String = config.get_value("internationalization", "locale/translations", "")

	if locales.is_empty():
		return {"success": true, "data": "No translation files found. Use extract + translate."}

	var lines: Array = ["Available locales (%d):" % locales.size()]
	for loc in locales:
		lines.append("  %s" % loc)
	if setting_locale != "":
		lines.append("\nCurrent project locale: %s" % setting_locale)

	return {"success": true, "data": "\n".join(lines), "locales": locales}


func _set_locale(input: Dictionary, project_path: String) -> Dictionary:
	var locale: String = input.get("target_locale", "")

	var config := ConfigFile.new()
	config.load(project_path + "/project.godot")
	config.set_value("internationalization", "locale/fallback", locale)

	# Add translation resource if CSV exists
	var csv_path: String = "res://localization/%s.csv" % locale
	if FileAccess.file_exists(project_path + "/localization/%s.csv" % locale):
		var existing: String = config.get_value("internationalization", "locale/translations", "")
		if existing == "":
			config.set_value("internationalization", "locale/translations", csv_path)
		elif csv_path not in existing:
			config.set_value("internationalization", "locale/translations", existing + "," + csv_path)

	config.save(project_path + "/project.godot")
	return {"success": true, "data": "Set project locale to '%s'" % locale}


func _add_locale(input: Dictionary, project_path: String) -> Dictionary:
	var locale: String = input.get("target_locale", "")
	# This is an alias for translate with a single locale
	return _translate({"target_locale": locale, "locales": [locale], "strings": input.get("strings", {})}, project_path)


func _scan_for_tr_strings(path: String, strings: Dictionary, depth: int) -> void:
	if depth > 6:
		return
	var da := DirAccess.open(path)
	if not da:
		return
	da.list_dir_begin()
	var f := da.get_next()
	while f != "":
		if f.begins_with(".") or f == ".godot":
			f = da.get_next()
			continue
		var full := path + "/" + f
		if da.current_is_dir():
			_scan_for_tr_strings(full, strings, depth + 1)
		elif f.ends_with(".gd"):
			_extract_tr_from_file(full, strings)
		f = da.get_next()
	da.list_dir_end()


func _extract_tr_from_file(file_path: String, strings: Dictionary) -> void:
	var fa := FileAccess.open(file_path, FileAccess.READ)
	if not fa:
		return
	var source: String = fa.get_as_text()
	fa.close()

	# Find tr("...") and tr('...') patterns
	var patterns := [r"""tr\("([^"]+)"\)""", """tr\\('([^']+)'\\)"""]
	for pattern in patterns:
		var regex := RegEx.new()
		regex.compile(pattern)
		for result in regex.search_all(source):
			if result and result.strings.size() > 1:
				var s: String = result.strings[1]
				if not strings.has(s):
					strings[s] = []
				strings[s].append(file_path)


func _csv_escape(text: String) -> String:
	if text.find(",") >= 0 or text.find("\"") >= 0 or text.find("\n") >= 0:
		return "\"" + text.replace("\"", "\"\"") + "\""
	return text
