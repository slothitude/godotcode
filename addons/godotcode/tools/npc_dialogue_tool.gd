class_name GCNPCDialogueTool
extends GCBaseTool
## Generate NPC dialogue data structures and dialogue UI scenes


func _init() -> void:
	super._init(
		"NPCDialogue",
		"Generate NPC dialogue data, dialogue UI, and conversation trees. Actions: create_dialogue, create_npc, generate_tree, list_dialogues.",
		{
			"action": {
				"type": "string",
				"description": "Action: create_dialogue, create_npc, generate_tree, list_dialogues",
				"enum": ["create_dialogue", "create_npc", "generate_tree", "list_dialogues"]
			},
			"npc_name": {
				"type": "string",
				"description": "NPC character name"
			},
			"personality": {
				"type": "string",
				"description": "NPC personality description (e.g. 'friendly shopkeeper', 'grumpy guard')"
			},
			"context": {
				"type": "string",
				"description": "Dialogue context/situation (e.g. 'first meeting', 'quest complete', 'shop browsing')"
			},
			"num_lines": {
				"type": "integer",
				"description": "Number of dialogue lines to generate (default: 5)"
			},
			"dialogue_data": {
				"type": "array",
				"description": "Dialogue lines: [{speaker, text, choices: [{text, next}]}]"
			},
			"save_path": {
				"type": "string",
				"description": "Save path for dialogue JSON (default: res://data/dialogues/<npc_name>.json)"
			},
			"has_choices": {
				"type": "boolean",
				"description": "Include player choice branches (default: false)"
			},
			"portrait_path": {
				"type": "string",
				"description": "Portrait image path for the NPC"
			}
		}
	)
	is_read_only = false


func validate_input(input: Dictionary) -> Dictionary:
	var action: String = input.get("action", "")
	if action == "":
		return {"valid": false, "error": "action is required"}
	match action:
		"create_dialogue":
			if input.get("npc_name", "") == "":
				return {"valid": false, "error": "npc_name is required for create_dialogue"}
		"create_npc":
			if input.get("npc_name", "") == "":
				return {"valid": false, "error": "npc_name is required for create_npc"}
	return {"valid": true}


func check_permissions(input: Dictionary, context: Dictionary) -> Dictionary:
	var action: String = input.get("action", "")
	if action == "list_dialogues":
		return {"behavior": "allow"}
	return {"behavior": "ask", "message": "NPC Dialogue: %s for %s" % [action, input.get("npc_name", "")]}


func execute(input: Dictionary, context: Dictionary) -> Dictionary:
	var action: String = input.get("action", "")
	var project_path: String = context.get("project_path", "")

	match action:
		"create_dialogue":
			return _create_dialogue(input, project_path)
		"create_npc":
			return _create_npc(input, project_path)
		"generate_tree":
			return _generate_tree(input, project_path)
		"list_dialogues":
			return _list_dialogues(project_path)
		_:
			return {"success": false, "error": "Unknown action: %s" % action}


func _create_dialogue(input: Dictionary, project_path: String) -> Dictionary:
	var npc_name: String = input.get("npc_name", "")
	var personality: String = input.get("personality", "neutral")
	var context: String = input.get("context", "greeting")
	var num_lines: int = input.get("num_lines", 5)
	var has_choices: bool = input.get("has_choices", false)

	var lines: Array = input.get("dialogue_data", [])
	if lines.is_empty():
		lines = _generate_dialogue_lines(npc_name, personality, context, num_lines, has_choices)

	var dialogue := {
		"npc_name": npc_name,
		"personality": personality,
		"context": context,
		"lines": lines,
	}

	# Save as JSON
	var save_path: String = input.get("save_path", "res://data/dialogues/%s.json" % npc_name.to_snake_case())
	var global_path := save_path
	if save_path.begins_with("res://") and project_path != "":
		global_path = project_path + "/" + save_path.replace("res://", "")

	DirAccess.make_dir_recursive_absolute(global_path.get_base_dir())
	var fa := FileAccess.open(global_path, FileAccess.WRITE)
	if not fa:
		return {"success": false, "error": "Cannot write to %s" % global_path}
	fa.store_string(JSON.stringify(dialogue, "\t"))
	fa.close()

	return {"success": true, "data": "Created dialogue for '%s' (%d lines) at %s" % [npc_name, lines.size(), save_path], "path": save_path}


func _create_npc(input: Dictionary, project_path: String) -> Dictionary:
	var npc_name: String = input.get("npc_name", "")
	var personality: String = input.get("personality", "friendly")
	var portrait: String = input.get("portrait_path", "")

	# Create NPC script
	var script := """extends CharacterBody2D
## NPC: %s

@export var npc_name: String = "%s"
@export var personality: String = "%s"
@export var dialogue_file: String = "res://data/dialogues/%s.json"

var dialogue_data: Dictionary = {}
var is_talking: bool = false
var interaction_range: Area2D

signal dialogue_started
signal dialogue_finished

func _ready() -> void:
\t_load_dialogue()

func _load_dialogue() -> void:
\tif FileAccess.file_exists(dialogue_file):
\t\tvar fa := FileAccess.open(dialogue_file, FileAccess.READ)
\t\tif fa:
\t\t\tvar json := JSON.new()
\t\t\tjson.parse(fa.get_as_text())
\t\t\tdialogue_data = json.data
\t\t\tfa.close()

func interact() -> void:
\tif dialogue_data.is_empty():
\t\treturn
\tis_talking = true
\tdialogue_started.emit()

func _on_interaction_body_entered(_body: Node2D) -> void:
\tpass # Show interaction prompt

func _on_interaction_body_exited(_body: Node2D) -> void:
\tif is_talking:
\t\tis_talking = false
\t\tdialogue_finished.emit()
""" % [npc_name, npc_name, personality, npc_name.to_snake_case()]

	# Save script
	var script_path := "res://scripts/npcs/%s.gd" % npc_name.to_snake_case()
	var global_script := project_path + "/" + script_path.replace("res://", "")
	DirAccess.make_dir_recursive_absolute(global_script.get_base_dir())
	var fa := FileAccess.open(global_script, FileAccess.WRITE)
	if fa:
		fa.store_string(script)
		fa.close()

	# Create dialogue data file too
	var dialogue_input := {
		"npc_name": npc_name,
		"personality": personality,
		"context": "greeting",
		"num_lines": 3,
	}
	_create_dialogue(dialogue_input, project_path)

	return {"success": true, "data": "Created NPC '%s' with script and dialogue data" % npc_name, "script": script_path}


func _generate_tree(input: Dictionary, project_path: String) -> Dictionary:
	var npc_name: String = input.get("npc_name", "NPC")
	var has_choices: bool = input.get("has_choices", true)

	var tree := {
		"start": {
			"speaker": npc_name,
			"text": "Hello, traveler! What brings you here?",
			"choices": [
				{"text": "Tell me about this place.", "next": "about_place"},
				{"text": "I'm looking for a quest.", "next": "quest"},
				{"text": "Just passing through. Goodbye.", "next": "goodbye"}
			]
		},
		"about_place": {
			"speaker": npc_name,
			"text": "This is a peaceful village. We've had some trouble with creatures in the forest lately.",
			"next": "start"
		},
		"quest": {
			"speaker": npc_name,
			"text": "There are strange noises coming from the old mine. Could you investigate?",
			"choices": [
				{"text": "I'll check it out.", "next": "quest_accept"},
				{"text": "Sounds dangerous. Maybe later.", "next": "start"}
			]
		},
		"quest_accept": {
			"speaker": npc_name,
			"text": "Thank you! Be careful in there. Take this torch with you.",
			"next": "goodbye"
		},
		"goodbye": {
			"speaker": npc_name,
			"text": "Safe travels!",
			"next": ""
		}
	}

	if not has_choices:
		# Flatten to linear
		var linear: Array = [
			{"speaker": npc_name, "text": "Hello, traveler! What brings you here?"},
			{"speaker": npc_name, "text": "This village has been peaceful, but strange things happen in the old mine."},
			{"speaker": npc_name, "text": "If you're looking for work, the mine could use investigating."},
			{"speaker": npc_name, "text": "Be careful out there. Safe travels!"},
		]
		tree = {"start": "greeting", "greeting": linear[0], "line1": linear[1], "line2": linear[2], "goodbye": linear[3]}
		# Wire next pointers
		var keys := tree.keys()
		for i in keys.size() - 1:
			tree[keys[i]]["next"] = keys[i + 1]
		tree[keys[-1]]["next"] = ""

	var save_path: String = input.get("save_path", "res://data/dialogues/%s_tree.json" % npc_name.to_snake_case())
	var global_path := project_path + "/" + save_path.replace("res://", "")
	DirAccess.make_dir_recursive_absolute(global_path.get_base_dir())
	var fa := FileAccess.open(global_path, FileAccess.WRITE)
	if fa:
		fa.store_string(JSON.stringify(tree, "\t"))
		fa.close()

	return {"success": true, "data": "Generated dialogue tree for '%s' with %d nodes" % [npc_name, tree.size()], "path": save_path}


func _list_dialogues(project_path: String) -> Dictionary:
	var dialogue_dir := project_path + "/data/dialogues/"
	var dialogues: Array = []

	var da := DirAccess.open(dialogue_dir)
	if not da:
		return {"success": true, "data": "No dialogue directory found. Use create_dialogue first."}

	da.list_dir_begin()
	var f := da.get_next()
	while f != "":
		if f.ends_with(".json"):
			dialogues.append(f)
		f = da.get_next()
	da.list_dir_end()

	if dialogues.is_empty():
		return {"success": true, "data": "No dialogue files found."}

	return {"success": true, "data": "Dialogue files:\n" + "\n".join(dialogues), "count": dialogues.size()}


func _generate_dialogue_lines(npc_name: String, personality: String, context: String, count: int, has_choices: bool) -> Array:
	var lines: Array = []

	# Template-based generation using personality and context
	var greetings := {
		"friendly": ["Hello there, friend!", "Welcome! Good to see you.", "Hey! Nice day, isn't it?"],
		"grumpy": ["What do you want?", "Make it quick.", "Hmm, you again."],
		"mysterious": ["I've been expecting you...", "The stars foretold your arrival.", "Curious... very curious."],
		"shopkeeper": ["Welcome to my shop! What can I get you?", "Looking for something specific?", "I have the finest goods in town!"],
		"guard": ["Halt! State your business.", "The area is secure. Move along.", "Watch yourself, stranger."],
		"neutral": ["Hello.", "Greetings.", "Yes?"],
	}

	var context_lines := {
		"greeting": ["How can I help you today?", "What brings you here?"],
		"quest_complete": ["Excellent work! Here's your reward.", "You did it! The village is grateful."],
		"shop_browsing": ["Take your time looking around.", "Everything's on sale today!"],
		"first_meeting": ["I don't believe we've met. I'm %s." % npc_name, "New around here, aren't you?"],
		"danger_warning": ["Be careful out there. It's not safe.", "Something lurks in the shadows..."],
	}

	var pool := greetings.get(personality, greetings["neutral"])
	if context_lines.has(context):
		pool = context_lines[context]

	for i in count:
		var line_idx: int = i % pool.size()
		var line := {"speaker": npc_name, "text": pool[line_idx]}
		if has_choices and i == 0:
			line["choices"] = [
				{"text": "Tell me more.", "next": "line_%d" % (i + 1)},
				{"text": "Goodbye.", "next": ""}
			]
		else:
			line["next"] = "line_%d" % (i + 1) if i < count - 1 else ""
		lines.append(line)

	return lines
