class_name GCGitTool
extends GCBaseTool
## Structured git operations with safety checks


func _init() -> void:
	super._init(
		"Git",
		"Execute git commands with structured output. Actions: status, diff, log, branch, add, stash, show, remote.",
		{
			"action": {
				"type": "string",
				"description": "Git action: status, diff, log, branch, add, stash, show, remote",
				"enum": ["status", "diff", "log", "branch", "add", "stash", "show", "remote"]
			},
			"args": {
				"type": "string",
				"description": "Additional arguments for the git command"
			},
			"path": {
				"type": "string",
				"description": "File path for diff/add/show operations"
			}
		}
	)
	is_read_only = true  # Destructive actions override in check_permissions


func validate_input(input: Dictionary) -> Dictionary:
	var action: String = input.get("action", "")
	if action == "":
		return {"valid": false, "error": "action is required"}
	var valid_actions := ["status", "diff", "log", "branch", "add", "stash", "show", "remote"]
	if action not in valid_actions:
		return {"valid": false, "error": "Invalid action: %s. Valid: %s" % [action, ", ".join(valid_actions)]}
	return {"valid": true}


func check_permissions(input: Dictionary, context: Dictionary) -> Dictionary:
	var action: String = input.get("action", "")
	var args: String = input.get("args", "")

	# Read-only actions
	var read_actions := ["status", "diff", "log", "show", "remote"]
	if action in read_actions:
		return {"behavior": "allow"}

	# Check for destructive operations
	if _is_destructive(action, args):
		return {"behavior": "ask", "message": "Destructive git operation: %s %s" % [action, args]}

	# Write operations need confirmation
	return {"behavior": "ask", "message": "Git %s %s" % [action, args]}


func execute(input: Dictionary, context: Dictionary) -> Dictionary:
	var action: String = input.get("action", "")
	var args: String = input.get("args", "")
	var path: String = input.get("path", "")
	var working_dir: String = context.get("project_path", "")

	var command: String = _build_command(action, args, path)
	var exit_code := -1

	var thread := Thread.new()
	var thread_result: Dictionary = {}

	thread.start(func():
		var o: PackedByteArray = []
		var e: PackedByteArray = []
		exit_code = OS.execute("git", _git_args(action, args, path, working_dir), o, true)
		thread_result["stdout"] = o.get_string_from_utf8() if o.size() > 0 else ""
		thread_result["exit_code"] = exit_code
	)

	var start_time := Time.get_ticks_msec()
	while thread.is_alive():
		if Time.get_ticks_msec() - start_time > 30000:
			return {"success": false, "error": "Git command timed out"}
		OS.delay_msec(50)

	thread.wait_to_finish()

	var stdout: String = thread_result.get("stdout", "")
	exit_code = thread_result.get("exit_code", -1)

	# Strip ANSI color codes
	stdout = _strip_ansi(stdout)

	# Add header
	var header := "=== git %s ===" % action
	if args != "":
		header += " %s" % args
	var result_text := header + "\n" + stdout

	if exit_code != 0 and stdout == "":
		return {"success": false, "error": "Git command failed (exit code %d)" % exit_code}

	return {"success": exit_code == 0, "data": result_text}


func _build_command(action: String, args: String, path: String) -> String:
	match action:
		"status":
			var s := "git status --short"
			if args != "":
				s += " " + args
			return s
		"diff":
			var cmd := "git diff"
			if path != "":
				cmd += " -- " + path
			if args != "":
				cmd += " " + args
			return cmd
		"log":
			var n := "20"
			if args != "" and args.is_valid_int():
				n = args
			return "git log --oneline -%s" % n
		"branch":
			if args != "":
				return "git branch %s" % args
			return "git branch -a"
		"add":
			var target := "."
			if path != "":
				target = path
			return "git add %s" % target
		"stash":
			if args == "list":
				return "git stash list"
			if args.begins_with("pop") or args.begins_with("apply"):
				return "git stash %s" % args
			return "git stash"
		"show":
			var target := "HEAD"
			if args != "":
				target = args
			return "git show --stat %s" % target
		"remote":
			return "git remote -v"
		_:
			return "git %s %s" % [action, args]


func _is_destructive(action: String, args: String) -> bool:
	var lower_args := args.to_lower()
	if action == "branch" and ("-D" in lower_args or "--delete" in lower_args):
		return true
	if "reset" in lower_args and ("--hard" in lower_args or "--mixed" in lower_args):
		return true
	if "push" in lower_args and ("--force" in lower_args or "-f " in lower_args):
		return true
	if "clean" in lower_args and "-f" in lower_args:
		return true
	return false


func _git_args(action: String, args: String, path: String, working_dir: String) -> PackedStringArray:
	## Build args for OS.execute("git", args) — no bash needed
	var git_args := PackedStringArray()
	if working_dir != "":
		git_args.append("-C")
		git_args.append(working_dir)
	var cmd: String = _build_command(action, args, path)
	# Strip the "git " prefix since we call git directly
	if cmd.begins_with("git "):
		cmd = cmd.substr(4)
	# Split the command string into individual args
	for arg in cmd.split(" ", false):
		git_args.append(arg)
	return git_args


func _strip_ansi(text: String) -> String:
	# Simple ANSI escape code removal
	var result := ""
	var i := 0
	var esc := char(27)  # ESC character
	while i < text.length():
		if text[i] == esc:
			# Skip escape sequence until 'm'
			while i < text.length() and text[i] != "m":
				i += 1
			if i < text.length():
				i += 1
		else:
			result += text[i]
			i += 1
	return result
