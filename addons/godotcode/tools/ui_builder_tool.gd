class_name GCUIBuilderTool
extends GCBaseTool
## Generate common UI patterns from descriptions


func _init() -> void:
	super._init(
		"UIBuilder",
		"Build common UI patterns in Godot: main menus, HUDs, dialog boxes, settings screens, pause menus, inventory grids, and notification toasts. Actions: build, list_patterns.",
		{
			"action": {
				"type": "string",
				"description": "Action: build (create UI), list_patterns (show available patterns)",
				"enum": ["build", "list_patterns"]
			},
			"pattern": {
				"type": "string",
				"description": "UI pattern: main_menu, hud, dialog_box, settings, pause_menu, inventory, notification, health_bar, score_display, minimap",
				"enum": ["main_menu", "hud", "dialog_box", "settings", "pause_menu", "inventory", "notification", "health_bar", "score_display", "minimap"]
			},
			"title": {
				"type": "string",
				"description": "Title text for the UI element (game title, menu title, etc.)"
			},
			"buttons": {
				"type": "array",
				"description": "Button labels for menus (e.g. ['Play', 'Settings', 'Quit'])"
			},
			"theme_colors": {
				"type": "object",
				"description": "Theme overrides: {primary, secondary, background, text, accent} as hex colors"
			},
			"anchor": {
				"type": "string",
				"description": "Anchor preset: full_rect, center, top_left, top_right, bottom_left, bottom_right, top_wide, bottom_wide",
				"enum": ["full_rect", "center", "top_left", "top_right", "bottom_left", "bottom_right", "top_wide", "bottom_wide"]
			},
			"save_path": {
				"type": "string",
				"description": "Path to save the generated scene (default: res://scenes/ui/<pattern>.tscn)"
			}
		}
	)
	is_read_only = false


func validate_input(input: Dictionary) -> Dictionary:
	var action: String = input.get("action", "")
	if action == "":
		return {"valid": false, "error": "action is required"}
	if action == "build" and input.get("pattern", "") == "":
		return {"valid": false, "error": "pattern is required for build"}
	return {"valid": true}


func check_permissions(input: Dictionary, context: Dictionary) -> Dictionary:
	if input.get("action", "") == "list_patterns":
		return {"behavior": "allow"}
	return {"behavior": "ask", "message": "UI Builder: create %s" % input.get("pattern", "")}


func execute(input: Dictionary, context: Dictionary) -> Dictionary:
	var action: String = input.get("action", "")
	var project_path: String = context.get("project_path", "")

	match action:
		"list_patterns":
			return _list_patterns()
		"build":
			return _build(input, project_path)
		_:
			return {"success": false, "error": "Unknown action: %s" % action}


func _list_patterns() -> Dictionary:
	var patterns := {
		"main_menu": "Main menu with title, buttons (Play/Settings/Quit), and background",
		"hud": "Heads-up display with score, health bar, and optional minimap",
		"dialog_box": "NPC dialogue box with speaker name, text area, and advance indicator",
		"settings": "Settings screen with audio sliders, fullscreen toggle, and back button",
		"pause_menu": "Pause overlay with Resume/Settings/Quit buttons",
		"inventory": "Grid-based inventory with item slots and drag support",
		"notification": "Toast notification system that auto-fades",
		"health_bar": "Standalone health bar with smooth value transitions",
		"score_display": "Score counter with animated number changes",
		"minimap": "SubViewport-based minimap with camera tracking",
	}
	var lines: Array = []
	for key in patterns:
		lines.append("  %s: %s" % [key, patterns[key]])
	return {"success": true, "data": "Available UI patterns:\n" + "\n".join(lines)}


func _build(input: Dictionary, project_path: String) -> Dictionary:
	var pattern: String = input.get("pattern", "")
	var save_path: String = input.get("save_path", "res://scenes/ui/%s.tscn" % pattern)

	var tscn_content: String = ""
	var script_content: String = ""

	match pattern:
		"main_menu":
			tscn_content = _build_main_menu(input)
			script_content = _script_main_menu()
		"hud":
			tscn_content = _build_hud(input)
			script_content = _script_hud()
		"dialog_box":
			tscn_content = _build_dialog_box(input)
			script_content = _script_dialog_box()
		"settings":
			tscn_content = _build_settings(input)
			script_content = _script_settings()
		"pause_menu":
			tscn_content = _build_pause_menu(input)
			script_content = _script_pause_menu()
		"inventory":
			tscn_content = _build_inventory(input)
			script_content = _script_inventory()
		"notification":
			tscn_content = _build_notification(input)
			script_content = _script_notification()
		"health_bar":
			tscn_content = _build_health_bar(input)
			script_content = _script_health_bar()
		"score_display":
			tscn_content = _build_score_display(input)
			script_content = _script_score_display()
		"minimap":
			tscn_content = _build_minimap(input)
			script_content = _script_minimap()
		_:
			return {"success": false, "error": "Unknown pattern: %s" % pattern}

	# Ensure directory exists
	var global_save := ProjectSettings.globalize_path(save_path)
	if project_path != "":
		global_save = project_path + "/" + save_path.replace("res://", "")
	var dir := global_save.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir)

	# Write .tscn file
	var fa := FileAccess.open(global_save, FileAccess.WRITE)
	if not fa:
		return {"success": false, "error": "Cannot write to %s" % global_save}
	fa.store_string(tscn_content)
	fa.close()

	# Write script file alongside
	var script_path := global_save.replace(".tscn", ".gd")
	var sfa := FileAccess.open(script_path, FileAccess.WRITE)
	if sfa:
		sfa.store_string(script_content)
		sfa.close()

	return {"success": true, "data": "Built '%s' UI at %s" % [pattern, save_path], "path": save_path}


func _apply_anchor(root_id: String, anchor: String) -> String:
	var lines: Array = []
	match anchor:
		"full_rect":
			lines.append("anchor_right = 1.0")
			lines.append("anchor_bottom = 1.0")
		"center":
			lines.append("anchors_preset = 8")
			lines.append("grow_horizontal = 2")
			lines.append("grow_vertical = 2")
		"top_left":
			lines.append("anchors_preset = 0")
		"top_right":
			lines.append("anchors_preset = 1")
			lines.append("grow_horizontal = 2")
		"bottom_left":
			lines.append("anchors_preset = 2")
			lines.append("grow_vertical = 2")
		"bottom_right":
			lines.append("anchors_preset = 3")
			lines.append("grow_horizontal = 2")
			lines.append("grow_vertical = 2")
		"top_wide":
			lines.append("anchor_right = 1.0")
		"bottom_wide":
			lines.append("anchor_right = 1.0")
			lines.append("anchor_bottom = 1.0")
	return "\n\t\t".join(lines)


func _theme_colors(input: Dictionary) -> Dictionary:
	var defaults := {"primary": "#4a90d9", "secondary": "#2d2d2d", "background": "#1a1a2e", "text": "#e0e0e0", "accent": "#e94560"}
	var colors: Dictionary = input.get("theme_colors", {})
	for key in defaults:
		if not colors.has(key):
			colors[key] = defaults[key]
	return colors


func _build_main_menu(input: Dictionary) -> String:
	var title: String = input.get("title", "My Game")
	var buttons: Array = input.get("buttons", ["Play", "Settings", "Quit"])
	var c := _theme_colors(input)

	var buttons_tscn: String = ""
	for i in buttons.size():
		var btn_text: String = buttons[i]
		buttons_tscn += """
[node name="Btn%s" type="Button" parent="VBox"]
custom_minimum_size = Vector2(200, 50)
theme_override_colors/font_color = Color(%s)
theme_override_font_sizes/font_size = 24
text = "%s"
""" % [btn_text, _color_str(c["text"]), btn_text]

	return """[gd_scene load_steps=2 format=3]

[ext_resource path="res://scenes/ui/main_menu.gd" type="Script" id="1"]

[node name="MainMenu" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
script = ExtResource("1")

[node name="Background" type="ColorRect" parent="."]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
color = Color(%s)

[node name="VBox" type="VBoxContainer" parent="."]
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -150.0
offset_top = -150.0
offset_right = 150.0
offset_bottom = 150.0
grow_horizontal = 2
grow_vertical = 2
theme_override_constants/separation = 20

[node name="Title" type="Label" parent="VBox"]
layout_mode = 2
theme_override_colors/font_color = Color(%s)
theme_override_font_sizes/font_size = 48
text = "%s"
horizontal_alignment = 1
%s
""" % [_color_str(c["background"]), _color_str(c["accent"]), title, buttons_tscn]


func _script_main_menu() -> String:
	return """extends Control

func _ready() -> void:
	# Connect button signals automatically
	for child in %VBox.get_children():
		if child is Button:
			child.pressed.connect(_on_button_pressed.bind(child.text))

func _on_button_pressed(button_text: String) -> void:
	match button_text:
		"Play":
			get_tree().change_scene_to_file(\"res://scenes/main.tscn\")
		"Settings":
			# TODO: Open settings scene
			pass
		"Quit":
			get_tree().quit()
		_:
			push_warning(\"Unhandled menu button: %s\" % button_text)
"""


func _build_hud(input: Dictionary) -> String:
	var c := _theme_colors(input)
	return """[gd_scene load_steps=2 format=3]

[ext_resource path="res://scenes/ui/hud.gd" type="Script" id="1"]

[node name="HUD" type="CanvasLayer"]
script = ExtResource("1")

[node name="Container" type="MarginContainer" parent="."]
offset_right = 1152.0
offset_bottom = 64.0
theme_override_constants/margin_left = 16
theme_override_constants/margin_top = 8
theme_override_constants/margin_right = 16
theme_override_constants/margin_bottom = 8

[node name="HBox" type="HBoxContainer" parent="Container"]
layout_mode = 2
theme_override_constants/separation = 24

[node name="ScoreLabel" type="Label" parent="Container/HBox"]
unique_name_in_owner = true
layout_mode = 2
theme_override_colors/font_color = Color(%s)
theme_override_font_sizes/font_size = 24
text = "Score: 0"

[node name="Spacer" type="Control" parent="Container/HBox"]
layout_mode = 2
size_flags_horizontal = 3

[node name="HealthBar" type="ProgressBar" parent="Container/HBox"]
unique_name_in_owner = true
layout_mode = 2
custom_minimum_size = Vector2(200, 24)
max_value = 100.0
value = 100.0
show_percentage = false
""" % [_color_str(c["text"])]


func _script_hud() -> String:
	return """extends CanvasLayer

@onready var score_label: Label = %ScoreLabel
@onready var health_bar: ProgressBar = %HealthBar

func update_score(score: int) -> void:
	if score_label:
		score_label.text = \"Score: %d\" % score

func update_health(health: float, max_health: float = 100.0) -> void:
	if health_bar:
		health_bar.max_value = max_health
		health_bar.value = health
"""


func _build_dialog_box(input: Dictionary) -> String:
	var c := _theme_colors(input)
	return """[gd_scene load_steps=2 format=3]

[ext_resource path="res://scenes/ui/dialog_box.gd" type="Script" id="1"]

[node name="DialogBox" type="CanvasLayer"]
script = ExtResource("1")

[node name="Panel" type="PanelContainer" parent="."]
anchors_preset = 12
anchor_top = 1.0
anchor_right = 1.0
anchor_bottom = 1.0
offset_top = -180.0
offset_left = 20.0
offset_right = -20.0
grow_vertical = 0

[node name="Margin" type="MarginContainer" parent="Panel"]
layout_mode = 2
theme_override_constants/margin_left = 16
theme_override_constants/margin_top = 12
theme_override_constants/margin_right = 16
theme_override_constants/margin_bottom = 12

[node name="VBox" type="VBoxContainer" parent="Panel/Margin"]
layout_mode = 2
theme_override_constants/separation = 8

[node name="SpeakerName" type="Label" parent="Panel/Margin/VBox"]
unique_name_in_owner = true
layout_mode = 2
theme_override_colors/font_color = Color(%s)
theme_override_font_sizes/font_size = 20
text = "Speaker"

[node name="DialogueText" type="RichTextLabel" parent="Panel/Margin/VBox"]
unique_name_in_owner = true
layout_mode = 2
custom_minimum_size = Vector2(0, 80)
bbcode_enabled = true
text = "Dialogue text goes here..."

[node name="Advance" type="Label" parent="Panel/Margin/VBox"]
layout_mode = 2
theme_override_colors/font_color = Color(%s)
text = "[Press Space to continue]"
horizontal_alignment = 2
""" % [_color_str(c["accent"]), _color_str(c["text"])]


func _script_dialog_box() -> String:
	return """extends CanvasLayer

@onready var speaker_label: Label = %SpeakerName
@onready var text_label: RichTextLabel = %DialogueText

var _lines: Array = []
var _index: int = 0
var _active: bool = false

signal dialogue_finished

func show_dialogue(lines: Array) -> void:
	_lines = lines
	_index = 0
	_active = true
	_show_current()

func _show_current() -> void:
	if _index >= _lines.size():
		_active = false
		dialogue_finished.emit()
		return
	var line: Dictionary = _lines[_index]
	speaker_label.text = line.get(\"speaker\", \"\")
	text_label.text = line.get(\"text\", \"\")

func _input(event: InputEvent) -> void:
	if not _active:
		return
	if event.is_action_pressed(\"ui_accept\") or event.is_action_pressed(\"interact\"):
		_index += 1
		_show_current()
"""


func _build_settings(input: Dictionary) -> String:
	var c := _theme_colors(input)
	return """[gd_scene load_steps=2 format=3]

[ext_resource path="res://scenes/ui/settings.gd" type="Script" id="1"]

[node name="Settings" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
script = ExtResource("1")

[node name="Background" type="ColorRect" parent="."]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
color = Color(%s, 0.9)

[node name="VBox" type="VBoxContainer" parent="."]
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -200.0
offset_top = -200.0
offset_right = 200.0
offset_bottom = 200.0
grow_horizontal = 2
grow_vertical = 2
theme_override_constants/separation = 24

[node name="Title" type="Label" parent="VBox"]
layout_mode = 2
theme_override_colors/font_color = Color(%s)
theme_override_font_sizes/font_size = 36
text = "Settings"
horizontal_alignment = 1

[node name="MusicRow" type="HBoxContainer" parent="VBox"]
layout_mode = 2

[node name="Label" type="Label" parent="VBox/MusicRow"]
layout_mode = 2
theme_override_colors/font_color = Color(%s)
text = "Music Volume"
custom_minimum_size = Vector2(150, 0)

[node name="MusicSlider" type="HSlider" parent="VBox/MusicRow"]
unique_name_in_owner = true
layout_mode = 2
size_flags_horizontal = 3
max_value = 100.0
value = 80.0

[node name="SFXRow" type="HBoxContainer" parent="VBox"]
layout_mode = 2

[node name="Label" type="Label" parent="VBox/SFXRow"]
layout_mode = 2
theme_override_colors/font_color = Color(%s)
text = "SFX Volume"
custom_minimum_size = Vector2(150, 0)

[node name="SFXSlider" type="HSlider" parent="VBox/SFXRow"]
unique_name_in_owner = true
layout_mode = 2
size_flags_horizontal = 3
max_value = 100.0
value = 80.0

[node name="FullscreenCheck" type="CheckBox" parent="VBox"]
unique_name_in_owner = true
layout_mode = 2
theme_override_colors/font_color = Color(%s)
text = "Fullscreen"

[node name="BackButton" type="Button" parent="VBox"]
layout_mode = 2
custom_minimum_size = Vector2(0, 50)
text = "Back"
""" % [_color_str(c["background"]), _color_str(c["text"]), _color_str(c["text"]), _color_str(c["text"]), _color_str(c["text"])]


func _script_settings() -> String:
	return """extends Control

@onready var music_slider: HSlider = %MusicSlider
@onready var sfx_slider: HSlider = %SFXSlider
@onready var fullscreen_check: CheckBox = %FullscreenCheck

func _ready() -> void:
	music_slider.value = int(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(\"Master\")))
	%BackButton.pressed.connect(_on_back)

func _on_music_slider_changed(value: float) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(\"Master\"), linear_to_db(value / 100.0))

func _on_fullscreen_toggled(pressed: bool) -> void:
	if pressed:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func _on_back() -> void:
	get_tree().change_scene_to_file(\"res://scenes/ui/main_menu.tscn\")
"""


func _build_pause_menu(input: Dictionary) -> String:
	var c := _theme_colors(input)
	return """[gd_scene load_steps=2 format=3]

[ext_resource path="res://scenes/ui/pause_menu.gd" type="Script" id="1"]

[node name="PauseMenu" type="CanvasLayer"]
script = ExtResource("1")
layer = 10

[node name="Overlay" type="ColorRect" parent="."]
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
color = Color(0, 0, 0, 0.6)

[node name="VBox" type="VBoxContainer" parent="."]
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -100.0
offset_top = -100.0
offset_right = 100.0
offset_bottom = 100.0
grow_horizontal = 2
grow_vertical = 2
theme_override_constants/separation = 16

[node name="Title" type="Label" parent="VBox"]
layout_mode = 2
theme_override_colors/font_color = Color(%s)
theme_override_font_sizes/font_size = 36
text = "PAUSED"
horizontal_alignment = 1

[node name="ResumeBtn" type="Button" parent="VBox"]
layout_mode = 2
custom_minimum_size = Vector2(200, 50)
text = "Resume"

[node name="SettingsBtn" type="Button" parent="VBox"]
layout_mode = 2
custom_minimum_size = Vector2(200, 50)
text = "Settings"

[node name="QuitBtn" type="Button" parent="VBox"]
layout_mode = 2
custom_minimum_size = Vector2(200, 50)
text = "Quit to Menu"
""" % [_color_str(c["text"])]


func _script_pause_menu() -> String:
	return """extends CanvasLayer

func _ready() -> void:
	%ResumeBtn.pressed.connect(_on_resume)
	%QuitBtn.pressed.connect(_on_quit)

func _on_resume() -> void:
	get_tree().paused = false
	visible = false

func _on_quit() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(\"res://scenes/ui/main_menu.tscn\")

func _input(event: InputEvent) -> void:
	if event.is_action_pressed(\"ui_cancel\"):
		if get_tree().paused:
			_on_resume()
		else:
			get_tree().paused = true
			visible = true
"""


func _build_inventory(input: Dictionary) -> String:
	var c := _theme_colors(input)
	return """[gd_scene load_steps=2 format=3]

[ext_resource path="res://scenes/ui/inventory.gd" type="Script" id="1"]

[node name="Inventory" type="CanvasLayer"]
script = ExtResource("1")
layer = 5

[node name="Panel" type="PanelContainer" parent="."]
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -200.0
offset_top = -200.0
offset_right = 200.0
offset_bottom = 200.0
grow_horizontal = 2
grow_vertical = 2

[node name="Grid" type="GridContainer" parent="Panel"]
unique_name_in_owner = true
layout_mode = 2
columns = 5
theme_override_constants/h_separation = 4
theme_override_constants/v_separation = 4
""" % []


func _script_inventory() -> String:
	return """extends CanvasLayer

@onready var grid: GridContainer = %Grid
@export var slot_count: int = 20

var _items: Array = []

func _ready() -> void:
	for i in slot_count:
		var slot := Panel.new()
		slot.custom_minimum_size = Vector2(64, 64)
		grid.add_child(slot)
	visible = false

func _input(event: InputEvent) -> void:
	if event.is_action_pressed(\"inventory\"):
		visible = not visible
		get_tree().paused = visible
"""


func _build_notification(input: Dictionary) -> String:
	var c := _theme_colors(input)
	return """[gd_scene load_steps=2 format=3]

[ext_resource path="res://scenes/ui/notification.gd" type="Script" id="1"]

[node name="Notification" type="CanvasLayer"]
script = ExtResource("1")
layer = 100

[node name="VBox" type="VBoxContainer" parent="."]
anchors_preset = 1
anchor_left = 1.0
anchor_right = 1.0
offset_left = -320.0
offset_top = 16.0
offset_right = -16.0
offset_bottom = 300.0
grow_horizontal = 0
theme_override_constants/separation = 8
alignment = 2
""" % []


func _script_notification() -> String:
	return """extends CanvasLayer

@onready var container: VBoxContainer = $VBox

func show_notification(text: String, duration: float = 3.0) -> void:
	var panel := PanelContainer.new()
	var label := Label.new()
	label.text = text
	label.add_theme_color_override(\"font_color\", Color.WHITE)
	panel.add_child(label)
	panel.custom_minimum_size = Vector2(280, 40)
	container.add_child(panel)

	var tween := create_tween()
	tween.tween_property(panel, \"modulate:a\", 0.0, 0.5).set_delay(duration)
	tween.tween_callback(panel.queue_free)
"""


func _build_health_bar(input: Dictionary) -> String:
	return """[gd_scene load_steps=2 format=3]

[ext_resource path="res://scenes/ui/health_bar.gd" type="Script" id="1"]

[node name="HealthBar" type="Control"]
layout_mode = 3
custom_minimum_size = Vector2(200, 28)
script = ExtResource("1")

[node name="Background" type="ColorRect" parent="."]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
color = Color(0.2, 0.2, 0.2, 1)

[node name="Fill" type="ColorRect" parent="."]
unique_name_in_owner = true
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
color = Color(0.9, 0.2, 0.2, 1)

[node name="Label" type="Label" parent="."]
unique_name_in_owner = true
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
horizontal_alignment = 1
vertical_alignment = 1
text = "100/100"
"""


func _script_health_bar() -> String:
	return """extends Control

@onready var fill: ColorRect = %Fill
@onready var label: Label = %Label

var _max_value: float = 100.0

func setup(max_hp: float) -> void:
	_max_value = max_hp
	update_value(max_hp)

func update_value(hp: float) -> void:
	var ratio := clampf(hp / _max_value, 0.0, 1.0)
	if fill:
		fill.anchor_right = ratio
	if label:
		label.text = \"%d/%d\" % [int(hp), int(_max_value)]
"""


func _build_score_display(input: Dictionary) -> String:
	var c := _theme_colors(input)
	return """[gd_scene load_steps=2 format=3]

[ext_resource path="res://scenes/ui/score_display.gd" type="Script" id="1"]

[node name="ScoreDisplay" type="Control"]
layout_mode = 3
custom_minimum_size = Vector2(200, 50)
script = ExtResource("1")

[node name="Label" type="Label" parent="."]
unique_name_in_owner = true
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
theme_override_colors/font_color = Color(%s)
theme_override_font_sizes/font_size = 32
text = "0"
horizontal_alignment = 1
vertical_alignment = 1
""" % [_color_str(c["text"])]


func _script_score_display() -> String:
	return """extends Control

@onready var label: Label = %Label

var current_score: int = 0

func add_score(points: int) -> void:
	current_score += points
	if label:
		label.text = str(current_score)
		var tween := create_tween()
		tween.tween_property(label, \"scale\", Vector2(1.2, 1.2), 0.1)
		tween.tween_property(label, \"scale\", Vector2.ONE, 0.15)

func reset() -> void:
	current_score = 0
	if label:
		label.text = \"0\"
"""


func _build_minimap(input: Dictionary) -> String:
	return """[gd_scene load_steps=2 format=3]

[ext_resource path="res://scenes/ui/minimap.gd" type="Script" id="1"]

[node name="Minimap" type="Control"]
anchors_preset = 1
anchor_left = 1.0
anchor_right = 1.0
offset_left = -180.0
offset_top = 16.0
offset_right = -16.0
offset_bottom = 180.0
script = ExtResource("1")

[node name="SubViewport" type="SubViewport" parent="."]
size = Vector2i(164, 164)
render_target_update_mode = 1

[node name="Camera2D" type="Camera2D" parent="SubViewport"]
unique_name_in_owner = true
zoom = Vector2(0.5, 0.5)

[node name="Border" type="PanelContainer" parent="."]
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
"""


func _script_minimap() -> String:
	return """extends Control

@onready var camera: Camera2D = %Camera2D
var _target: Node2D = null

func set_target(node: Node2D) -> void:
	_target = node

func _process(_delta: float) -> void:
	if _target and camera:
		camera.global_position = _target.global_position
"""


func _color_str(hex: String) -> String:
	var c := Color(hex)
	return "%s, %s, %s" % [str(c.r), str(c.g), str(c.b)]
