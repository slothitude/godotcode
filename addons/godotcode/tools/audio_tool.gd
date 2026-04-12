class_name GCAudioTool
extends GCBaseTool
## Audio bus layout, stream player management, and audio resource handling


func _init() -> void:
	super._init(
		"Audio",
		"Manage audio buses, players, and resources. Actions: create_bus_layout, add_player, list_buses, play, stop, set_volume, add_effect.",
		{
			"action": {
				"type": "string",
				"description": "Action: create_bus_layout, add_player, list_buses, play, stop, set_volume, add_effect",
				"enum": ["create_bus_layout", "add_player", "list_buses", "play", "stop", "set_volume", "add_effect"]
			},
			"buses": {
				"type": "array",
				"description": "Bus names to create (e.g. ['Music', 'SFX', 'Ambient', 'Voice']). First bus is always Master."
			},
			"bus_name": {
				"type": "string",
				"description": "Target bus name (for set_volume, add_effect, add_player)"
			},
			"volume_db": {
				"type": "number",
				"description": "Volume in dB (for set_volume)"
			},
			"effect_type": {
				"type": "string",
				"description": "Audio effect type: reverb, chorus, compressor, limiter, eq, delay, distortion, filter_low, filter_high, filter_band (for add_effect)",
				"enum": ["reverb", "chorus", "compressor", "limiter", "eq", "delay", "distortion", "filter_low", "filter_high", "filter_band"]
			},
			"player_type": {
				"type": "string",
				"description": "AudioStreamPlayer type: player, player_2d, player_3d (default: player)",
				"enum": ["player", "player_2d", "player_3d"]
			},
			"node_path": {
				"type": "string",
				"description": "Scene tree path to parent node (for add_player)"
			},
			"player_name": {
				"type": "string",
				"description": "Name for the AudioStreamPlayer node"
			},
			"stream_path": {
				"type": "string",
				"description": "Resource path to audio file (for play)"
			},
			"save_layout": {
				"type": "boolean",
				"description": "Save the bus layout to project (default: true)"
			}
		}
	)
	is_read_only = false


func validate_input(input: Dictionary) -> Dictionary:
	var action: String = input.get("action", "")
	if action == "":
		return {"valid": false, "error": "action is required"}
	return {"valid": true}


func check_permissions(input: Dictionary, context: Dictionary) -> Dictionary:
	var action: String = input.get("action", "")
	if action == "list_buses":
		return {"behavior": "allow"}
	return {"behavior": "ask", "message": "Audio: %s" % action}


func execute(input: Dictionary, context: Dictionary) -> Dictionary:
	var action: String = input.get("action", "")

	match action:
		"create_bus_layout":
			return _create_bus_layout(input)
		"add_player":
			return _add_player(input)
		"list_buses":
			return _list_buses()
		"play":
			return _play(input)
		"stop":
			return _stop(input)
		"set_volume":
			return _set_volume(input)
		"add_effect":
			return _add_effect(input)
		_:
			return {"success": false, "error": "Unknown action: %s" % action}


func _create_bus_layout(input: Dictionary) -> Dictionary:
	var bus_names: Array = input.get("buses", [])
	if bus_names.is_empty():
		bus_names = ["Music", "SFX", "Ambient", "Voice"]

	# Clear non-master buses
	while AudioServer.bus_count > 1:
		AudioServer.remove_bus(AudioServer.bus_count - 1)

	# Create buses
	var created: Array = []
	for bus_name in bus_names:
		var bus_name_str: String = str(bus_name)
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name_str)
		AudioServer.set_bus_send(idx, "Master")
		AudioServer.set_bus_volume_db(idx, 0.0)
		AudioServer.set_bus_mute(idx, false)
		AudioServer.set_bus_solo(idx, false)
		created.append(bus_name_str)

	# Save layout
	var save: bool = input.get("save_layout", true)
	if save:
		var layout := AudioServer.generate_bus_layout()
		ResourceSaver.save(layout, "res://default_bus_layout.tres")

	return {"success": true, "data": "Created audio bus layout: Master, %s" % ", ".join(created)}


func _add_player(input: Dictionary) -> Dictionary:
	if not Engine.is_editor_hint():
		return {"success": false, "error": "Requires editor mode"}

	var node_path: String = input.get("node_path", "")
	var player_type: String = input.get("player_type", "player")
	var player_name: String = input.get("player_name", "AudioStreamPlayer")
	var bus_name: String = input.get("bus_name", "Master")

	var root := EditorInterface.get_edited_scene_root()
	if not root:
		return {"success": false, "error": "No scene open"}

	var parent: Node = root
	if node_path != "":
		parent = root.get_node_or_null(NodePath(node_path))
		if not parent:
			return {"success": false, "error": "Node not found: %s" % node_path}

	var player: Node = null
	match player_type:
		"player":
			player = AudioStreamPlayer.new()
		"player_2d":
			player = AudioStreamPlayer2D.new()
		"player_3d":
			player = AudioStreamPlayer3D.new()
		_:
			player = AudioStreamPlayer.new()

	player.name = player_name
	if "bus" in player:
		player.bus = bus_name

	parent.add_child(player)
	player.owner = root

	return {"success": true, "data": "Added %s '%s' to %s (bus: %s)" % [player_type, player_name, node_path if node_path != "" else "root", bus_name]}


func _list_buses() -> Dictionary:
	var buses: Array = []
	for i in AudioServer.bus_count:
		var name: String = AudioServer.get_bus_name(i)
		var vol: float = AudioServer.get_bus_volume_db(i)
		var mute: bool = AudioServer.is_bus_mute(i)
		var solo: bool = AudioServer.is_bus_solo(i)
		var effects: int = AudioServer.get_bus_effect_count(i)
		buses.append("  %d: %s (vol: %.1fdB, mute: %s, effects: %d)" % [i, name, vol, str(mute), effects])

	if buses.is_empty():
		return {"success": true, "data": "No audio buses configured"}

	return {"success": true, "data": "Audio buses:\n" + "\n".join(buses)}


func _play(input: Dictionary) -> Dictionary:
	if not Engine.is_editor_hint():
		return {"success": false, "error": "Requires editor mode for playback"}

	var node_path: String = input.get("node_path", "")
	var stream_path: String = input.get("stream_path", "")

	if stream_path == "":
		return {"success": false, "error": "stream_path is required"}

	var root := EditorInterface.get_edited_scene_root()
	if not root:
		return {"success": false, "error": "No scene open"}

	# Find or create player
	var player: AudioStreamPlayer = null
	if node_path != "":
		player = root.get_node_or_null(NodePath(node_path))

	if not player:
		player = AudioStreamPlayer.new()
		player.name = "TempAudioPlayer"
		root.add_child(player)

	var stream := load(stream_path)
	if not stream:
		return {"success": false, "error": "Cannot load audio: %s" % stream_path}

	player.stream = stream
	if input.has("bus_name") and "bus" in player:
		player.bus = input.bus_name
	player.play()

	return {"success": true, "data": "Playing %s" % stream_path}


func _stop(input: Dictionary) -> Dictionary:
	if not Engine.is_editor_hint():
		return {"success": false, "error": "Requires editor mode"}

	var node_path: String = input.get("node_path", "")
	if node_path == "":
		return {"success": false, "error": "node_path is required"}

	var root := EditorInterface.get_edited_scene_root()
	if not root:
		return {"success": false, "error": "No scene open"}

	var player: Node = root.get_node_or_null(NodePath(node_path))
	if not player or not ("playing" in player):
		return {"success": false, "error": "AudioStreamPlayer not found: %s" % node_path}

	player.stop()
	return {"success": true, "data": "Stopped %s" % node_path}


func _set_volume(input: Dictionary) -> Dictionary:
	var bus_name: String = input.get("bus_name", "Master")
	var volume_db: float = input.get("volume_db", 0.0)

	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return {"success": false, "error": "Bus '%s' not found" % bus_name}

	AudioServer.set_bus_volume_db(idx, volume_db)
	return {"success": true, "data": "Set %s volume to %.1f dB" % [bus_name, volume_db]}


func _add_effect(input: Dictionary) -> Dictionary:
	var bus_name: String = input.get("bus_name", "Master")
	var effect_type: String = input.get("effect_type", "")

	if effect_type == "":
		return {"success": false, "error": "effect_type is required"}

	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return {"success": false, "error": "Bus '%s' not found" % bus_name}

	var effect: AudioEffect = null
	match effect_type:
		"reverb":
			effect = AudioEffectReverb.new()
			effect.predelay = 0.08
			effect.predelay_feedback = 0.4
			effect.room_size = 0.5
			effect.damping = 0.5
			effect.wet = 0.3
		"chorus":
			effect = AudioEffectChorus.new()
		"compressor":
			effect = AudioEffectCompressor.new()
			effect.threshold = 0.0
			effect.ratio = 4.0
		"limiter":
			effect = AudioEffectLimiter.new()
			effect.ceiling_db = -0.5
		"eq":
			effect = AudioEffectEQ.new()
		"delay":
			effect = AudioEffectDelay.new()
		"distortion":
			effect = AudioEffectDistortion.new()
		"filter_low":
			effect = AudioEffectLowPassFilter.new()
			effect.cutoff_hz = 2000.0
		"filter_high":
			effect = AudioEffectHighPassFilter.new()
			effect.cutoff_hz = 200.0
		"filter_band":
			effect = AudioEffectBandPassFilter.new()
		_:
			return {"success": false, "error": "Unknown effect: %s" % effect_type}

	AudioServer.add_bus_effect(idx, effect)
	return {"success": true, "data": "Added %s effect to bus '%s'" % [effect_type, bus_name]}
