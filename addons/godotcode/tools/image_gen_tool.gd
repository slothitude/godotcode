class_name GCImageGenTool
extends GCBaseTool
## Generate or edit images via NVIDIA NIM (Flux.1-schnell / Flux.1-kontext-dev) or Ollama


func _init() -> void:
	super._init(
		"ImageGen",
		"Generate or edit an image using AI. Use 'prompt' to describe what to generate. To edit an existing image, provide one of: 'image' (base64), 'file_path' (project file), or 'edit_last' (reuse last generated image).",
		{
			"prompt": {
				"type": "string",
				"description": "Description of the image to generate, or edit instruction when editing an image (required)"
			},
			"image": {
				"type": "string",
				"description": "Base64-encoded image to edit (optional, for image editing mode)"
			},
			"file_path": {
				"type": "string",
				"description": "Path to an image file in the project to edit (e.g. 'res://icon.png' or 'assets/photo.jpg'). Used instead of 'image'."
			},
			"edit_last": {
				"type": "boolean",
				"description": "Set to true to edit the last generated or displayed image (no need to provide image data)"
			},
			"aspect_ratio": {
				"enum": ["match_input_image", "1:1", "16:9", "9:16", "4:3", "3:4"],
				"description": "Aspect ratio for the output (default: match_input_image when editing, 1:1 when generating)"
			},
			"seed": {
				"type": "integer",
				"description": "Random seed for reproducibility (default: 0 = random)"
			},
			"provider": {
				"type": "string",
				"description": "Provider to use: 'nvidia' (default), 'comfyui' (local ComfyUI with Flux), or 'ollama'"
			}
		}
	)
	is_read_only = true


func validate_input(input: Dictionary) -> Dictionary:
	if not input.has("prompt") or str(input.get("prompt", "")).strip_edges() == "":
		return {"valid": false, "error": "prompt is required"}

	# If file_path given, verify it exists
	var fp: String = str(input.get("file_path", ""))
	if fp != "":
		var resolved := _resolve_path(fp)
		if not FileAccess.file_exists(resolved):
			return {"valid": false, "error": "file not found: %s" % fp}

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
		"comfyui":
			return await _generate_comfyui(prompt, input, context)
		_:
			return await _generate_ollama(prompt, input, context)


func _resolve_input_image(input: Dictionary, context: Dictionary) -> Dictionary:
	## Resolves the input image from whichever source is provided.
	## Returns {"base64": "...", "media_type": "..."} or {"error": "..."}
	var has_image := input.has("image") and str(input.get("image", "")) != ""
	var has_file := input.has("file_path") and str(input.get("file_path", "")) != ""
	var edit_last: bool = input.get("edit_last", false)

	if not has_image and not has_file and not edit_last:
		return {"base64": "", "media_type": ""}  # No image = generation mode

	var base64_data: String = ""
	var media_type: String = "image/png"

	# Priority: explicit image > file_path > edit_last
	if has_image:
		base64_data = str(input["image"])
		# Detect media type from the data URI if present
		if base64_data.begins_with("data:"):
			var sep := base64_data.find(",")
			if sep > 0:
				var header := base64_data.substr(0, sep)
				if header.find("image/jpeg") != -1:
					media_type = "image/jpeg"
				elif header.find("image/webp") != -1:
					media_type = "image/webp"
				base64_data = base64_data.substr(sep + 1)
		return {"base64": base64_data, "media_type": media_type}

	if has_file:
		var fp: String = str(input["file_path"])
		var resolved := _resolve_path(fp)
		var file := FileAccess.open(resolved, FileAccess.READ)
		if not file:
			return {"error": "Cannot open file: %s" % fp}
		var bytes := file.get_buffer(file.get_length())
		file.close()
		if bytes.is_empty():
			return {"error": "File is empty: %s" % fp}
		# Detect format
		if bytes.size() >= 3 and bytes[0] == 0xFF and bytes[1] == 0xD8:
			media_type = "image/jpeg"
		elif bytes.size() >= 12 and bytes[8] == 0x57 and bytes[9] == 0x45:
			media_type = "image/webp"
		base64_data = Marshalls.raw_to_base64(bytes)
		return {"base64": base64_data, "media_type": media_type}

	# edit_last: pull from context
	if edit_last:
		var last_vision = context.get("last_vision_data", "")
		var last_type = context.get("last_vision_media_type", "image/png")
		if last_vision == "":
			return {"error": "No previous image to edit. Generate an image first."}
		return {"base64": last_vision, "media_type": last_type}

	return {"base64": "", "media_type": ""}


func _resolve_path(path: String) -> String:
	if path.begins_with("res://"):
		return ProjectSettings.globalize_path(path)
	if path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	return path


func _generate_nvidia(prompt: String, input: Dictionary, context: Dictionary) -> Dictionary:
	var api_key: String = ""
	var settings = context.get("settings")
	if settings and settings.has_method("get_nim_api_key"):
		api_key = settings.get_nim_api_key()

	if api_key == "":
		return {"success": false, "error": "NVIDIA NIM requires an API key. Set it in GodotCode settings."}

	# Resolve input image
	var img_result := _resolve_input_image(input, context)
	if img_result.has("error"):
		return {"success": false, "error": img_result["error"]}

	var input_b64: String = img_result.get("base64", "")
	var input_media: String = img_result.get("media_type", "image/png")
	var is_edit := input_b64 != ""

	var url: String
	var payload: Dictionary
	var seed: int = input.get("seed", 0)

	if is_edit:
		# Flux.1-kontext-dev: image editing
		# NOTE: NVIDIA NIM hosted kontext-dev only accepts example_id references
		# to preset images — custom base64 uploads are rejected by the API.
		# We send base64 anyway; if rejected, we return a clear error.
		url = "https://ai.api.nvidia.com/v1/genai/black-forest-labs/flux.1-kontext-dev"
		var data_uri := "data:%s;base64,%s" % [input_media, input_b64]
		var aspect: String = str(input.get("aspect_ratio", "match_input_image"))
		payload = {
			"prompt": prompt,
			"image": data_uri,
			"aspect_ratio": aspect,
			"steps": 20,
			"cfg_scale": 3.5,
			"seed": seed
		}
	else:
		# Flux.1-schnell: fast image generation
		url = "https://ai.api.nvidia.com/v1/genai/black-forest-labs/flux.1-schnell"
		payload = {
			"prompt": prompt,
			"width": 1024,
			"height": 1024,
			"seed": seed,
			"steps": 4
		}

	var body := JSON.stringify(payload)

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
	if output.has("detail"):
		var detail_str := str(output["detail"])
		# Check for the kontext-dev custom image rejection
		if detail_str.find("example_id") != -1:
			return {"success": false, "error": "NVIDIA kontext-dev does not support custom image uploads on the hosted endpoint. Use 'provider: ollama' with a local model for image editing."}
		return {"success": false, "error": "NVIDIA API error: %s" % detail_str}

	# Extract image data from response
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
		"data": "Image via NVIDIA Flux.1-kontext-dev (edit)" if is_edit else "Image via NVIDIA Flux.1-schnell",
		"is_vision": true,
		"vision_data": image_data,
		"media_type": "image/jpeg"
	}


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

	var response_text: String = str(output.get("response", ""))
	if response_text != "":
		return {"success": true, "data": response_text}

	return {"success": false, "error": "No image data in Ollama response. Model '%s' may not support image generation." % model}


func _json_headers() -> PackedStringArray:
	return PackedStringArray(["Content-Type: application/json"])


# ── ComfyUI provider ──────────────────────────────────────────────

# Stored as raw JSON strings to preserve integer types in link arrays
const _SCHNELL_JSON := '{"1":{"class_type":"UnetLoaderGGUF","inputs":{"unet_name":"flux1-schnell-Q3_K_S.gguf"}},"2":{"class_type":"DualCLIPLoaderGGUF","inputs":{"clip_name1":"clip_l.safetensors","clip_name2":"t5xxl-Q4_K_S.gguf","type":"flux"}},"3":{"class_type":"CLIPTextEncode","inputs":{"text":"","clip":["2",0]}},"4":{"class_type":"CLIPTextEncode","inputs":{"text":"","clip":["2",0]}},"5":{"class_type":"EmptyLatentImage","inputs":{"width":1024,"height":1024,"batch_size":1}},"6":{"class_type":"KSampler","inputs":{"seed":42,"steps":4,"cfg":1.0,"sampler_name":"euler","scheduler":"simple","denoise":1.0,"model":["1",0],"positive":["3",0],"negative":["4",0],"latent_image":["5",0]}},"7":{"class_type":"VAELoader","inputs":{"vae_name":"ae.safetensors"}},"8":{"class_type":"VAEDecode","inputs":{"samples":["6",0],"vae":["7",0]}},"9":{"class_type":"SaveImage","inputs":{"images":["8",0],"filename_prefix":"flux_schnell"}}}'

const _KONTEXT_JSON := '{"1":{"class_type":"UnetLoaderGGUF","inputs":{"unet_name":"flux1-kontext-dev-Q3_K_S.gguf"}},"2":{"class_type":"DualCLIPLoaderGGUF","inputs":{"clip_name1":"clip_l.safetensors","clip_name2":"t5xxl-Q4_K_S.gguf","type":"flux"}},"3":{"class_type":"CLIPTextEncode","inputs":{"text":"","clip":["2",0]}},"4":{"class_type":"CLIPTextEncode","inputs":{"text":"","clip":["2",0]}},"5":{"class_type":"LoadImage","inputs":{"image":"example.png"}},"6":{"class_type":"FluxKontextImageScale","inputs":{"image":["5",0]}},"7":{"class_type":"VAELoader","inputs":{"vae_name":"ae.safetensors"}},"8":{"class_type":"VAEEncode","inputs":{"pixels":["6",0],"vae":["7",0]}},"9":{"class_type":"KSampler","inputs":{"seed":42,"steps":28,"cfg":2.5,"sampler_name":"euler","scheduler":"simple","denoise":0.85,"model":["1",0],"positive":["3",0],"negative":["4",0],"latent_image":["8",0]}},"10":{"class_type":"VAEDecode","inputs":{"samples":["9",0],"vae":["7",0]}},"11":{"class_type":"SaveImage","inputs":{"images":["10",0],"filename_prefix":"kontext"}}}'



func _generate_comfyui(prompt: String, input: Dictionary, context: Dictionary) -> Dictionary:
	var comfyui_base: String = "http://192.168.0.18:8202"
	var settings = context.get("settings")
	if settings and settings.has_method("get_comfyui_url"):
		comfyui_base = settings.get_comfyui_url()

	# Resolve input image
	var img_result := _resolve_input_image(input, context)
	if img_result.has("error"):
		return {"success": false, "error": img_result["error"]}

	var input_b64: String = img_result.get("base64", "")
	var is_edit := input_b64 != ""
	var seed: int = input.get("seed", 0)

	# Build workflow JSON via string replacement (avoids GDScript float coercion)
	var workflow_json: String
	if is_edit:
		# Upload image first
		var uploaded_name := await _comfyui_upload_image(input_b64, comfyui_base)
		if uploaded_name == "":
			return {"success": false, "error": "Failed to upload image to ComfyUI"}
		workflow_json = _KONTEXT_JSON
		# Node 3 is the first CLIPTextEncode — replace its empty text with our prompt
		# Both node 3 and 4 have "text":"", so we use the unique clip link ["2",0]}},"4" pattern
		workflow_json = workflow_json.replace('"text":"","clip":["2",0]}},"4"', '"text":"%s","clip":["2",0]}},"4"' % prompt.json_escape())
		workflow_json = workflow_json.replace('"seed":42', '"seed":%d' % seed)
		workflow_json = workflow_json.replace('"image":"example.png"', '"image":"%s"' % uploaded_name)
	else:
		workflow_json = _SCHNELL_JSON
		# Node 3 is the first CLIPTextEncode — same pattern
		workflow_json = workflow_json.replace('"text":"","clip":["2",0]}},"4"', '"text":"%s","clip":["2",0]}},"4"' % prompt.json_escape())
		workflow_json = workflow_json.replace('"seed":42', '"seed":%d' % seed)

	# Submit workflow as raw JSON string
	var submit_body := '{"prompt":%s,"client_id":"godotcode"}' % workflow_json
	var http := HTTPRequest.new()
	var root: Node = (Engine.get_main_loop() as SceneTree).root
	root.add_child(http)
	http.timeout = 300.0

	var state: Dictionary = {"output": {}, "done": false}
	var err := http.request("%s/prompt" % comfyui_base, _json_headers(), HTTPClient.METHOD_POST, submit_body)
	if err != OK:
		if http.is_inside_tree(): http.queue_free()
		return {"success": false, "error": "ComfyUI request failed: %s" % error_string(err)}

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
		if Time.get_ticks_msec() - start > 300000:
			if http.is_inside_tree(): http.queue_free()
			return {"success": false, "error": "ComfyUI submit timed out"}
		await Engine.get_main_loop().process_frame

	if http.is_inside_tree(): http.queue_free()

	var output: Dictionary = state["output"]
	if output.has("_raw"):
		return {"success": false, "error": "ComfyUI returned non-JSON: %s" % str(output["_raw"]).left(200)}

	if output.has("node_errors"):
		var ne = output["node_errors"]
		if ne is Dictionary and ne.size() > 0:
			return {"success": false, "error": "ComfyUI node errors: %s" % str(ne).left(300)}

	var prompt_id: String = str(output.get("prompt_id", ""))
	if prompt_id == "":
		return {"success": false, "error": "ComfyUI did not return prompt_id: %s" % str(output).left(200)}

	# Poll for completion
	var poll_http := HTTPRequest.new()
	root.add_child(poll_http)
	poll_http.timeout = 30.0

	var poll_state: Dictionary = {"output": {}, "done": false}

	while true:
		poll_state["done"] = false
		var poll_err := poll_http.request("%s/history/%s" % [comfyui_base, prompt_id], _json_headers(), HTTPClient.METHOD_GET, "")
		if poll_err != OK:
			if poll_http.is_inside_tree(): poll_http.queue_free()
			return {"success": false, "error": "ComfyUI poll failed"}

		poll_http.request_completed.connect(func(_result, _code, _headers, body_bytes: PackedByteArray):
			var text := body_bytes.get_string_from_utf8()
			var json := JSON.new()
			if json.parse(text) == OK:
				poll_state["output"] = json.data
			poll_state["done"] = true
		)

		var poll_start := Time.get_ticks_msec()
		while not poll_state["done"]:
			if Time.get_ticks_msec() - poll_start > 30000:
				break
			await Engine.get_main_loop().process_frame

		var history: Dictionary = poll_state["output"]
		if history.has(prompt_id):
			var status: Dictionary = history[prompt_id].get("status", {})
			if status.get("completed", false) or status.get("status_str") == "success":
				break
			if status.get("status_str") == "error":
				if poll_http.is_inside_tree(): poll_http.queue_free()
				return {"success": false, "error": "ComfyUI execution error"}

		await Engine.get_main_loop().create_timer(2.0).timeout

	if poll_http.is_inside_tree(): poll_http.queue_free()

	# Extract output image info
	var outputs: Dictionary = poll_state["output"].get(prompt_id, {}).get("outputs", {})
	var image_info: Dictionary
	for node_id in outputs:
		var node_out = outputs[node_id]
		if node_out is Dictionary and node_out.has("images"):
			var images = node_out["images"]
			if images is Array and images.size() > 0:
				image_info = images[0]
				break

	if not image_info.has("filename"):
		return {"success": false, "error": "No image in ComfyUI output"}

	# Download the image
	var filename: String = str(image_info.get("filename", ""))
	var subfolder: String = str(image_info.get("subfolder", ""))
	var dl_url := "%s/view?filename=%s&subfolder=%s&type=output" % [comfyui_base, filename.uri_encode(), subfolder.uri_encode()]

	var dl_http := HTTPRequest.new()
	root.add_child(dl_http)
	dl_http.timeout = 60.0

	var dl_state: Dictionary = {"data": PackedByteArray(), "done": false}
	var dl_err := dl_http.request(dl_url, _json_headers(), HTTPClient.METHOD_GET, "")
	if dl_err != OK:
		if dl_http.is_inside_tree(): dl_http.queue_free()
		return {"success": false, "error": "Failed to download ComfyUI image"}

	dl_http.request_completed.connect(func(_result, _code, _headers, body_bytes: PackedByteArray):
		dl_state["data"] = body_bytes
		dl_state["done"] = true
	)

	var dl_start := Time.get_ticks_msec()
	while not dl_state["done"]:
		if Time.get_ticks_msec() - dl_start > 60000:
			if dl_http.is_inside_tree(): dl_http.queue_free()
			return {"success": false, "error": "Image download timed out"}
		await Engine.get_main_loop().process_frame

	if dl_http.is_inside_tree(): dl_http.queue_free()

	var img_bytes: PackedByteArray = dl_state["data"]
	if img_bytes.is_empty():
		return {"success": false, "error": "ComfyUI returned empty image"}

	var media_type := "image/png"
	if img_bytes.size() >= 3 and img_bytes[0] == 0xFF and img_bytes[1] == 0xD8:
		media_type = "image/jpeg"

	return {
		"success": true,
		"data": "Image via ComfyUI Flux.1-kontext-dev (edit)" if is_edit else "Image via ComfyUI Flux.1-schnell",
		"is_vision": true,
		"vision_data": Marshalls.raw_to_base64(img_bytes),
		"media_type": media_type,
	}


func _comfyui_upload_image(base64_data: String, base_url: String) -> String:
	## Upload base64 image to ComfyUI and return the server-side filename.
	var img_bytes := Marshalls.base64_to_raw(base64_data)
	if img_bytes.is_empty():
		return ""

	var filename := "godotcode_upload_%d.png" % Time.get_ticks_msec()

	# Build multipart form body
	var boundary := "----GodotCodeBoundary%d" % Time.get_ticks_msec()
	var header := (
		"--%s\r\n" % boundary +
		"Content-Disposition: form-data; name=\"image\"; filename=\"%s\"\r\n" % filename +
		"Content-Type: image/png\r\n\r\n"
	)
	var footer := "\r\n--%s--\r\n" % boundary
	var body := header.to_utf8_buffer() + img_bytes + footer.to_utf8_buffer()

	var http := HTTPRequest.new()
	var root: Node = (Engine.get_main_loop() as SceneTree).root
	root.add_child(http)
	http.timeout = 60.0

	var state: Dictionary = {"output": {}, "done": false}
	var err := http.request_raw(
		"%s/upload/image" % base_url,
		PackedStringArray(["Content-Type: multipart/form-data; boundary=%s" % boundary]),
		HTTPClient.METHOD_POST,
		body
	)
	if err != OK:
		if http.is_inside_tree(): http.queue_free()
		return ""

	http.request_completed.connect(func(_result, _code, _headers, body_bytes: PackedByteArray):
		var text := body_bytes.get_string_from_utf8()
		var json := JSON.new()
		if json.parse(text) == OK:
			state["output"] = json.data
		state["done"] = true
	)

	var start := Time.get_ticks_msec()
	while not state["done"]:
		if Time.get_ticks_msec() - start > 60000:
			if http.is_inside_tree(): http.queue_free()
			return ""
		await Engine.get_main_loop().process_frame

	if http.is_inside_tree(): http.queue_free()

	return str(state["output"].get("name", ""))
