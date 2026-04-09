class_name GCBaseCommand
extends RefCounted
## Abstract base class for slash commands

var command_name: String
var description: String


func _init(p_name: String = "", p_desc: String = "") -> void:
	command_name = p_name
	description = p_desc


func execute(args: String, context: Dictionary) -> Dictionary:
	push_error("execute() must be overridden")
	return {"text": "Not implemented"}


func _result(text: String) -> Dictionary:
	return {"text": text}
