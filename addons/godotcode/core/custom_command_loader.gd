class_name GCCustomCommandLoader
extends RefCounted
## Load user-defined slash commands from .gd scripts in the project


func load_commands() -> Array:
	## Scan res://.godotcode/commands/*.gd for classes extending GCBaseCommand
	var commands: Array = []
	var dir := "res://.godotcode/commands/"

	if not DirAccess.dir_exists_absolute(dir):
		return commands

	var da := DirAccess.open(dir)
	if not da:
		return commands

	da.list_dir_begin()
	var file_name := da.get_next()
	while file_name != "":
		if file_name.ends_with(".gd"):
			var path := dir + file_name
			var cmd := _load_command(path, file_name)
			if cmd:
				commands.append(cmd)
		file_name = da.get_next()
	da.list_dir_end()

	return commands


func _load_command(path: String, file_name: String) -> GCBaseCommand:
	## Load a single command script, validate it extends GCBaseCommand
	# We try to load it as a GDScript and check if it's a valid command
	var script := load(path) as GDScript
	if not script:
		return null

	# Try to instantiate
	var instance = null
	# GDScript classes might have class_name or be plain scripts
	# We attempt to create the instance and check the type
	instance = script.new()

	if not instance:
		return null

	# Check if it's a valid command (has required properties)
	if not ("command_name" in instance and "execute" in instance):
		if instance is RefCounted:
			instance.unreference()
		return null

	# Verify it at least looks like a command
	var cmd := instance as GCBaseCommand
	if not cmd:
		# Still usable if it has the right interface
		if not instance.has_method("execute"):
			if instance is RefCounted:
				instance.unreference()
			return null

	return instance
