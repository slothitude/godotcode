class_name GCWebFetchTool
extends GCBaseTool
## Fetch URL content and convert HTML to text


func _init() -> void:
	super._init(
		"WebFetch",
		"Fetch content from a URL and return it as text.",
		{
			"url": {
				"type": "string",
				"description": "The URL to fetch"
			}
		}
	)


func validate_input(input: Dictionary) -> Dictionary:
	if not input.has("url"):
		return {"valid": false, "error": "url is required"}
	return {"valid": true}


func execute(input: Dictionary, context: Dictionary) -> Dictionary:
	var url: String = str(input.get("url", ""))

	if url == "":
		return {"success": false, "error": "url is required"}

	if not url.begins_with("http://") and not url.begins_with("https://"):
		return {"success": false, "error": "url must start with http:// or https://"}

	var result := await _fetch_url(url)
	if result == null:
		return {"success": false, "error": "Failed to fetch URL: %s" % url}

	# Strip HTML tags for plain text
	var text := _html_to_text(result)
	# Truncate if too long
	if text.length() > 50000:
		text = text.left(50000) + "\n... [truncated]"

	return {"success": true, "data": text}


func _fetch_url(url: String) -> String:
	var http := HTTPRequest.new()
	var root := Engine.get_main_loop().root
	root.add_child(http)

	var output: String = ""
	var done := false

	http.request(url, [
		"User-Agent: Mozilla/5.0 (compatible; GCCode/1.0)",
		"Accept: text/html,text/plain,application/json"
	])
	http.request_completed.connect(func(_result, _code, _headers, body: PackedByteArray):
		output = body.get_string_from_utf8()
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


func _html_to_text(html: String) -> String:
	var text := html
	# Remove script and style blocks
	var regex := RegEx.new()
	regex.compile("<script[^>]*>[\\s\\S]*?</script>")
	text = regex.sub(text, "", true)
	regex.compile("<style[^>]*>[\\s\\S]*?</style>")
	text = regex.sub(text, "", true)
	# Convert line breaks
	regex.compile("<br[^>]*>")
	text = regex.sub(text, "\n", true)
	regex.compile("</p>")
	text = regex.sub(text, "\n", true)
	regex.compile("</div>")
	text = regex.sub(text, "\n", true)
	regex.compile("</h[1-6]>")
	text = regex.sub(text, "\n", true)
	regex.compile("</li>")
	text = regex.sub(text, "\n", true)
	# Remove remaining tags
	regex.compile("<[^>]+>")
	text = regex.sub(text, "", true)
	# Decode entities
	text = text.replace("&amp;", "&")
	text = text.replace("&lt;", "<")
	text = text.replace("&gt;", ">")
	text = text.replace("&quot;", "\"")
	text = text.replace("&#39;", "'")
	text = text.replace("&nbsp;", " ")
	# Collapse whitespace
	regex.compile("\\n{3,}")
	text = regex.sub(text, "\n\n", true)
	regex.compile("^[ \\t]+")
	text = regex.sub(text, "", true)
	return text.strip_edges()
