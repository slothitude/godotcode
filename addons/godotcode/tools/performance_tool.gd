class_name GCPerformanceTool
extends GCBaseTool
## Performance analysis and optimization suggestions


func _init() -> void:
	super._init(
		"Performance",
		"Analyze game performance, identify bottlenecks, and suggest optimizations. Actions: profile, analyze_scene, suggest, check_settings, fps_report.",
		{
			"action": {
				"type": "string",
				"description": "Action: profile (runtime metrics), analyze_scene (static analysis), suggest (optimization tips), check_settings (project config), fps_report (current FPS)",
				"enum": ["profile", "analyze_scene", "suggest", "check_settings", "fps_report"]
			},
			"duration": {
				"type": "number",
				"description": "Profile duration in seconds (default: 3.0)"
			},
			"node_path": {
				"type": "string",
				"description": "Specific node to analyze (for analyze_scene)"
			},
			"category": {
				"type": "string",
				"description": "Performance category: rendering, physics, scripting, memory, general (default: general)",
				"enum": ["rendering", "physics", "scripting", "memory", "general"]
			}
		}
	)
	is_read_only = true


func validate_input(input: Dictionary) -> Dictionary:
	var action: String = input.get("action", "")
	if action == "":
		return {"valid": false, "error": "action is required"}
	return {"valid": true}


func check_permissions(input: Dictionary, context: Dictionary) -> Dictionary:
	return {"behavior": "allow"}


func execute(input: Dictionary, context: Dictionary) -> Dictionary:
	var action: String = input.get("action", "")
	var project_path: String = context.get("project_path", "")

	match action:
		"profile":
			return _profile(input)
		"analyze_scene":
			return _analyze_scene(input)
		"suggest":
			return _suggest(input)
		"check_settings":
			return _check_settings(project_path)
		"fps_report":
			return _fps_report()
		_:
			return {"success": false, "error": "Unknown action: %s" % action}


func _profile(input: Dictionary) -> Dictionary:
	var metrics := {
		"fps": Performance.get_monitor(Performance.TIME_FPS),
		"frame_time_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"physics_time_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"static_memory_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / (1024.0 * 1024.0),
		"object_count": Performance.get_monitor(Performance.OBJECT_COUNT),
		"node_count": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"orphan_nodes": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		"render_objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"vertices": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
	}

	var lines: Array = ["=== Performance Profile ===", ""]
	lines.append("Frame Metrics:")
	lines.append("  FPS: %.0f" % metrics.fps)
	lines.append("  Frame time: %.2f ms" % metrics.frame_time_ms)
	lines.append("  Physics time: %.2f ms" % metrics.physics_time_ms)
	lines.append("")
	lines.append("Memory:")
	lines.append("  Static: %.1f MB" % metrics.static_memory_mb)
	lines.append("  Objects: %d" % metrics.object_count)
	lines.append("  Nodes: %d" % metrics.node_count)
	lines.append("  Orphan nodes: %d" % metrics.orphan_nodes)
	lines.append("")
	lines.append("Rendering:")
	lines.append("  Objects in frame: %d" % metrics.render_objects)
	lines.append("  Draw calls: %d" % metrics.draw_calls)
	lines.append("  Vertices: %d" % metrics.vertices)

	# Identify issues
	var issues: Array = []
	if metrics.fps < 30.0:
		issues.append("LOW FPS: %.0f FPS is below 30 — investigate frame time" % metrics.fps)
	if metrics.frame_time_ms > 33.0:
		issues.append("HIGH FRAME TIME: %.2f ms exceeds 30 FPS budget" % metrics.frame_time_ms)
	if metrics.orphan_nodes > 10:
		issues.append("MEMORY LEAK: %d orphan nodes detected" % metrics.orphan_nodes)
	if metrics.draw_calls > 100:
		issues.append("HIGH DRAW CALLS: %d — consider batching/merging meshes" % metrics.draw_calls)
	if metrics.node_count > 1000:
		issues.append("HIGH NODE COUNT: %d — consider object pooling" % metrics.node_count)

	if not issues.is_empty():
		lines.append("")
		lines.append("Issues Found:")
		for issue in issues:
			lines.append("  ! %s" % issue)

	return {"success": true, "data": "\n".join(lines), "metrics": metrics, "issues": issues}


func _analyze_scene(input: Dictionary) -> Dictionary:
	if not Engine.is_editor_hint():
		return {"success": false, "error": "Requires editor mode"}

	var root := EditorInterface.get_edited_scene_root()
	if not root:
		return {"success": false, "error": "No scene open"}

	var node_path: String = input.get("node_path", "")
	var target: Node = root
	if node_path != "":
		target = root.get_node_or_null(NodePath(node_path))
		if not target:
			return {"success": false, "error": "Node not found: %s" % node_path}

	var analysis := _analyze_node_tree(target, root)
	var lines: Array = ["Scene Analysis: %s" % (node_path if node_path != "" else "root"), ""]

	var total_nodes: int = analysis.node_count
	var script_count: int = analysis.scripted_nodes
	var physics_bodies: int = analysis.physics_bodies
	var visual_nodes: int = analysis.visual_nodes
	var animation_players: int = analysis.animation_players

	lines.append("Node Statistics:")
	lines.append("  Total nodes: %d" % total_nodes)
	lines.append("  Scripted nodes: %d" % script_count)
	lines.append("  Physics bodies: %d" % physics_bodies)
	lines.append("  Visual nodes: %d" % visual_nodes)
	lines.append("  AnimationPlayers: %d" % animation_players)

	# Performance suggestions
	var suggestions: Array = []
	if total_nodes > 500:
		suggestions.append("Consider scene instancing or level streaming for %d nodes" % total_nodes)
	if physics_bodies > 50:
		suggestions.append("High physics body count (%d) — consider simplifying collision shapes" % physics_bodies)
	if analysis.large_textures.size() > 0:
		for tex_info in analysis.large_textures:
			suggestions.append("Large texture: %s (%s)" % [tex_info.path, tex_info.size])

	if not suggestions.is_empty():
		lines.append("")
		lines.append("Suggestions:")
		for s in suggestions:
			lines.append("  - %s" % s)

	return {"success": true, "data": "\n".join(lines), "analysis": {
		"node_count": total_nodes,
		"scripted_nodes": script_count,
		"physics_bodies": physics_bodies,
		"visual_nodes": visual_nodes,
	}}


func _suggest(input: Dictionary) -> Dictionary:
	var category: String = input.get("category", "general")

	var suggestions := {
		"rendering": [
			"Use VisibleOnScreenNotifier2D/3D to cull off-screen objects",
			"Enable mesh LOD for distant 3D objects",
			"Batch similar draw calls with MultiMesh or tilemaps",
			"Reduce texture sizes — use compressed formats (VRAM compression)",
			"Use CanvasItem.visible = false instead of modulate.a = 0",
			"Avoid overlapping transparent UI elements",
			"Use Z-indexing sparingly — each Z-layer adds a draw call",
			"Consider GPU instancing for repeated objects (MultiMesh)",
		],
		"physics": [
			"Use simplified collision shapes (circles/boxes over polygons)",
			"Reduce physics tick rate for non-critical bodies",
			"Enable CCD only on fast-moving objects",
			"Use StaticBody for non-moving objects instead of RigidBody",
			"Disable contact monitoring on bodies that don't need it",
			"Use collision layers/masks to reduce broad-phase checks",
			"Consider area-based detection instead of body collision for triggers",
		],
		"scripting": [
			"Avoid _process()/_physics_process() on nodes that don't need per-frame updates",
			"Cache node references with @onready instead of get_node() each frame",
			"Use Object.emit_signal() sparingly — prefer direct function calls for 1:1",
			"Pool and reuse objects instead of instantiate()/queue_free() cycles",
			"Minimize string operations in hot paths",
			"Use typed arrays (Array[int]) over Variant arrays for performance",
			"Avoid creating new objects in _process() — reuse with reset()",
		],
		"memory": [
			"Free resources when no longer needed (queue_free, unref)",
			"Use ResourceLoader.load_threaded() for large assets",
			"Compress audio to OGG Vorbis for streaming (not WAV)",
			"Monitor orphan node count with Performance.OBJECT_ORPHAN_NODE_COUNT",
			"Use weakref() for caches to allow garbage collection",
			"Limit undo stack size to prevent memory bloat",
		],
		"general": [
			"Profile first with the Performance tool before optimizing",
			"Focus on the biggest bottleneck — 80/20 rule",
			"Test on target hardware, not just development machine",
			"Use OS.delay_msec() for non-critical timers instead of Timer nodes",
			"Consider level streaming/loading for large worlds",
			"Keep scene trees shallow — avoid deeply nested hierarchies",
			"Use static typing for better performance: var x: int = 5",
		],
	}

	var items: Array = suggestions.get(category, suggestions["general"])
	return {"success": true, "data": "Optimization suggestions (%s):\n%s" % [category, "\n".join(items)]}


func _check_settings(project_path: String) -> Dictionary:
	var config := ConfigFile.new()
	config.load(project_path + "/project.godot")

	var lines: Array = ["Project Performance Settings:", ""]
	var issues: Array = []

	# Rendering
	var render_method: String = config.get_value("rendering", "renderer/rendering_method", "mobile")
	lines.append("Rendering:")
	lines.append("  Method: %s" % render_method)
	if render_method == "forward_plus":
		issues.append("Using forward+ renderer — switch to 'mobile' for better performance on lower-end devices")

	# 2D specific
	var vsync: String = str(config.get_value("display", "window/vsync/vsync_mode", 1))
	lines.append("  VSync: %s" % vsync)

	# Physics
	var physics_fps: int = config.get_value("physics", "common/physics_fps", 60)
	lines.append("")
	lines.append("Physics:")
	lines.append("  Tick rate: %d Hz" % physics_fps)
	if physics_fps > 60:
		issues.append("Physics FPS is %d — higher tick rate increases CPU load" % physics_fps)

	# Threading
	var threaded_physics: bool = config.get_value("physics", "common/threaded_physics", false)
	lines.append("  Threaded: %s" % str(threaded_physics))

	if not issues.is_empty():
		lines.append("")
		lines.append("Recommendations:")
		for issue in issues:
			lines.append("  ! %s" % issue)

	return {"success": true, "data": "\n".join(lines), "issues": issues}


func _fps_report() -> Dictionary:
	var fps: float = Performance.get_monitor(Performance.TIME_FPS)
	var frame_time: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var physics_time: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0

	var rating: String = "Excellent"
	if fps < 60:
		rating = "Good"
	if fps < 30:
		rating = "Poor"
	if fps < 15:
		rating = "Critical"

	return {
		"success": true,
		"data": "FPS: %.0f | Frame: %.2fms | Physics: %.2fms | Rating: %s" % [fps, frame_time, physics_time, rating],
		"fps": fps,
		"frame_time_ms": frame_time,
		"physics_time_ms": physics_time,
		"rating": rating
	}


class _SceneAnalysis:
	var node_count: int = 0
	var scripted_nodes: int = 0
	var physics_bodies: int = 0
	var visual_nodes: int = 0
	var animation_players: int = 0
	var large_textures: Array = []


func _analyze_node_tree(node: Node, root: Node) -> _SceneAnalysis:
	var analysis := _SceneAnalysis.new()
	_count_nodes(node, analysis)
	return analysis


func _count_nodes(node: Node, analysis: _SceneAnalysis) -> void:
	analysis.node_count += 1

	if node.script:
		analysis.scripted_nodes += 1

	if node is CharacterBody2D or node is CharacterBody3D or node is RigidBody2D or node is RigidBody3D or node is StaticBody2D or node is StaticBody3D:
		analysis.physics_bodies += 1

	if node is Sprite2D or node is Sprite3D or node is MeshInstance3D or node is AnimatedSprite2D:
		analysis.visual_nodes += 1

	if node is AnimationPlayer:
		analysis.animation_players += 1

	for child in node.get_children():
		_count_nodes(child, analysis)
