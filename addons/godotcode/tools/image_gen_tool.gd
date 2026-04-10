class_name GCImageGenTool
extends GCBaseTool
## Generate images via NVIDIA NIM (Flux.1-schnell) or Ollama


func _init() -> void:
	super._init(
		"ImageGen",
		"Generate an image from a text prompt using AI. Returns the generated image for display in chat.",
		{
			"prompt": {
				"type": "string",
				"description": "Description of the image to generate (required)"
			},
			"provider": {
				"type": "string",
				"description": "Provider to use: 'nvidia' (default) or 'ollama'"
			}
		}
	)
	is_read_only = true


func validate_input(input: Dictionary) -> Dictionary:
	if not input.has("prompt") or str(input.get("prompt", "")).strip_edges() == "":
		return {"valid": false, "error": "prompt is required"}
	return {"valid": true}


func execute(input: Dictionary, context: Dictionary) -> Dictionary:
	var prompt: String = str(input.get("prompt", ""))
	var provider: String = str(input.get("provider", ""))

	var settings = context.get("settings")
	if provider == "" and settings and settings.has_method("get_image_gen_provider"):
		provider = settings.get_image_gen_provider()

	match provider:
		"nvidia":
			return await _generate_nvidia(prompt, input, context)
		_:
			return await _generate_ollama(prompt, input, context)


func _generate_ollama(prompt: String, input: Dictionary, context: Dictionary) -> Dictionary:
	var ollama_base: String = "http://localhost:11434"
	var model: String = "llava"

	var settings = context.get("settings")
	if settings:
		if settings.has_method("get_ollama_url"):
			ollama_base = settings.get_ollama_url()
		if settings.has_method("get_image_gen_model"):
			model = settings.get_image_gen_model()

	var url: String = "%s/api/generate" % ollama_base
	var body := JSON.stringify({
		"model": model,
		"prompt": prompt,
		"stream": false
	})

	var http := HTTPRequest.new()
	var root: Node = (Engine.get_main_loop() as SceneTree).root
	root.add_child(http)
	http.timeout = 120.0

	var state: Dictionary = {"output": {}, "done": false}

	var err := http.request(url, _json_headers(), HTTPClient.METHOD_POST, body)
	if err != OK:
		if http.is_inside_tree():
			http.queue_free()
		return {"success": false, "error": "Ollama request failed: %s" % error_string(err)}

	http.request_completed.connect(func(_result, _code, _headers, body_bytes: PackedByteArray):
		var text := body_bytes.get_string_from_utf8()
		var json := JSON.new()
		if json.parse(text) == OK:
			state["output"] = json.data
		state["done"] = true
	)

	var start := Time.get_ticks_msec()
	while not state["done"]:
		if Time.get_ticks_msec() - start > 130000:
			if http.is_inside_tree():
				http.queue_free()
			return {"success": false, "error": "Ollama request timed out"}
		await Engine.get_main_loop().process_frame

	if http.is_inside_tree():
		http.queue_free()

	var output: Dictionary = state["output"]
	if output.is_empty():
		return {"success": false, "error": "Ollama returned empty response — is Ollama running?"}

	# Check for images array in response
	var images = output.get("images", [])
	if images.size() > 0:
		var b64: String = str(images[0])
		return {
			"success": true,
			"data": "Image generated via Ollama (%s)" % model,
			"is_vision": true,
			"vision_data": b64,
			"media_type": "image/png"
		}

	# Some models return base64 in done_reason or other fields
	var response_text: String = str(output.get("response", ""))
	if response_text != "":
		return {"success": true, "data": response_text}

	return {"success": false, "error": "No image data in Ollama response. Model '%s' may not support image generation." % model}


func _generate_nvidia(prompt: String, input: Dictionary, context: Dictionary) -> Dictionary:
	var api_key: String = ""
	var settings = context.get("settings")
	if settings and settings.has_method("get_nim_api_key"):
		api_key = settings.get_nim_api_key()

	if api_key == "":
		return {"success": false, "error": "NVIDIA NIM requires an API key. Set it in GodotCode settings."}

	var url := "https://ai.api.nvidia.com/v1/genai/black-forest-labs/flux.1-schnell"
	var body := JSON.stringify({
		"prompt": prompt,
		"width": 1024,
		"height": 1024,
		"seed": 0,
		"steps": 4
	})

	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer %s" % api_key,
		"Accept: application/json"
	])

	var http := HTTPRequest.new()
	var root: Node = (Engine.get_main_loop() as SceneTree).root
	root.add_child(http)
	http.timeout = 120.0

	var state: Dictionary = {"output": {}, "done": false}

	var err := http.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		if http.is_inside_tree():
			http.queue_free()
		return {"success": false, "error": "NVIDIA request failed: %s" % error_string(err)}

	http.request_completed.connect(func(_result, _code, _headers, body_bytes: PackedByteArray):
		var text := body_bytes.get_string_from_utf8()
		var json := JSON.new()
		if json.parse(text) == OK:
			state["output"] = json.data
		else:
			state["output"] = {"_raw": text}
		state["done"] = true
	)

	var start := Time.get_ticks_msec()
	while not state["done"]:
		if Time.get_ticks_msec() - start > 130000:
			if http.is_inside_tree():
				http.queue_free()
			return {"success": false, "error": "NVIDIA request timed out"}
		await Engine.get_main_loop().process_frame

	if http.is_inside_tree():
		http.queue_free()

	var output: Dictionary = state["output"]

	if output.has("_raw"):
		return {"success": false, "error": "NVIDIA API returned non-JSON: %s" % str(output["_raw"]).left(200)}

	# Check for API error
	if output.has("status") and str(output.get("status", "")) != "":
		var detail: String = str(output.get("detail", output.get("title", "")))
		return {"success": false, "error": "NVIDIA API error: %s" % detail}

	# Flux.1-schnell returns artifacts array with base64 image data
	var image_data: String = ""

	var artifacts = output.get("artifacts", [])
	for artifact in artifacts:
		if artifact is Dictionary:
			image_data = str(artifact.get("base64", ""))
			if image_data != "":
				break

	# Fallback: check common alternative response structures
	if image_data == "" and output.has("image"):
		var img = output["image"]
		if img is String:
			image_data = img
		elif img is Dictionary and img.has("base64"):
			image_data = str(img["base64"])

	if image_data == "" and output.has("data"):
		var d = output["data"]
		if d is Array and d.size() > 0:
			var first = d[0]
			if first is Dictionary:
				image_data = str(first.get("b64_json", first.get("base64", "")))

	if image_data == "":
		return {"success": false, "error": "No image data in NVIDIA response. Keys: %s" % str(output.keys())}

	return {
		"success": true,
		"data": "Image generated via NVIDIA Flux.1-schnell",
		"is_vision": true,
		"vision_data": image_data,
		"media_type": "image/png"
	}


func _json_headers() -> PackedStringArray:
	return PackedStringArray(["Content-Type: application/json"])
