class_name GCMCPTool
extends GCBaseTool
## Direct MCP tool call — specify server, tool, and arguments


var _mcp_client: GCMCPClient


func _init() -> void:
	super._init(
		"MCP",
		"Call a tool on a connected MCP (Model Context Protocol) server. Specify server name, tool name, and arguments.",
		{
			"server": {
				"type": "string",
				"description": "MCP server name (as configured in settings)"
			},
			"tool": {
				"type": "string",
				"description": "Tool name on the MCP server"
			},
			"arguments": {
				"type": "object",
				"description": "Arguments to pass to the MCP tool"
			}
		}
	)
	is_read_only = true


func validate_input(input: Dictionary) -> Dictionary:
	if not input.has("server"):
		return {"valid": false, "error": "server is required"}
	if not input.has("tool"):
		return {"valid": false, "error": "tool is required"}
	return {"valid": true}


func check_permissions(input: Dictionary, context: Dictionary) -> Dictionary:
	return {"behavior": "ask", "message": "MCP call: %s/%s" % [input.get("server", ""), input.get("tool", "")]}


func execute(input: Dictionary, context: Dictionary) -> Dictionary:
	if not _mcp_client:
		_mcp_client = context.get("mcp_client")
	if not _mcp_client:
		return {"success": false, "error": "MCP client not available"}

	var server: String = input.get("server", "")
	var tool: String = input.get("tool", "")
	var arguments: Dictionary = input.get("arguments", {})

	return await _mcp_client.call_tool(server, tool, arguments)
