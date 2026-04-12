class_name GCMCPToolWrapper
extends GCBaseTool
## Generic wrapper for MCP-discovered tools


var _mcp_client: GCMCPClient
var _tool_name: String = ""
var _description: String = ""
var _input_schema: Dictionary = {}


func _init() -> void:
	# Deferred init — set properties after creation
	super._init("", "", {})


func _post_init() -> void:
	tool_name = _tool_name
	description = _description
	input_schema = _input_schema
	is_read_only = false


func validate_input(input: Dictionary) -> Dictionary:
	return {"valid": true}


func check_permissions(input: Dictionary, context: Dictionary) -> Dictionary:
	return {"behavior": "ask", "message": "MCP tool call: %s" % tool_name}


func execute(input: Dictionary, context: Dictionary) -> Dictionary:
	if not _mcp_client:
		return {"success": false, "error": "MCP client not available"}

	var server_name := _mcp_client.get_server_for_tool(tool_name)
	if server_name == "":
		return {"success": false, "error": "No server found for tool: %s" % tool_name}

	return await _mcp_client.call_tool(server_name, tool_name, input)
