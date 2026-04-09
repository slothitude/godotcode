extends GdUnitTestSuite
## Tests for GCSettings

const settings_path := "res://addons/godotcode/core/settings.gd"


func test_settings_loads_without_errors() -> void:
	var settings := GCSettings.new()
	assert_not_null(settings)


func test_default_model() -> void:
	var settings := GCSettings.new()
	var model := settings.DEFAULT_MODEL
	assert_str(model).is_equal("claude-sonnet-4-20250514")


func test_default_base_url() -> void:
	var settings := GCSettings.new()
	var url := settings.DEFAULT_BASE_URL
	assert_str(url).is_equal("https://api.anthropic.com")


func test_default_max_tokens() -> void:
	var settings := GCSettings.new()
	assert_int(settings.DEFAULT_MAX_TOKENS).is_equal(8192)


func test_default_permission_mode() -> void:
	var settings := GCSettings.new()
	assert_str(settings.DEFAULT_PERMISSION_MODE).is_equal("default")
