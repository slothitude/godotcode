class_name GCWebSearchTool
extends GCBaseTool
## Web search using SearXNG directly (instant, no heavy crawling)


func _init() -> void:
	super._init(
		"WebSearch",
		"Search the web and return results with titles, snippets, and URLs. Provides up-to-date information from the internet.",
		{
			"query": {
				"type": "string",
				"description": "The search query (at least 2 characters)"
			},
			"limit": {
				"type": "integer",
				"description": "Max number of results to return (default 5, max 20)"
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

	var limit := int(input.get("limit", 5))
	limit = mini(limit, 20)

	# Query SearXNG directly — instant results with titles + snippets
	var searx_url: String = "http://localhost:8889/search?q=%s&format=json&limit=%d" % [query.uri_encode(), limit]
	var result := await _get_json(searx_url)

	if result.is_empty():
		return {"success": false, "error": "Search failed — is SearXNG running at localhost:8889?"}

	var results = result.get("results", [])
	if results.size() == 0:
		return {"success": true, "data": "No results found for: %s" % query}

	var output: String = "Search results for: %s\n" % query
	var count := 0
	for r in results:
		if count >= limit:
			break
		var title: String = str(r.get("title", ""))
		var url: String = str(r.get("url", ""))
		var snippet: String = str(r.get("content", ""))
		output += "\n%d. %s" % [count + 1, title]
		output += "\n   %s" % url
		if snippet != "":
			output += "\n   %s" % snippet
		count += 1

	return {"success": true, "data": output}


func _get_json(url: String) -> Dictionary:
	var http := HTTPRequest.new()
	var root: Node = (Engine.get_main_loop() as SceneTree).root
	root.add_child(http)

	var output: Dictionary = {}
	var done := false

	http.request(url, [], HTTPClient.METHOD_GET, "")
	http.request_completed.connect(func(_result, _code, _headers, body: PackedByteArray):
		var text := body.get_string_from_utf8()
		var json := JSON.new()
		if json.parse(text) == OK:
			output = json.data
		done = true
	)

	var start := Time.get_ticks_msec()
	while not done:
		if Time.get_ticks_msec() - start > 15000:
			break
		await Engine.get_main_loop().process_frame

	if http.is_inside_tree():
		http.queue_free()
	return output
