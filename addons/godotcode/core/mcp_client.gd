class_name GCMCPClient
extends Node
## Connect to external tool servers via HTTP transport

signal tool_discovered(tool_name: String, server_name: String)
signal tool_call_result(tool_name: String, result: Dictionary)

var _servers: Dictionary = {}  # server_name -> {url, api_key}
var _discovered_tools: Dictionary = {}  # tool_name -> {server, definition}


func configure_servers(servers_config: Array) -> void:
	_servers.clear()
	for s in servers_config:
		if s is Dictionary:
			var name: String = s.get("name", "")
			var url: String = s.get("url", "")
			if name != "" and url != "":
				_servers[name] = {
					"url": url.rstrip("/"),
					"api_key": str(s.get("api_key", ""))
				}


func discover_tools(server_name: String) -> Array:
	## Discover tools from a specific MCP server. Returns array of tool definitions.
	if not _servers.has(server_name):
		return []

	var server: Dictionary = _servers[server_name]
	var url: String = server.url + "/tools"

	var http := HTTPRequest.new()
	add_child(http)

	var headers := PackedStringArray(["Content-Type: application/json"])
	var api_key: String = server.get("api_key", "")
	if api_key != "":
		headers.append("Authorization: Bearer %s" % api_key)

	http.request(url, headers, HTTPClient.METHOD_GET)
	var result: Array = await http.request_completed
	http.queue_free()

	if result[0] != HTTPRequest.RESULT_SUCCESS:
		return []

	var body: PackedByteArray = result[3]
	var response_text := body.get_string_from_utf8()

	var json := JSON.new()
	if json.parse(response_text) != OK:
		return []

	var data = json.data
	if not data is Dictionary:
		return []

	var tools = data.get("tools", [])
	if not tools is Array:
		return []

	var discovered: Array = []
	for tool_def in tools:
		if tool_def is Dictionary:
			var tool_name: String = tool_def.get("name", "")
			if tool_name != "":
				_discovered_tools[tool_name] = {
					"server": server_name,
					"definition": tool_def
				}
				discovered.append(tool_def)
				tool_discovered.emit(tool_name, server_name)

	return discovered


func discover_and_register(tool_registry: GCToolRegistry) -> int:
	## Discover tools from all configured servers and register as wrapped tools
	var total := 0

	for server_name in _servers:
		var tools := await discover_tools(server_name)
		for tool_def in tools:
			var wrapper := GCMCPToolWrapper.new()
			wrapper._mcp_client = self
			wrapper._tool_name = tool_def.get("name", "")
			wrapper._description = tool_def.get("description", "")
			wrapper._input_schema = tool_def.get("input_schema", {}).get("properties", {})
			tool_registry.register(wrapper)
			total += 1

	return total


func call_tool(server_name: String, tool_name: String, arguments: Dictionary) -> Dictionary:
	## Call a tool on an MCP server
	if not _servers.has(server_name):
		return {"success": false, "error": "Server not found: %s" % server_name}

	var server: Dictionary = _servers[server_name]
	var url: String = server.url + "/call"

	var body := {
		"tool": tool_name,
		"arguments": arguments
	}

	var http := HTTPRequest.new()
	add_child(http)

	var headers := PackedStringArray(["Content-Type: application/json"])
	var api_key: String = server.get("api_key", "")
	if api_key != "":
		headers.append("Authorization: Bearer %s" % api_key)

	http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	var result: Array = await http.request_completed
	http.queue_free()

	if result[0] != HTTPRequest.RESULT_SUCCESS:
		return {"success": false, "error": "Request failed"}

	var response_body: PackedByteArray = result[3]
	var response_text := response_body.get_string_from_utf8()

	if result[1] >= 400:
		return {"success": false, "error": "Server error (HTTP %d): %s" % [result[1], response_text.left(500)]}

	var json := JSON.new()
	if json.parse(response_text) != OK:
		return {"success": false, "error": "Invalid JSON response"}

	return {"success": true, "data": json.data}


func get_server_for_tool(tool_name: String) -> String:
	if _discovered_tools.has(tool_name):
		return _discovered_tools[tool_name].get("server", "")
	return ""


func get_discovered_tools() -> Dictionary:
	return _discovered_tools.duplicate()
