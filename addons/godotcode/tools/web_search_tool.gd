class_name GCWebSearchTool
extends GCBaseTool
## Web search using the web_eyes local API (SearXNG + crawl + summarize)


func _init() -> void:
	super._init(
		"WebSearch",
		"Search the web and return summarized results. Provides up-to-date information from the internet.",
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

	var settings: GCSettings = context.get("settings", null)
	var base_url: String = "http://localhost:3000"
	if settings:
		base_url = settings.get_web_eyes_url()

	var limit := int(input.get("limit", 5))
	limit = mini(limit, 20)

	var body := JSON.stringify({"query": query, "limit": limit})
	var result := await _post_json(base_url + "/search", body)

	if result == null:
		return {"success": false, "error": "Web search failed — is web_eyes running at %s?" % base_url}

	var summary: String = str(result.get("summary", ""))
	var sources = result.get("sources", [])

	if summary == "" and sources.size() == 0:
		return {"success": true, "data": "No results found for: %s" % query}

	var output: String = summary
	if sources.size() > 0:
		output += "\n\nSources:"
		for src in sources:
			var title: String = str(src.get("title", src.get("url", "")))
			var url: String = str(src.get("url", ""))
			if title != "" and url != "":
				output += "\n- %s (%s)" % [title, url]
			elif url != "":
				output += "\n- %s" % url

	return {"success": true, "data": output}


func _post_json(url: String, json_body: String) -> Dictionary:
	var http := HTTPRequest.new()
	var root: Node = (Engine.get_main_loop() as SceneTree).root
	root.add_child(http)

	var output: Dictionary = {}
	var done := false

	var headers := ["Content-Type: application/json"]
	http.request(url, headers, HTTPClient.METHOD_POST, json_body)
	http.request_completed.connect(func(_result, _code, _headers, body: PackedByteArray):
		var text := body.get_string_from_utf8()
		var json := JSON.new()
		if json.parse(text) == OK:
			output = json.data
		done = true
	)

	var start := Time.get_ticks_msec()
	while not done:
		if Time.get_ticks_msec() - start > 30000:
			break
		await Engine.get_main_loop().process_frame

	if http.is_inside_tree():
		http.queue_free()
	return output
