class_name GCCompactCommand
extends GCBaseCommand
## /compact — Clear history, keep recent messages


func _init() -> void:
	super._init("compact", "Clear conversation history, keeping only recent messages")


func execute(args: String, context: Dictionary) -> Dictionary:
	var history: GCConversationHistory = context.get("conversation_history")
	if history:
		var keep := 4
		if args != "" and args.is_valid_int():
			keep = int(args)
		history.compact(keep)
		return _result("Conversation compacted (keeping last %d messages)" % keep)
	return _result("No conversation history to compact")
