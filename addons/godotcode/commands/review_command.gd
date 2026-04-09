class_name GCReviewCommand
extends GCBaseCommand
## /review — Code review prompt


func _init() -> void:
	super._init("review", "Start a code review of recent changes")


func execute(args: String, context: Dictionary) -> Dictionary:
	var diff_array: PackedStringArray = []
	OS.execute("git", ["diff", "HEAD"], diff_array)
	var diff := diff_array[0] if diff_array.size() > 0 else ""

	if diff == "":
		OS.execute("git", ["diff", "--cached"], diff_array)
		diff = diff_array[0] if diff_array.size() > 0 else ""

	if diff == "":
		return _result("No changes to review. Make some changes first.")

	var target := args if args != "" else "the staged/unstaged changes"
	var prompt := "Please review %s. Focus on:\n- Bugs and potential issues\n- Code quality and style\n- Performance concerns\n- Security vulnerabilities\n\nHere are the changes:\n\n%s" % [target, diff.left(10000)]

	var engine: GCQueryEngine = context.get("query_engine")
	if engine:
		engine.submit_message(prompt)
		return _result("Starting code review...")

	return _result("Code review prompt prepared but no query engine available.")
