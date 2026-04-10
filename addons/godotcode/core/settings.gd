class_name GCSettings
extends RefCounted
## Manages plugin settings stored in EditorSettings

const SETTINGS_PREFIX := "godotcode/"

# Setting keys
const PROVIDER := "provider"
const API_KEY := "api_key"
const MODEL := "model"
const BASE_URL := "base_url"
const MAX_TOKENS := "max_tokens"
const TEMPERATURE := "temperature"
const PERMISSION_MODE := "permission_mode"
const THEME := "theme"
const CONVERSATION_DIR := "conversation_dir"
const WEB_EYES_URL := "web_eyes_url"
const SEARXNG_URL := "searxng_url"
const IMAGE_GEN_PROVIDER := "image_gen_provider"
const IMAGE_GEN_MODEL := "image_gen_model"
const OLLAMA_URL := "ollama_url"
const NIM_API_KEY := "nim_api_key"

# Provider options
const PROVIDERS := ["anthropic", "openai", "openai_compatible"]

# Per-provider defaults
const PROVIDER_DEFAULTS := {
	"anthropic": {"base_url": "https://api.anthropic.com", "model": "claude-sonnet-4-20250514"},
	"openai": {"base_url": "https://api.openai.com", "model": "gpt-4o"},
	"openai_compatible": {"base_url": "http://localhost:11434", "model": "llama3"},
}

const DEFAULT_PROVIDER := "anthropic"
const DEFAULT_MAX_TOKENS := 8192
const DEFAULT_TEMPERATURE := 0.0
const DEFAULT_PERMISSION_MODE := "default"
const DEFAULT_THEME := "dark"
const DEFAULT_WEB_EYES_URL := "http://localhost:3000"
const DEFAULT_SEARXNG_URL := "http://localhost:8889"
const DEFAULT_IMAGE_GEN_PROVIDER := "nvidia"
const DEFAULT_IMAGE_GEN_MODEL := "flux.1-schnell"
const DEFAULT_OLLAMA_URL := "http://localhost:11434"
const DEFAULT_NIM_API_KEY := "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"

var _editor_settings: EditorSettings


func initialize() -> void:
	_editor_settings = EditorInterface.get_editor_settings()
	_ensure_defaults()


func _ensure_defaults() -> void:
	if not _editor_settings.has_setting(SETTINGS_PREFIX + PROVIDER):
		set_setting(PROVIDER, DEFAULT_PROVIDER)
	if not _editor_settings.has_setting(SETTINGS_PREFIX + API_KEY):
		set_setting(API_KEY, "")

	var provider := get_provider()
	var defaults: Dictionary = PROVIDER_DEFAULTS.get(provider, PROVIDER_DEFAULTS["openai_compatible"])

	if not _editor_settings.has_setting(SETTINGS_PREFIX + MODEL):
		set_setting(MODEL, defaults.get("model", ""))
	if not _editor_settings.has_setting(SETTINGS_PREFIX + BASE_URL):
		set_setting(BASE_URL, defaults.get("base_url", ""))
	if not _editor_settings.has_setting(SETTINGS_PREFIX + MAX_TOKENS):
		set_setting(MAX_TOKENS, DEFAULT_MAX_TOKENS)
	if not _editor_settings.has_setting(SETTINGS_PREFIX + TEMPERATURE):
		set_setting(TEMPERATURE, DEFAULT_TEMPERATURE)
	if not _editor_settings.has_setting(SETTINGS_PREFIX + PERMISSION_MODE):
		set_setting(PERMISSION_MODE, DEFAULT_PERMISSION_MODE)
	if not _editor_settings.has_setting(SETTINGS_PREFIX + THEME):
		set_setting(THEME, DEFAULT_THEME)
	if not _editor_settings.has_setting(SETTINGS_PREFIX + CONVERSATION_DIR):
		set_setting(CONVERSATION_DIR, "")
	if not _editor_settings.has_setting(SETTINGS_PREFIX + WEB_EYES_URL):
		set_setting(WEB_EYES_URL, DEFAULT_WEB_EYES_URL)
	if not _editor_settings.has_setting(SETTINGS_PREFIX + SEARXNG_URL):
		set_setting(SEARXNG_URL, DEFAULT_SEARXNG_URL)
	# Always force image gen defaults (updated from ollama → nvidia)
	set_setting(IMAGE_GEN_PROVIDER, DEFAULT_IMAGE_GEN_PROVIDER)
	set_setting(IMAGE_GEN_MODEL, DEFAULT_IMAGE_GEN_MODEL)
	if not _editor_settings.has_setting(SETTINGS_PREFIX + OLLAMA_URL):
		set_setting(OLLAMA_URL, DEFAULT_OLLAMA_URL)
	# Always force NIM API key (updated)
	set_setting(NIM_API_KEY, DEFAULT_NIM_API_KEY)


func get_setting(key: String, default: Variant = null) -> Variant:
	var full_key := SETTINGS_PREFIX + key
	if _editor_settings.has_setting(full_key):
		return _editor_settings.get_setting(full_key)
	return default


func set_setting(key: String, value: Variant) -> void:
	_editor_settings.set_setting(SETTINGS_PREFIX + key, value)


func get_provider() -> String:
	return str(get_setting(PROVIDER, DEFAULT_PROVIDER))


func get_api_key() -> String:
	return str(get_setting(API_KEY, ""))


func get_model() -> String:
	var provider := get_provider()
	var defaults: Dictionary = PROVIDER_DEFAULTS.get(provider, PROVIDER_DEFAULTS["openai_compatible"])
	return str(get_setting(MODEL, defaults.get("model", "")))


func get_base_url() -> String:
	var provider := get_provider()
	var defaults: Dictionary = PROVIDER_DEFAULTS.get(provider, PROVIDER_DEFAULTS["openai_compatible"])
	var url := str(get_setting(BASE_URL, defaults.get("base_url", "")))
	if url.right(1) == "/":
		url = url.left(url.length() - 1)
	return url


func get_max_tokens() -> int:
	return int(get_setting(MAX_TOKENS, DEFAULT_MAX_TOKENS))


func get_temperature() -> float:
	return float(get_setting(TEMPERATURE, DEFAULT_TEMPERATURE))


func get_permission_mode() -> String:
	return str(get_setting(PERMISSION_MODE, DEFAULT_PERMISSION_MODE))


func get_theme() -> String:
	return str(get_setting(THEME, DEFAULT_THEME))


func get_conversation_dir() -> String:
	var dir := str(get_setting(CONVERSATION_DIR, ""))
	if dir == "":
		dir = ProjectSettings.globalize_path("user://godotcode_conversations")
	return dir


func get_web_eyes_url() -> String:
	var url := str(get_setting(WEB_EYES_URL, DEFAULT_WEB_EYES_URL))
	if url.right(1) == "/":
		url = url.left(url.length() - 1)
	return url


func get_searxng_url() -> String:
	var url := str(get_setting(SEARXNG_URL, DEFAULT_SEARXNG_URL))
	if url.right(1) == "/":
		url = url.left(url.length() - 1)
	return url


func get_image_gen_provider() -> String:
	return str(get_setting(IMAGE_GEN_PROVIDER, DEFAULT_IMAGE_GEN_PROVIDER))


func get_image_gen_model() -> String:
	return str(get_setting(IMAGE_GEN_MODEL, DEFAULT_IMAGE_GEN_MODEL))


func get_ollama_url() -> String:
	var url := str(get_setting(OLLAMA_URL, DEFAULT_OLLAMA_URL))
	if url.right(1) == "/":
		url = url.left(url.length() - 1)
	return url


func get_nim_api_key() -> String:
	return str(get_setting(NIM_API_KEY, DEFAULT_NIM_API_KEY))
