class_name GCCommitCommand
extends GCBaseCommand
## /commit — Git commit workflow


func _init() -> void:
	super._init("commit", "Create a git commit with a generated message")


func execute(args: String, context: Dictionary) -> Dictionary:
	# Run git status and diff
	var output: String = ""

	var status_array: PackedStringArray = []
	OS.execute("git", ["status", "--short"], status_array)
	var status := status_array[0] if status_array.size() > 0 else ""

	if status == "":
		return _result("No changes to commit, or not a git repository")

	var diff_array: PackedStringArray = []
	OS.execute("git", ["diff", "--stat"], diff_array)
	var diff := diff_array[0] if diff_array.size() > 0 else ""

	var log_array: PackedStringArray = []
	OS.execute("git", ["log", "--oneline", "-5"], log_array)
	var log := log_array[0] if log_array.size() > 0 else ""

	var info := "Git Status:\n%s\n\nRecent commits:\n%s\n\nDiff stat:\n%s" % [status, log, diff]

	if args != "":
		# User provided commit message
		var msg_array: PackedStringArray = []
		OS.execute("git", ["add", "-A"], msg_array)
		OS.execute("git", ["commit", "-m", args], msg_array)
		return _result("Committed with message: %s" % args)

	return _result("Changes detected. Provide a commit message like: /commit Fix the bug\n\n%s" % info)
