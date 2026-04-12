class_name GCVisualDiffTool
extends GCBaseTool
## Return before/after screenshots from the most recent visual mutation


var _visual_diff: GCVisualDiff


func _init() -> void:
	super._init(
		"VisualDiff",
		"View before/after screenshots of the most recent scene mutation. Shows what changed visually after an AI edit.",
		{}
	)
	is_read_only = true


func validate_input(input: Dictionary) -> Dictionary:
	return {"valid": true}


func execute(input: Dictionary, context: Dictionary) -> Dictionary:
	if not _visual_diff:
		_visual_diff = context.get("visual_diff")
	if not _visual_diff:
		return {"success": false, "error": "Visual diff system not available"}

	if not _visual_diff.has_before():
		return {"success": true, "data": "No visual changes recorded yet"}

	var diff := _visual_diff.capture_after()
	if not diff.get("has_diff", false):
		return {"success": true, "data": "No visual difference detected"}

	# Return the after image as vision content, with before/after info
	var after_b64: String = diff.get("after", "")
	if after_b64 == "":
		return {"success": true, "data": "After image capture failed"}

	return {
		"success": true,
		"data": "Visual diff for %s:\nBefore: captured\nAfter: captured\nUse Screenshot tool to see current state." % diff.get("tool_name", "unknown tool"),
		"is_vision": true,
		"vision_data": after_b64,
		"media_type": "image/png"
	}
