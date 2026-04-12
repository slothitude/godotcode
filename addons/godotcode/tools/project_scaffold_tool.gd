class_name GCProjectScaffoldTool
extends GCBaseTool
## Generate project structure from game type templates


func _init() -> void:
	super._init(
		"ProjectScaffold",
		"Scaffold a new game project with folder structure, project.godot config, input mappings, autoload singletons, and base scenes. Actions: scaffold, list_templates, preview.",
		{
			"action": {
				"type": "string",
				"description": "Action: scaffold (generate project), list_templates (show available types), preview (show what scaffold would create)",
				"enum": ["scaffold", "list_templates", "preview"]
			},
			"game_type": {
				"type": "string",
				"description": "Game template: 2d_platformer, 3d_fps, top_down_rpg, puzzle, top_down_shooter, side_scroller, visual_novel, strategy, racing, fighting",
				"enum": ["2d_platformer", "3d_fps", "top_down_rpg", "puzzle", "top_down_shooter", "side_scroller", "visual_novel", "strategy", "racing", "fighting"]
			},
			"project_name": {
				"type": "string",
				"description": "Project name (used for window title and folder naming)"
			},
			"resolution": {
				"type": "string",
				"description": "Viewport resolution as WxH (default: 1920x1080)"
			},
			"include_autoloads": {
				"type": "boolean",
				"description": "Generate autoload singletons like GameManager, AudioManager (default: true)"
			},
			"include_ui": {
				"type": "boolean",
				"description": "Generate main menu and HUD scenes (default: true)"
			}
		}
	)
	is_read_only = false


func validate_input(input: Dictionary) -> Dictionary:
	var action: String = input.get("action", "")
	if action == "":
		return {"valid": false, "error": "action is required"}
	if action == "scaffold" and input.get("game_type", "") == "":
		return {"valid": false, "error": "game_type is required for scaffold"}
	return {"valid": true}


func check_permissions(input: Dictionary, context: Dictionary) -> Dictionary:
	var action: String = input.get("action", "")
	if action == "list_templates":
		return {"behavior": "allow"}
	return {"behavior": "ask", "message": "Project scaffold: %s for %s" % [action, input.get("game_type", "")]}


func execute(input: Dictionary, context: Dictionary) -> Dictionary:
	var action: String = input.get("action", "")
	var project_path: String = context.get("project_path", "")

	match action:
		"list_templates":
			return _list_templates()
		"preview":
			return _preview(input, project_path)
		"scaffold":
			return _scaffold(input, project_path)
		_:
			return {"success": false, "error": "Unknown action: %s" % action}


func _list_templates() -> Dictionary:
	var templates := {
		"2d_platformer": "2D Platformer — CharacterBody2D, TileMap, Camera, parallax backgrounds",
		"3d_fps": "3D First-Person Shooter — CharacterBody3D, RayCast weapons, FPS camera",
		"top_down_rpg": "Top-Down RPG — CharacterBody2D/3D, tile-based movement, dialogue, inventory",
		"puzzle": "Puzzle Game — Grid-based logic, tween animations, level system",
		"top_down_shooter": "Top-Down Shooter — Twin-stick controls, projectiles, wave spawning",
		"side_scroller": "Side-Scroller — Auto-scroll or controlled, obstacle spawning",
		"visual_novel": "Visual Novel — Dialogue system, character portraits, choice branching",
		"strategy": "Strategy Game — Grid/RTS, unit selection, resource management",
		"racing": "Racing Game — PathFollow camera, track generation, lap system",
		"fighting": "Fighting Game — Hitbox/hurtbox, combo system, health bars",
	}
	var lines: Array = []
	for key in templates:
		lines.append("  %s: %s" % [key, templates[key]])
	return {"success": true, "data": "Available templates:\n" + "\n".join(lines)}


func _preview(input: Dictionary, project_path: String) -> Dictionary:
	var game_type: String = input.get("game_type", "")
	var plan := _get_scaffold_plan(game_type, input)
	var lines: Array = ["Scaffold plan for '%s':" % game_type, ""]
	lines.append("Folders:")
	for folder in plan.folders:
		lines.append("  + %s/" % folder)
	lines.append("")
	lines.append("Files:")
	for file in plan.files:
		lines.append("  + %s" % file)
	lines.append("")
	if not plan.input_actions.is_empty():
		lines.append("Input mappings:")
		for action_name in plan.input_actions:
			lines.append("  + %s: %s" % [action_name, str(plan.input_actions[action_name])])
	return {"success": true, "data": "\n".join(lines)}


func _scaffold(input: Dictionary, project_path: String) -> Dictionary:
	var game_type: String = input.get("game_type", "")
	var project_name: String = input.get("project_name", "MyGame")
	var plan := _get_scaffold_plan(game_type, input)
	var created: Array = []
	var errors: Array = []

	# Create folders
	for folder in plan.folders:
		var dir_path: String = project_path + "/" + folder
		if DirAccess.make_dir_recursive_absolute(dir_path) == OK:
			created.append("dir: %s/" % folder)
		else:
			errors.append("Failed to create: %s/" % folder)

	# Create files
	for file_path in plan.files:
		var full_path: String = project_path + "/" + file_path
		var content: String = plan.file_contents.get(file_path, "")
		var fa := FileAccess.open(full_path, FileAccess.WRITE)
		if fa:
			fa.store_string(content)
			fa.close()
			created.append("file: %s" % file_path)
		else:
			errors.append("Failed to write: %s" % file_path)

	# Update project.godot with input mappings
	_patch_project_godot(project_path, plan, project_name, input)

	var msg := "Scaffolded '%s' (%s):\n" % [project_name, game_type]
	msg += "Created %d folders, %d files" % [plan.folders.size(), plan.files.size()]
	if not errors.is_empty():
		msg += "\nErrors:\n" + "\n".join(errors)
	return {"success": errors.is_empty(), "data": msg, "created": created}


class _ScaffoldPlan:
	var folders: Array = []
	var files: Array = []
	var file_contents: Dictionary = {}
	var input_actions: Dictionary = {}
	var autoloads: Dictionary = {}


func _get_scaffold_plan(game_type: String, input: Dictionary) -> _ScaffoldPlan:
	var plan := _ScaffoldPlan.new()
	var include_autoloads: bool = input.get("include_autoloads", true)
	var include_ui: bool = input.get("include_ui", true)
	var res: String = input.get("resolution", "1920x1080")
	var dims := res.split("x")
	var width: int = 1920
	var height: int = 1080
	if dims.size() == 2:
		width = int(dims[0])
		height = int(dims[1])

	# Common folders
	plan.folders = ["scenes", "scripts", "scripts/autoload", "scripts/components",
		"assets", "assets/sprites", "assets/audio", "assets/audio/music",
		"assets/audio/sfx", "assets/fonts", "assets/shaders"]

	match game_type:
		"2d_platformer":
			plan = _plan_2d_platformer(plan, width, height, include_autoloads, include_ui)
		"3d_fps":
			plan = _plan_3d_fps(plan, width, height, include_autoloads, include_ui)
		"top_down_rpg":
			plan = _plan_top_down_rpg(plan, width, height, include_autoloads, include_ui)
		"puzzle":
			plan = _plan_puzzle(plan, width, height, include_autoloads, include_ui)
		"top_down_shooter":
			plan = _plan_top_down_shooter(plan, width, height, include_autoloads, include_ui)
		"side_scroller":
			plan = _plan_side_scroller(plan, width, height, include_autoloads, include_ui)
		"visual_novel":
			plan = _plan_visual_novel(plan, width, height, include_autoloads, include_ui)
		"strategy":
			plan = _plan_strategy(plan, width, height, include_autoloads, include_ui)
		"racing":
			plan = _plan_racing(plan, width, height, include_autoloads, include_ui)
		"fighting":
			plan = _plan_fighting(plan, width, height, include_autoloads, include_ui)

	return plan


func _add_autoloads(plan: _ScaffoldPlan, autoloads: Array) -> void:
	for autoload in autoloads:
		var name: String = autoload[0]
		var script: String = autoload[1]
		var path := "scripts/autoload/%s.gd" % name.to_snake_case()
		plan.files.append(path)
		plan.file_contents[path] = autoload[2] if autoload.size() > 2 else _autoload_stub(name)
		plan.autoloads[name] = "*res://%s" % path


func _autoload_stub(name: String) -> String:
	return """extends Node
## Autoload singleton: %s

func _ready() -> void:
	pass
""" % name


func _player_script_2d(speed: float, jump_velocity: float) -> String:
	return """extends CharacterBody2D

const SPEED := %.1f
const JUMP_VELOCITY := %.1f

var gravity: float = ProjectSettings.get_setting(\"physics/2d/default_gravity\")

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += gravity * delta
	if Input.is_action_just_pressed(\"jump\") and is_on_floor():
		velocity.y = JUMP_VELOCITY
	var direction := Input.get_axis(\"move_left\", \"move_right\")
	velocity.x = direction * SPEED
	move_and_slide()
""" % [speed, jump_velocity]


func _main_scene_script() -> String:
	return """extends Node2D

func _ready() -> void:
	pass
"""


func _game_manager_script() -> String:
	return """extends Node
## Game state manager

signal game_started
signal game_paused
signal game_resumed
signal game_over

enum State { MENU, PLAYING, PAUSED, GAME_OVER }
var current_state: State = State.MENU
var score: int = 0

func start_game() -> void:
	current_state = State.PLAYING
	score = 0
	game_started.emit()

func pause_game() -> void:
	current_state = State.PAUSED
	get_tree().paused = true
	game_paused.emit()

func resume_game() -> void:
	current_state = State.PLAYING
	get_tree().paused = false
	game_resumed.emit()

func end_game() -> void:
	current_state = State.GAME_OVER
	game_over.emit()
"""


func _audio_manager_script() -> String:
	return """extends Node
## Audio management singleton

var music_volume: float = 1.0
var sfx_volume: float = 1.0

func play_sfx(stream: AudioStream, position: Vector2 = Vector2.ZERO) -> void:
	var player := AudioStreamPlayer2D.new()
	player.stream = stream
	player.volume_db = linear_to_db(sfx_volume)
	player.global_position = position
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)

func play_music(stream: AudioStream) -> void:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = linear_to_db(music_volume)
	add_child(player)
	player.play()
"""


func _hud_script() -> String:
	return """extends CanvasLayer

@onready var score_label: Label = %ScoreLabel

func _ready() -> void:
	GameManager.game_started.connect(_on_game_started)
	GameManager.game_over.connect(_on_game_over)

func update_score(value: int) -> void:
	if score_label:
		score_label.text = \"Score: %d\" % value

func _on_game_started() -> void:
	update_score(0)

func _on_game_over() -> void:
	pass
"""


func _menu_script() -> String:
	return """extends Control

func _on_play_pressed() -> void:
	get_tree().change_scene_to_file(\"res://scenes/main.tscn\")

func _on_quit_pressed() -> void:
	get_tree().quit()
"""


func _plan_2d_platformer(plan: _ScaffoldPlan, w: int, h: int, autoloads: bool, ui: bool) -> _ScaffoldPlan:
	plan.folders.append_array(["scenes/player", "scenes/enemies", "scenes/levels"])
	if autoloads:
		_add_autoloads(plan, [
			["GameManager", "game_manager", _game_manager_script()],
			["AudioManager", "audio_manager", _audio_manager_script()],
		])
	plan.files.append_array(["scenes/player/player.gd", "scenes/main.gd"])
	plan.file_contents["scenes/player/player.gd"] = _player_script_2d(300.0, -400.0)
	plan.file_contents["scenes/main.gd"] = _main_scene_script()
	if ui:
		plan.files.append_array(["scenes/hud.gd", "scenes/main_menu.gd"])
		plan.file_contents["scenes/hud.gd"] = _hud_script()
		plan.file_contents["scenes/main_menu.gd"] = _menu_script()
	plan.input_actions = {
		"move_left": [{"events": [KEY_A, KEY_LEFT]}],
		"move_right": [{"events": [KEY_D, KEY_RIGHT]}],
		"jump": [{"events": [KEY_SPACE, KEY_W, KEY_UP]}],
	}
	return plan


func _plan_3d_fps(plan: _ScaffoldPlan, w: int, h: int, autoloads: bool, ui: bool) -> _ScaffoldPlan:
	plan.folders.append_array(["scenes/player", "scenes/enemies", "scenes/levels", "scenes/weapons"])
	if autoloads:
		_add_autoloads(plan, [
			["GameManager", "game_manager", _game_manager_script()],
			["AudioManager", "audio_manager", _audio_manager_script()],
		])
	plan.files.append_array(["scenes/player/player.gd", "scenes/main.gd"])
	plan.file_contents["scenes/player/player.gd"] = """extends CharacterBody3D

const SPEED := 5.0
const JUMP_VELOCITY := 4.5
const MOUSE_SENSITIVITY := 0.003

var gravity: float = ProjectSettings.get_setting(\"physics/3d/default_gravity\")
@onready var camera: Camera3D = $Camera3D

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		camera.rotation.x = clampf(camera.rotation.x, -PI/2, PI/2)
	if event.is_action_pressed(\"ui_cancel\"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	if Input.is_action_just_pressed(\"jump\") and is_on_floor():
		velocity.y = JUMP_VELOCITY
	var input_dir := Input.get_vector(\"move_left\", \"move_right\", \"move_forward\", \"move_back\")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)
	move_and_slide()
"""
	plan.file_contents["scenes/main.gd"] = """extends Node3D

func _ready() -> void:
	pass
"""
	if ui:
		plan.files.append_array(["scenes/hud.gd", "scenes/main_menu.gd"])
		plan.file_contents["scenes/hud.gd"] = _hud_script()
		plan.file_contents["scenes/main_menu.gd"] = _menu_script()
	plan.input_actions = {
		"move_forward": [{"events": [KEY_W, KEY_UP]}],
		"move_back": [{"events": [KEY_S, KEY_DOWN]}],
		"move_left": [{"events": [KEY_A, KEY_LEFT]}],
		"move_right": [{"events": [KEY_D, KEY_RIGHT]}],
		"jump": [{"events": [KEY_SPACE]}],
		"shoot": [{"events": [MOUSE_BUTTON_LEFT]}],
		"reload": [{"events": [KEY_R]}],
	}
	return plan


func _plan_top_down_rpg(plan: _ScaffoldPlan, w: int, h: int, autoloads: bool, ui: bool) -> _ScaffoldPlan:
	plan.folders.append_array(["scenes/player", "scenes/npcs", "scenes/levels", "data"])
	if autoloads:
		_add_autoloads(plan, [
			["GameManager", "game_manager", _game_manager_script()],
			["AudioManager", "audio_manager", _audio_manager_script()],
		])
	plan.files.append_array(["scenes/player/player.gd", "scenes/main.gd"])
	plan.file_contents["scenes/player/player.gd"] = """extends CharacterBody2D

const SPEED := 150.0

func _physics_process(_delta: float) -> void:
	var input_dir := Input.get_vector(\"move_left\", \"move_right\", \"move_up\", \"move_down\")
	velocity = input_dir * SPEED
	move_and_slide()
"""
	plan.file_contents["scenes/main.gd"] = _main_scene_script()
	if ui:
		plan.files.append_array(["scenes/hud.gd", "scenes/main_menu.gd", "scenes/dialogue_box.gd"])
		plan.file_contents["scenes/hud.gd"] = _hud_script()
		plan.file_contents["scenes/main_menu.gd"] = _menu_script()
		plan.file_contents["scenes/dialogue_box.gd"] = """extends CanvasLayer

@onready var label: RichTextLabel = %DialogueText
@onready var speaker: Label = %SpeakerName

var _lines: Array = []
var _index: int = 0

func show_dialogue(lines: Array) -> void:
	_lines = lines
	_index = 0
	_show_line()
	visible = true

func _show_line() -> void:
	if _index >= _lines.size():
		visible = false
		return
	var line: Dictionary = _lines[_index]
	speaker.text = line.get(\"speaker\", \"\")
	label.text = line.get(\"text\", \"\")

func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(\"interact\"):
		_index += 1
		_show_line()
"""
	plan.input_actions = {
		"move_left": [{"events": [KEY_A, KEY_LEFT]}],
		"move_right": [{"events": [KEY_D, KEY_RIGHT]}],
		"move_up": [{"events": [KEY_W, KEY_UP]}],
		"move_down": [{"events": [KEY_S, KEY_DOWN]}],
		"interact": [{"events": [KEY_E]}],
	}
	return plan


func _plan_puzzle(plan: _ScaffoldPlan, w: int, h: int, autoloads: bool, ui: bool) -> _ScaffoldPlan:
	plan.folders.append_array(["scenes/levels", "data"])
	if autoloads:
		_add_autoloads(plan, [
			["GameManager", "game_manager", _game_manager_script()],
		])
	plan.files.append_array(["scripts/grid_board.gd", "scenes/main.gd"])
	plan.file_contents["scripts/grid_board.gd"] = """extends Node2D
## Generic grid-based puzzle board

@export var grid_size: Vector2i = Vector2i(8, 8)
@export var cell_size: float = 64.0

var grid: Array = []

func _ready() -> void:
	grid.resize(grid_size.x * grid_size.y)
	grid.fill(0)

func get_cell(pos: Vector2i) -> int:
	if not _in_bounds(pos):
		return -1
	return grid[pos.y * grid_size.x + pos.x]

func set_cell(pos: Vector2i, value: int) -> void:
	if _in_bounds(pos):
		grid[pos.y * grid_size.x + pos.x] = value

func _in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < grid_size.x and pos.y >= 0 and pos.y < grid_size.y
"""
	plan.file_contents["scenes/main.gd"] = _main_scene_script()
	if ui:
		plan.files.append_array(["scenes/hud.gd", "scenes/main_menu.gd"])
		plan.file_contents["scenes/hud.gd"] = _hud_script()
		plan.file_contents["scenes/main_menu.gd"] = _menu_script()
	plan.input_actions = {
		"move_left": [{"events": [KEY_A, KEY_LEFT]}],
		"move_right": [{"events": [KEY_D, KEY_RIGHT]}],
		"move_up": [{"events": [KEY_W, KEY_UP]}],
		"move_down": [{"events": [KEY_S, KEY_DOWN]}],
		"interact": [{"events": [KEY_SPACE, KEY_E]}],
	}
	return plan


func _plan_top_down_shooter(plan: _ScaffoldPlan, w: int, h: int, autoloads: bool, ui: bool) -> _ScaffoldPlan:
	plan.folders.append_array(["scenes/player", "scenes/enemies", "scenes/projectiles", "scenes/levels"])
	if autoloads:
		_add_autoloads(plan, [
			["GameManager", "game_manager", _game_manager_script()],
			["AudioManager", "audio_manager", _audio_manager_script()],
		])
	plan.files.append_array(["scenes/player/player.gd", "scenes/main.gd", "scenes/projectiles/bullet.gd"])
	plan.file_contents["scenes/player/player.gd"] = """extends CharacterBody2D

const SPEED := 250.0

func _physics_process(_delta: float) -> void:
	var input_dir := Input.get_vector(\"move_left\", \"move_right\", \"move_up\", \"move_down\")
	velocity = input_dir * SPEED
	move_and_slide()
	look_at(get_global_mouse_position())
	if Input.is_action_just_pressed(\"shoot\"):
		_shoot()

func _shoot() -> void:
	var bullet_scene := preload(\"res://scenes/projectiles/bullet.tscn\")
	var bullet := bullet_scene.instantiate()
	bullet.global_position = global_position
	bullet.direction = (get_global_mouse_position() - global_position).normalized()
	get_parent().add_child(bullet)
"""
	plan.file_contents["scenes/projectiles/bullet.gd"] = """extends Area2D

var direction := Vector2.RIGHT
var speed := 500.0

func _physics_process(delta: float) -> void:
	position += direction * speed * delta

func _on_body_entered(_body: Node2D) -> void:
	queue_free()
"""
	plan.file_contents["scenes/main.gd"] = _main_scene_script()
	if ui:
		plan.files.append_array(["scenes/hud.gd", "scenes/main_menu.gd"])
		plan.file_contents["scenes/hud.gd"] = _hud_script()
		plan.file_contents["scenes/main_menu.gd"] = _menu_script()
	plan.input_actions = {
		"move_left": [{"events": [KEY_A, KEY_LEFT]}],
		"move_right": [{"events": [KEY_D, KEY_RIGHT]}],
		"move_up": [{"events": [KEY_W, KEY_UP]}],
		"move_down": [{"events": [KEY_S, KEY_DOWN]}],
		"shoot": [{"events": [MOUSE_BUTTON_LEFT]}],
	}
	return plan


func _plan_side_scroller(plan: _ScaffoldPlan, w: int, h: int, autoloads: bool, ui: bool) -> _ScaffoldPlan:
	plan.folders.append_array(["scenes/player", "scenes/obstacles", "scenes/levels"])
	if autoloads:
		_add_autoloads(plan, [
			["GameManager", "game_manager", _game_manager_script()],
			["AudioManager", "audio_manager", _audio_manager_script()],
		])
	plan.files.append_array(["scenes/player/player.gd", "scenes/main.gd"])
	plan.file_contents["scenes/player/player.gd"] = _player_script_2d(350.0, -500.0)
	plan.file_contents["scenes/main.gd"] = _main_scene_script()
	if ui:
		plan.files.append_array(["scenes/hud.gd", "scenes/main_menu.gd"])
		plan.file_contents["scenes/hud.gd"] = _hud_script()
		plan.file_contents["scenes/main_menu.gd"] = _menu_script()
	plan.input_actions = {
		"jump": [{"events": [KEY_SPACE, KEY_W, KEY_UP]}],
		"crouch": [{"events": [KEY_S, KEY_DOWN]}],
	}
	return plan


func _plan_visual_novel(plan: _ScaffoldPlan, w: int, h: int, autoloads: bool, ui: bool) -> _ScaffoldPlan:
	plan.folders.append_array(["scenes/characters", "data", "data/dialogues"])
	if autoloads:
		_add_autoloads(plan, [
			["GameManager", "game_manager", _game_manager_script()],
			["AudioManager", "audio_manager", _audio_manager_script()],
		])
	plan.files.append_array(["scenes/dialogue_manager.gd", "scenes/main.gd"])
	plan.file_contents["scenes/dialogue_manager.gd"] = """extends Node
## Dialogue engine for visual novel

signal dialogue_started
signal dialogue_finished
signal line_shown(speaker: String, text: String, choices: Array)

var _dialogue_data: Dictionary = {}
var _current_id: String = \"\"

func load_dialogue(path: String) -> void:
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa:
		var json := JSON.new()
		json.parse(fa.get_as_text())
		_dialogue_data = json.data
		fa.close()

func start_dialogue(id: String) -> void:
	_current_id = id
	dialogue_started.emit()
	_advance()

func _advance(choice_index: int = -1) -> void:
	if not _dialogue_data.has(_current_id):
		dialogue_finished.emit()
		return
	var node: Dictionary = _dialogue_data[_current_id]
	dialogue_line_shown.emit(node.get(\"speaker\", \"\"), node.get(\"text\", \"\"), node.get(\"choices\", []))

signal dialogue_line_shown(speaker: String, text: String, choices: Array)

func choose(index: int) -> void:
	var node: Dictionary = _dialogue_data.get(_current_id, {})
	var choices: Array = node.get(\"choices\", [])
	if index < choices.size():
		_current_id = choices[index].get(\"next\", \"\")
		_advance()
"""
	plan.file_contents["scenes/main.gd"] = _main_scene_script()
	if ui:
		plan.files.append_array(["scenes/dialogue_box.gd", "scenes/main_menu.gd"])
		plan.file_contents["scenes/dialogue_box.gd"] = """extends CanvasLayer

@onready var text_label: RichTextLabel = %VNText
@onready var speaker_label: Label = %VNSpeaker
@onready var choice_container: VBoxContainer = %VNChoices

func _ready() -> void:
	# Wire to dialogue manager if available
	pass

func show_line(speaker: String, text: String, choices: Array) -> void:
	speaker_label.text = speaker
	text_label.text = text
	for child in choice_container.get_children():
		child.queue_free()
	for i in choices.size():
		var btn := Button.new()
		btn.text = choices[i].get(\"text\", \"Choice %d\" % (i + 1))
		btn.pressed.connect(_on_choice.bind(i))
		choice_container.add_child(btn)

func _on_choice(index: int) -> void:
	pass # Wire to dialogue manager
"""
		plan.file_contents["scenes/main_menu.gd"] = _menu_script()
	plan.input_actions = {
		"interact": [{"events": [KEY_SPACE, KEY_ENTER]}],
	}
	return plan


func _plan_strategy(plan: _ScaffoldPlan, w: int, h: int, autoloads: bool, ui: bool) -> _ScaffoldPlan:
	plan.folders.append_array(["scenes/units", "scenes/buildings", "scenes/levels", "data"])
	if autoloads:
		_add_autoloads(plan, [
			["GameManager", "game_manager", _game_manager_script()],
			["AudioManager", "audio_manager", _audio_manager_script()],
		])
	plan.files.append_array(["scripts/unit_base.gd", "scenes/main.gd"])
	plan.file_contents["scripts/unit_base.gd"] = """extends CharacterBody2D
## Base unit for strategy game

@export var unit_name: String = \"Unit\"
@export var health: int = 100
@export var attack_damage: int = 10
@export var move_speed: float = 100.0

var selected: bool = false
var target_position: Vector2 = Vector2.ZERO

func select() -> void:
	selected = true

func deselect() -> void:
	selected = false

func move_to(pos: Vector2) -> void:
	target_position = pos
"""
	plan.file_contents["scenes/main.gd"] = _main_scene_script()
	if ui:
		plan.files.append_array(["scenes/hud.gd", "scenes/main_menu.gd"])
		plan.file_contents["scenes/hud.gd"] = _hud_script()
		plan.file_contents["scenes/main_menu.gd"] = _menu_script()
	plan.input_actions = {
		"move_left": [{"events": [KEY_A, KEY_LEFT]}],
		"move_right": [{"events": [KEY_D, KEY_RIGHT]}],
		"move_up": [{"events": [KEY_W, KEY_UP]}],
		"move_down": [{"events": [KEY_S, KEY_DOWN]}],
		"select": [{"events": [MOUSE_BUTTON_LEFT]}],
		"command": [{"events": [MOUSE_BUTTON_RIGHT]}],
	}
	return plan


func _plan_racing(plan: _ScaffoldPlan, w: int, h: int, autoloads: bool, ui: bool) -> _ScaffoldPlan:
	plan.folders.append_array(["scenes/vehicles", "scenes/tracks"])
	if autoloads:
		_add_autoloads(plan, [
			["GameManager", "game_manager", _game_manager_script()],
			["AudioManager", "audio_manager", _audio_manager_script()],
		])
	plan.files.append_array(["scenes/vehicles/vehicle.gd", "scenes/main.gd"])
	plan.file_contents["scenes/vehicles/vehicle.gd"] = """extends CharacterBody3D

@export var max_speed: float = 30.0
@export var acceleration: float = 15.0
@export var steering_speed: float = 2.5
@export var brake_force: float = 20.0

var speed: float = 0.0
var steer_angle: float = 0.0

func _physics_process(delta: float) -> void:
	if Input.is_action_pressed(\"accelerate\"):
		speed = minf(speed + acceleration * delta, max_speed)
	elif Input.is_action_pressed(\"brake\"):
		speed = maxf(speed - brake_force * delta, -max_speed * 0.3)
	else:
		speed = move_toward(speed, 0.0, 5.0 * delta)

	steer_angle = Input.get_axis(\"steer_right\", \"steer_left\") * steering_speed
	rotate_y(steer_angle * delta)
	velocity = -transform.basis.z * speed
	move_and_slide()
"""
	plan.file_contents["scenes/main.gd"] = """extends Node3D

func _ready() -> void:
	pass
"""
	if ui:
		plan.files.append_array(["scenes/hud.gd", "scenes/main_menu.gd"])
		plan.file_contents["scenes/hud.gd"] = """extends CanvasLayer

@onready var speed_label: Label = %SpeedLabel
@onready var lap_label: Label = %LapLabel

var current_lap: int = 1
var total_laps: int = 3

func update_speed(speed: float) -> void:
	if speed_label:
		speed_label.text = \"%d km/h\" % int(speed)

func update_lap() -> void:
	if lap_label:
		lap_label.text = \"Lap %d / %d\" % [current_lap, total_laps]
"""
		plan.file_contents["scenes/main_menu.gd"] = _menu_script()
	plan.input_actions = {
		"accelerate": [{"events": [KEY_W, KEY_UP]}],
		"brake": [{"events": [KEY_S, KEY_DOWN]}],
		"steer_left": [{"events": [KEY_A, KEY_LEFT]}],
		"steer_right": [{"events": [KEY_D, KEY_RIGHT]}],
	}
	return plan


func _plan_fighting(plan: _ScaffoldPlan, w: int, h: int, autoloads: bool, ui: bool) -> _ScaffoldPlan:
	plan.folders.append_array(["scenes/fighters", "scenes/arenas"])
	if autoloads:
		_add_autoloads(plan, [
			["GameManager", "game_manager", _game_manager_script()],
			["AudioManager", "audio_manager", _audio_manager_script()],
		])
	plan.files.append_array(["scenes/fighters/fighter.gd", "scenes/main.gd"])
	plan.file_contents["scenes/fighters/fighter.gd"] = """extends CharacterBody2D
## Base fighter with health and attacks

@export var max_health: int = 100
@export var move_speed: float = 200.0
@export var jump_force: float = -400.0
@export var attack_damage: int = 10

var health: int = 100
var is_attacking: bool = false
var facing: int = 1

var gravity: float = ProjectSettings.get_setting(\"physics/2d/default_gravity\")

signal health_changed(new_health: int)
signal defeated

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += gravity * delta
	move_and_slide()

func take_damage(amount: int) -> void:
	health = maxi(health - amount, 0)
	health_changed.emit(health)
	if health <= 0:
		defeated.emit()

func attack() -> void:
	if is_attacking:
		return
	is_attacking = true
	# Override in subclass with animation timing
	await get_tree().create_timer(0.3).timeout
	is_attacking = false
"""
	plan.file_contents["scenes/main.gd"] = _main_scene_script()
	if ui:
		plan.files.append_array(["scenes/hud.gd", "scenes/main_menu.gd"])
		plan.file_contents["scenes/hud.gd"] = """extends CanvasLayer

@onready var p1_health: ProgressBar = %P1Health
@onready var p2_health: ProgressBar = %P2Health
@onready var timer_label: Label = %TimerLabel

func update_health(player: int, health: int, max_health: int) -> void:
	var bar: ProgressBar = p1_health if player == 1 else p2_health
	if bar:
		bar.value = float(health) / float(max_health) * 100.0
"""
		plan.file_contents["scenes/main_menu.gd"] = _menu_script()
	plan.input_actions = {
		"move_left": [{"events": [KEY_A, KEY_LEFT]}],
		"move_right": [{"events": [KEY_D, KEY_RIGHT]}],
		"jump": [{"events": [KEY_W, KEY_UP]}],
		"crouch": [{"events": [KEY_S, KEY_DOWN]}],
		"attack_light": [{"events": [KEY_J]}],
		"attack_heavy": [{"events": [KEY_K]}],
		"block": [{"events": [KEY_L]}],
	}
	return plan


func _patch_project_godot(project_path: String, plan: _ScaffoldPlan, project_name: String, input: Dictionary) -> void:
	var project_file: String = project_path + "/project.godot"
	var config := ConfigFile.new()

	# Read existing if present
	config.load(project_file)

	# Set basic project settings
	var res: String = input.get("resolution", "1920x1080")
	var dims := res.split("x")
	var width: int = 1920
	var height: int = 1080
	if dims.size() == 2:
		width = int(dims[0])
		height = int(dims[1])

	config.set_value("application", "config/name", project_name)
	config.set_value("application", "run/main_scene", "res://scenes/main.tscn")
	config.set_value("display", "window/size/viewport_width", width)
	config.set_value("display", "window/size/viewport_height", height)
	config.set_value("display", "window/stretch/mode", "canvas_items")

	# Add autoloads
	for autoload_name in plan.autoloads:
		config.set_value("autoload", autoload_name, plan.autoloads[autoload_name])

	# Add input actions
	var input_section := "input"
	for action_name in plan.input_actions:
		var action_events: Array = plan.input_actions[action_name]
		var events_arr: Array = []
		for event_data in action_events:
			var keys: Array = event_data.get("events", [])
			for key_code in keys:
				if key_code == MOUSE_BUTTON_LEFT:
					events_arr.append({
						"deadzone": 0.5,
						"events": [{"event": {"button_mask": 1, "double_click": false, "factor": 1.0, "button_index": 1, "pressed": true, "ctrl_pressed": false, "shift_pressed": false, "meta_pressed": false, "alt_pressed": false}, "read_only": false}]
					})
				else:
					events_arr.append({
						"deadzone": 0.5,
						"events": [{"event": {"alt_pressed": false, "ctrl_pressed": false, "keycode": key_code, "physical_keycode": 0, "meta_pressed": false, "shift_pressed": false, "unicode": 0}, "read_only": false}]
					})
		if not events_arr.is_empty():
			config.set_value(input_section, action_name, events_arr)

	config.save(project_file)
