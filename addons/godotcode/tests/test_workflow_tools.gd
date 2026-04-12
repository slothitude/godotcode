extends SceneTree
## Test suite for Phase 4 workflow automation tools (12 tools)
## Run: godot --headless --script addons/godotcode/tests/test_workflow_tools.gd

var _pass := 0
var _fail := 0
var _test_dir := ""


func _init() -> void:
	print("\n===== Test: Workflow Automation Tools (12 tools) =====\n")

	# Create temp dir for file-based tests (use user:// protocol)
	_test_dir = ProjectSettings.globalize_path("user://test_workflow")
	DirAccess.make_dir_recursive_absolute(_test_dir)
	# Create a minimal project.godot
	var fa := FileAccess.open(_test_dir + "/project.godot", FileAccess.WRITE)
	fa.store_string("[application]\nconfig/name=\"TestProject\"\n")
	fa.close()

	# Tier 1: Quick Wins
	test_project_scaffold_properties()
	test_project_scaffold_list()
	test_project_scaffold_preview()
	test_project_scaffold_validate()
	test_ui_builder_properties()
	test_ui_builder_list()
	test_ui_builder_validate()
	test_export_properties()
	test_export_validate()
	test_export_detect()
	test_export_status()
	test_input_mapper_properties()
	test_input_mapper_validate()
	test_input_mapper_list()
	test_input_mapper_preset()
	test_input_mapper_add_action()

	# Tier 2: Scene Power-Ups
	test_animation_properties()
	test_animation_validate()
	test_collision_properties()
	test_collision_validate()
	test_collision_define_layers()
	test_audio_properties()
	test_audio_validate()
	test_audio_list_buses()
	test_test_generator_properties()
	test_test_generator_validate()
	test_test_generator_list()
	test_test_generator_suggest()

	# Tier 3: Advanced Workflows
	test_level_properties()
	test_level_validate()
	test_level_info()
	test_level_bsp()
	test_level_cellular()
	test_level_noise()
	test_level_maze()
	test_npc_dialogue_properties()
	test_npc_dialogue_validate()
	test_npc_dialogue_list()
	test_localization_properties()
	test_localization_validate()
	test_localization_list()
	test_performance_properties()
	test_performance_validate()
	test_performance_fps()

	# Cross-cutting: all tools have valid schema
	test_all_tools_schema()

	_cleanup()
	_summary()
	quit(0 if _fail == 0 else 1)


func _ok(cond: bool, name: String, detail: String = "") -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL: %s — %s" % [name, detail])


func _summary() -> void:
	print("\nResults: %d/%d passed" % [_pass, _pass + _fail])
	if _fail > 0:
		print("FAILED")
	else:
		print("ALL PASSED")


func _cleanup() -> void:
	var da := DirAccess.open(_test_dir.get_base_dir())
	if da:
		da.remove(_test_dir)
	# Remove test dir recursively
	_rmdir(_test_dir)


func _rmdir(path: String) -> void:
	var da := DirAccess.open(path)
	if not da:
		return
	da.list_dir_begin()
	var f := da.get_next()
	while f != "":
		if f == "." or f == "..":
			f = da.get_next()
			continue
		var full := path + "/" + f
		if da.current_is_dir():
			_rmdir(full)
		else:
			DirAccess.remove_absolute(full)
		f = da.get_next()
	da.list_dir_end()
	DirAccess.remove_absolute(path)


# ============================================================
# Tier 1: ProjectScaffold
# ============================================================

func test_project_scaffold_properties() -> void:
	print("  ProjectScaffold: properties")
	var t := GCProjectScaffoldTool.new()
	_ok(t.tool_name == "ProjectScaffold", "tool name")
	_ok(t.is_read_only == false, "not read-only")
	_ok(t.description != "", "has description")
	_ok(t.input_schema.has("action"), "has action schema")
	_ok(t.input_schema.has("game_type"), "has game_type schema")


func test_project_scaffold_list() -> void:
	print("  ProjectScaffold: list_templates")
	var t := GCProjectScaffoldTool.new()
	var r: Dictionary = t.execute({"action": "list_templates"}, {})
	_ok(r.get("success", false), "list_templates succeeds")
	_ok(str(r.get("data", "")).find("2d_platformer") >= 0, "contains 2d_platformer")
	_ok(str(r.get("data", "")).find("3d_fps") >= 0, "contains 3d_fps")
	_ok(str(r.get("data", "")).find("puzzle") >= 0, "contains puzzle")


func test_project_scaffold_preview() -> void:
	print("  ProjectScaffold: preview")
	var t := GCProjectScaffoldTool.new()
	var r: Dictionary = t.execute({"action": "preview", "game_type": "2d_platformer"}, {})
	_ok(r.get("success", false), "preview succeeds")
	var data: String = str(r.get("data", ""))
	_ok(data.find("scenes/") >= 0, "mentions scenes")
	_ok(data.find("Input mappings") >= 0, "mentions input mappings")


func test_project_scaffold_validate() -> void:
	print("  ProjectScaffold: validate_input")
	var t := GCProjectScaffoldTool.new()
	var v1: Dictionary = t.validate_input({"action": "scaffold", "game_type": "puzzle"})
	_ok(v1.get("valid", false), "scaffold with game_type valid")
	var v2: Dictionary = t.validate_input({"action": "scaffold"})
	_ok(not v2.get("valid", true), "scaffold without game_type invalid")
	var v3: Dictionary = t.validate_input({"action": ""})
	_ok(not v3.get("valid", true), "empty action invalid")
	var v4: Dictionary = t.validate_input({"action": "list_templates"})
	_ok(v4.get("valid", false), "list_templates valid without game_type")


# ============================================================
# Tier 1: UIBuilder
# ============================================================

func test_ui_builder_properties() -> void:
	print("  UIBuilder: properties")
	var t := GCUIBuilderTool.new()
	_ok(t.tool_name == "UIBuilder", "tool name")
	_ok(t.is_read_only == false, "not read-only")
	_ok(t.input_schema.has("pattern"), "has pattern schema")
	_ok(t.input_schema.has("buttons"), "has buttons schema")


func test_ui_builder_list() -> void:
	print("  UIBuilder: list_patterns")
	var t := GCUIBuilderTool.new()
	var r: Dictionary = t.execute({"action": "list_patterns"}, {})
	_ok(r.get("success", false), "list succeeds")
	var data: String = str(r.get("data", ""))
	_ok(data.find("main_menu") >= 0, "has main_menu")
	_ok(data.find("hud") >= 0, "has hud")
	_ok(data.find("dialog_box") >= 0, "has dialog_box")
	_ok(data.find("inventory") >= 0, "has inventory")


func test_ui_builder_validate() -> void:
	print("  UIBuilder: validate_input")
	var t := GCUIBuilderTool.new()
	_ok(not t.validate_input({"action": "build"}).get("valid", true), "build without pattern invalid")
	_ok(t.validate_input({"action": "build", "pattern": "main_menu"}).get("valid", false), "build with pattern valid")
	_ok(t.validate_input({"action": "list_patterns"}).get("valid", false), "list valid")


# ============================================================
# Tier 1: Export
# ============================================================

func test_export_properties() -> void:
	print("  Export: properties")
	var t := GCExportTool.new()
	_ok(t.tool_name == "Export", "tool name")
	_ok(t.is_read_only == false, "not read-only")
	_ok(t.input_schema.has("platform"), "has platform schema")
	_ok(t.input_schema.has("action"), "has action schema")


func test_export_validate() -> void:
	print("  Export: validate_input")
	var t := GCExportTool.new()
	_ok(not t.validate_input({"action": "export"}).get("valid", true), "export without platform invalid")
	_ok(t.validate_input({"action": "export", "platform": "windows"}).get("valid", false), "export with platform valid")
	_ok(t.validate_input({"action": "list_presets"}).get("valid", false), "list_presets valid")


func test_export_detect() -> void:
	print("  Export: detect_platforms")
	var t := GCExportTool.new()
	var r: Dictionary = t.execute({"action": "detect_platforms"}, {})
	_ok(r.get("success", false), "detect succeeds")
	var platforms: Array = r.get("platforms", [])
	_ok(platforms.size() > 0, "found platforms")
	_ok("windows" in platforms or "linux" in platforms, "has at least windows or linux")


func test_export_status() -> void:
	print("  Export: status")
	var t := GCExportTool.new()
	var r: Dictionary = t.execute({"action": "status"}, {"project_path": _test_dir})
	_ok(r.get("success", false), "status succeeds")


# ============================================================
# Tier 1: InputMapper
# ============================================================

func test_input_mapper_properties() -> void:
	print("  InputMapper: properties")
	var t := GCInputMapperTool.new()
	_ok(t.tool_name == "InputMapper", "tool name")
	_ok(t.is_read_only == false, "not read-only")
	_ok(t.input_schema.has("preset"), "has preset schema")
	_ok(t.input_schema.has("keycode"), "has keycode schema")


func test_input_mapper_validate() -> void:
	print("  InputMapper: validate_input")
	var t := GCInputMapperTool.new()
	_ok(not t.validate_input({"action": "add_action"}).get("valid", true), "add_action without input_action invalid")
	_ok(t.validate_input({"action": "add_action", "input_action": "jump"}).get("valid", false), "add_action with name valid")
	_ok(not t.validate_input({"action": "set_preset"}).get("valid", true), "set_preset without preset invalid")
	_ok(t.validate_input({"action": "set_preset", "preset": "fps"}).get("valid", false), "set_preset with preset valid")


func test_input_mapper_list() -> void:
	print("  InputMapper: list_actions")
	var t := GCInputMapperTool.new()
	var r: Dictionary = t.execute({"action": "list_actions"}, {"project_path": _test_dir})
	_ok(r.get("success", false), "list succeeds")


func test_input_mapper_preset() -> void:
	print("  InputMapper: set_preset")
	var t := GCInputMapperTool.new()
	var r: Dictionary = t.execute({"action": "set_preset", "preset": "platformer"}, {"project_path": _test_dir})
	_ok(r.get("success", false), "set_preset succeeds")
	_ok(str(r.get("data", "")).find("move_left") >= 0, "mentions move_left")
	_ok(str(r.get("data", "")).find("jump") >= 0, "mentions jump")

	# Verify actions were written to project.godot
	var config := ConfigFile.new()
	config.load(_test_dir + "/project.godot")
	_ok(config.has_section_key("input", "move_left"), "move_left written to project.godot")
	_ok(config.has_section_key("input", "jump"), "jump written to project.godot")


func test_input_mapper_add_action() -> void:
	print("  InputMapper: add_action")
	var t := GCInputMapperTool.new()
	var r: Dictionary = t.execute({"action": "add_action", "input_action": "dash", "keycode": 4194322}, {"project_path": _test_dir})
	_ok(r.get("success", false), "add_action succeeds")

	# Verify written
	var config := ConfigFile.new()
	config.load(_test_dir + "/project.godot")
	_ok(config.has_section_key("input", "dash"), "dash written to project.godot")


# ============================================================
# Tier 2: Animation
# ============================================================

func test_animation_properties() -> void:
	print("  Animation: properties")
	var t := GCAnimationTool.new()
	_ok(t.tool_name == "Animation", "tool name")
	_ok(t.is_read_only == false, "not read-only")
	_ok(t.input_schema.has("preset"), "has preset schema")
	_ok(t.input_schema.has("animation_name"), "has animation_name schema")


func test_animation_validate() -> void:
	print("  Animation: validate_input")
	var t := GCAnimationTool.new()
	_ok(not t.validate_input({"action": "create_player"}).get("valid", true), "create_player without node_path invalid")
	_ok(t.validate_input({"action": "create_player", "node_path": "Player"}).get("valid", false), "create_player with path valid")
	_ok(t.validate_input({"action": "list"}).get("valid", false), "list valid")


# ============================================================
# Tier 2: Collision
# ============================================================

func test_collision_properties() -> void:
	print("  Collision: properties")
	var t := GCCollisionTool.new()
	_ok(t.tool_name == "Collision", "tool name")
	_ok(t.is_read_only == false, "not read-only")
	_ok(t.input_schema.has("layers"), "has layers schema")
	_ok(t.input_schema.has("entity_layers"), "has entity_layers schema")


func test_collision_validate() -> void:
	print("  Collision: validate_input")
	var t := GCCollisionTool.new()
	_ok(not t.validate_input({"action": "define_layers"}).get("valid", true), "define_layers without layers invalid")
	_ok(t.validate_input({"action": "define_layers", "layers": {"Player": 1}}).get("valid", false), "define_layers with mapping valid")
	_ok(t.validate_input({"action": "list_layers"}).get("valid", false), "list_layers valid")


func test_collision_define_layers() -> void:
	print("  Collision: define_layers")
	var t := GCCollisionTool.new()
	var r: Dictionary = t.execute({
		"action": "define_layers",
		"layers": {"Player": 1, "Enemy": 2, "Projectile": 3, "Environment": 4}
	}, {"project_path": _test_dir})
	_ok(r.get("success", false), "define_layers succeeds")
	_ok(str(r.get("data", "")).find("Player") >= 0, "mentions Player")
	_ok(str(r.get("data", "")).find("Environment") >= 0, "mentions Environment")

	# Verify project.godot updated
	var config := ConfigFile.new()
	config.load(_test_dir + "/project.godot")
	_ok(config.get_value("physics", "layer_names_2d_physics/layer_1", "") == "Player", "layer 1 is Player")
	_ok(config.get_value("physics", "layer_names_2d_physics/layer_2", "") == "Enemy", "layer 2 is Enemy")


# ============================================================
# Tier 2: Audio
# ============================================================

func test_audio_properties() -> void:
	print("  Audio: properties")
	var t := GCAudioTool.new()
	_ok(t.tool_name == "Audio", "tool name")
	_ok(t.is_read_only == false, "not read-only")
	_ok(t.input_schema.has("bus_name"), "has bus_name schema")
	_ok(t.input_schema.has("effect_type"), "has effect_type schema")


func test_audio_validate() -> void:
	print("  Audio: validate_input")
	var t := GCAudioTool.new()
	_ok(not t.validate_input({"action": ""}).get("valid", true), "empty action invalid")
	_ok(t.validate_input({"action": "list_buses"}).get("valid", false), "list_buses valid")


func test_audio_list_buses() -> void:
	print("  Audio: list_buses")
	var t := GCAudioTool.new()
	var r: Dictionary = t.execute({"action": "list_buses"}, {})
	_ok(r.get("success", false), "list_buses succeeds")
	var data: String = str(r.get("data", ""))
	_ok(data.find("Master") >= 0, "has Master bus")


# ============================================================
# Tier 2: TestGenerator
# ============================================================

func test_test_generator_properties() -> void:
	print("  TestGenerator: properties")
	var t := GCTestGeneratorTool.new()
	_ok(t.tool_name == "TestGenerator", "tool name")
	_ok(t.is_read_only == false, "not read-only")
	_ok(t.input_schema.has("script_path"), "has script_path schema")
	_ok(t.input_schema.has("framework"), "has framework schema")


func test_test_generator_validate() -> void:
	print("  TestGenerator: validate_input")
	var t := GCTestGeneratorTool.new()
	_ok(not t.validate_input({"action": "generate"}).get("valid", true), "generate without path invalid")
	_ok(t.validate_input({"action": "generate", "script_path": "res://test.gd"}).get("valid", false), "generate with path valid")
	_ok(t.validate_input({"action": "list_tests"}).get("valid", false), "list_tests valid")


func test_test_generator_list() -> void:
	print("  TestGenerator: list_tests")
	var t := GCTestGeneratorTool.new()
	var r: Dictionary = t.execute({"action": "list_tests"}, {"project_path": _test_dir})
	_ok(r.get("success", false), "list_tests succeeds")


func test_test_generator_suggest() -> void:
	print("  TestGenerator: suggest_cases (with dummy script)")
	# Create a test script
	var fa := FileAccess.open(_test_dir + "/player.gd", FileAccess.WRITE)
	fa.store_string("class_name Player\nextends CharacterBody2D\n\nvar health: int = 100\n\nfunc take_damage(amount: int) -> void:\n\thealth = maxi(health - amount, 0)\n\nsignal died\n")
	fa.close()

	var t := GCTestGeneratorTool.new()
	var r: Dictionary = t.execute({"action": "suggest_cases", "script_path": _test_dir + "/player.gd"}, {})
	_ok(r.get("success", false), "suggest succeeds")
	var suggestions: Array = r.get("suggestions", [])
	_ok(suggestions.size() > 0, "generated suggestions")
	_ok(str(suggestions).find("test_take_damage") >= 0, "suggests test_take_damage")
	_ok(str(suggestions).find("test_signal_died") >= 0, "suggests test for signal")


# ============================================================
# Tier 3: Level
# ============================================================

func test_level_properties() -> void:
	print("  Level: properties")
	var t := GCLevelTool.new()
	_ok(t.tool_name == "Level", "tool name")
	_ok(t.is_read_only == false, "not read-only")
	_ok(t.input_schema.has("algorithm"), "has algorithm schema")
	_ok(t.input_schema.has("width"), "has width schema")


func test_level_validate() -> void:
	print("  Level: validate_input")
	var t := GCLevelTool.new()
	_ok(not t.validate_input({"action": ""}).get("valid", true), "empty action invalid")
	_ok(t.validate_input({"action": "info"}).get("valid", false), "info valid")
	_ok(not t.validate_input({"action": "populate"}).get("valid", true), "populate without template invalid")
	_ok(t.validate_input({"action": "populate", "scene_template": "res://enemy.tscn"}).get("valid", false), "populate with template valid")


func test_level_info() -> void:
	print("  Level: info")
	var t := GCLevelTool.new()
	var r: Dictionary = t.execute({"action": "info"}, {})
	_ok(r.get("success", false), "info succeeds")
	var data: String = str(r.get("data", ""))
	_ok(data.find("bsp_dungeon") >= 0, "mentions bsp_dungeon")
	_ok(data.find("maze") >= 0, "mentions maze")


func test_level_bsp() -> void:
	print("  Level: BSP dungeon generation")
	var t := GCLevelTool.new()
	var r: Dictionary = t.execute({"action": "generate_layout", "algorithm": "bsp_dungeon", "width": 30, "height": 20, "seed_value": 42}, {})
	_ok(r.get("success", false), "BSP succeeds")
	var grid: Array = r.get("grid", [])
	_ok(grid.size() == 20, "grid height = 20")
	_ok(grid.size() > 0 and grid[0].size() == 30, "grid width = 30")
	# Should have some floor and some wall
	var floor_count := 0
	for row in grid:
		for cell in row:
			if cell == 1:
				floor_count += 1
	_ok(floor_count > 20, "has floor tiles (%d)" % floor_count)
	_ok(floor_count < 30 * 20, "not all floor")


func test_level_cellular() -> void:
	print("  Level: cellular automata generation")
	var t := GCLevelTool.new()
	var r: Dictionary = t.execute({"action": "generate_layout", "algorithm": "cellular_automata", "width": 20, "height": 20, "seed_value": 7}, {})
	_ok(r.get("success", false), "cellular automata succeeds")
	var grid: Array = r.get("grid", [])
	_ok(grid.size() == 20, "grid correct size")


func test_level_noise() -> void:
	print("  Level: noise terrain generation")
	var t := GCLevelTool.new()
	var r: Dictionary = t.execute({"action": "generate_layout", "algorithm": "noise_terrain", "width": 25, "height": 25}, {})
	_ok(r.get("success", false), "noise succeeds")
	_ok(r.get("grid", []).size() == 25, "grid correct height")


func test_level_maze() -> void:
	print("  Level: maze generation")
	var t := GCLevelTool.new()
	var r: Dictionary = t.execute({"action": "generate_layout", "algorithm": "maze", "width": 21, "height": 21, "seed_value": 99}, {})
	_ok(r.get("success", false), "maze succeeds")
	var grid: Array = r.get("grid", [])
	_ok(grid.size() == 21, "grid correct size")
	# Start cell should be floor
	_ok(grid[1][1] == 1, "start cell is floor")


# ============================================================
# Tier 3: NPCDialogue
# ============================================================

func test_npc_dialogue_properties() -> void:
	print("  NPCDialogue: properties")
	var t := GCNPCDialogueTool.new()
	_ok(t.tool_name == "NPCDialogue", "tool name")
	_ok(t.is_read_only == false, "not read-only")
	_ok(t.input_schema.has("npc_name"), "has npc_name schema")
	_ok(t.input_schema.has("personality"), "has personality schema")


func test_npc_dialogue_validate() -> void:
	print("  NPCDialogue: validate_input")
	var t := GCNPCDialogueTool.new()
	_ok(not t.validate_input({"action": "create_dialogue"}).get("valid", true), "create_dialogue without name invalid")
	_ok(t.validate_input({"action": "create_dialogue", "npc_name": "Shopkeeper"}).get("valid", false), "create_dialogue with name valid")
	_ok(t.validate_input({"action": "list_dialogues"}).get("valid", false), "list valid")


func test_npc_dialogue_list() -> void:
	print("  NPCDialogue: list_dialogues")
	var t := GCNPCDialogueTool.new()
	var r: Dictionary = t.execute({"action": "list_dialogues"}, {"project_path": _test_dir})
	_ok(r.get("success", false), "list succeeds")


# ============================================================
# Tier 3: Localization
# ============================================================

func test_localization_properties() -> void:
	print("  Localization: properties")
	var t := GCLocalizationTool.new()
	_ok(t.tool_name == "Localization", "tool name")
	_ok(t.is_read_only == false, "not read-only")
	_ok(t.input_schema.has("target_locale"), "has target_locale schema")
	_ok(t.input_schema.has("locales"), "has locales schema")


func test_localization_validate() -> void:
	print("  Localization: validate_input")
	var t := GCLocalizationTool.new()
	_ok(not t.validate_input({"action": "translate", "locales": "not_array"}).get("valid", true), "translate without locale invalid")
	_ok(t.validate_input({"action": "translate", "target_locale": "es"}).get("valid", false), "translate with locale valid")
	_ok(not t.validate_input({"action": "set_locale"}).get("valid", true), "set_locale without locale invalid")
	_ok(t.validate_input({"action": "extract"}).get("valid", false), "extract valid")


func test_localization_list() -> void:
	print("  Localization: list_locales")
	var t := GCLocalizationTool.new()
	var r: Dictionary = t.execute({"action": "list_locales"}, {"project_path": _test_dir})
	_ok(r.get("success", false), "list succeeds")


# ============================================================
# Tier 3: Performance
# ============================================================

func test_performance_properties() -> void:
	print("  Performance: properties")
	var t := GCPerformanceTool.new()
	_ok(t.tool_name == "Performance", "tool name")
	_ok(t.is_read_only == true, "is read-only")
	_ok(t.input_schema.has("category"), "has category schema")
	_ok(t.input_schema.has("action"), "has action schema")


func test_performance_validate() -> void:
	print("  Performance: validate_input")
	var t := GCPerformanceTool.new()
	_ok(not t.validate_input({"action": ""}).get("valid", true), "empty action invalid")
	_ok(t.validate_input({"action": "fps_report"}).get("valid", false), "fps_report valid")
	_ok(t.validate_input({"action": "profile"}).get("valid", false), "profile valid")


func test_performance_fps() -> void:
	print("  Performance: fps_report")
	var t := GCPerformanceTool.new()
	var r: Dictionary = t.execute({"action": "fps_report"}, {})
	_ok(r.get("success", false), "fps_report succeeds")
	_ok(r.has("fps"), "has fps metric")
	_ok(r.has("frame_time_ms"), "has frame_time_ms")
	_ok(r.has("rating"), "has rating")
	var rating: String = str(r.get("rating", ""))
	_ok(rating in ["Excellent", "Good", "Poor", "Critical"], "valid rating: %s" % rating)


# ============================================================
# Cross-cutting: schema validation
# ============================================================

func test_all_tools_schema() -> void:
	print("  All tools: schema validation")
	var tools := [
		GCProjectScaffoldTool.new(),
		GCUIBuilderTool.new(),
		GCExportTool.new(),
		GCInputMapperTool.new(),
		GCAnimationTool.new(),
		GCCollisionTool.new(),
		GCAudioTool.new(),
		GCTestGeneratorTool.new(),
		GCLevelTool.new(),
		GCNPCDialogueTool.new(),
		GCLocalizationTool.new(),
		GCPerformanceTool.new(),
	]
	for tool in tools:
		var def: Dictionary = tool.to_tool_definition()
		_ok(def.get("name", "") != "", "%s has name in definition" % tool.tool_name)
		_ok(def.get("description", "") != "", "%s has description" % tool.tool_name)
		_ok(def.has("input_schema"), "%s has input_schema" % tool.tool_name)
		var schema: Dictionary = def.get("input_schema", {})
		_ok(schema.has("properties"), "%s schema has properties" % tool.tool_name)
