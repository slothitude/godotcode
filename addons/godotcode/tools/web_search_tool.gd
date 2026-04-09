class_name GCWebSearchTool
extends GCBaseTool
## Web search using HTTP requests to configurable search API


func _init() -> void:
	super._init(
		"WebSearch",
		"Search the web and return results. Provides up-to-date information from the internet.",
		{
			"query": {
				"type": "string",
				"description": "The search query (at least 2 characters)"
			}
		}
	)


func validate_input(input: Dictionary) -> Dictionary:
	if not input.has("query"):
		return {"valid": false, "error": "query is required"}
	if str(input.get("query", "")).length() < 2:
		return {"valid": false, "error": "query must be at least 2 characters"}
	return {"valid": true}


func execute(input: Dictionary, context: Dictionary) -> Dictionary:
	var query: String = str(input.get("query", ""))

	if query == "":
		return {"success": false, "error": "query is required"}

	# Use DuckDuckGo HTML search as fallback (no API key needed)
	var url := "https://html.duckduckgo.com/html/?q=%s" % query.uri_encode()

	var http := HTTPRequest.new()
	# We need a node tree — use a temporary approach
	# In practice this should be handled via the query engine's node
	var result := await _do_request(http, url)

	if result == null:
		return {"success": false, "error": "Web search request failed"}

	# Parse basic results from HTML
	var results := _parse_ddg_results(result)
	if results.is_empty():
		return {"success": true, "data": "No results found for: %s" % query}

	return {"success": true, "data": "\n".join(results)}


func _do_request(http: HTTPRequest, url: String) -> String:
	# HTTPRequest must be in the scene tree to work
	var output: String = ""
	var done := false

	var root: Node = (Engine.get_main_loop() as SceneTree).root
	root.add_child(http)
	http.request(url, ["User-Agent: Mozilla/5.0"])
	http.request_completed.connect(func(_result, _code, _headers, body: PackedByteArray):
		output = body.get_string_from_utf8()
		done = true
	)

	# Wait for completion with timeout
	var start := Time.get_ticks_msec()
	while not done:
		if Time.get_ticks_msec() - start > 15000:
			break
		await Engine.get_main_loop().process_frame

	if http.is_inside_tree():
		http.queue_free()
	return output


func _parse_ddg_results(html: String) -> Array:
	var results: Array = []
	var regex := RegEx.new()
	regex.compile("class=\"result__a[^>]*>(.*?)</a>")
	var matches := regex.search_all(html)
	for m in matches:
		var title := m.get_string(1).strip_edges()
		# Strip HTML tags
		title = RegEx.create_from_string("<[^>]+>").sub(title, "", true)
		if title != "":
			results.append("- %s" % title)
		if results.size() >= 10:
			break
	return results
