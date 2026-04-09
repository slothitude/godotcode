@tool
extends AcceptDialog
## Settings dialog for the GodotCode plugin

var _settings: GCSettings

@onready var _api_key_input: LineEdit = $Content/ApiKeySection/ApiKeyInput
@onready var _model_option: OptionButton = $Content/ModelSection/ModelOption
@onready var _base_url_input: LineEdit = $Content/BaseUrlSection/BaseUrlInput
@onready var _permission_option: OptionButton = $Content/PermissionSection/PermissionOption

const MODELS := [
	"claude-sonnet-4-20250514",
	"claude-opus-4-20250514",
	"claude-haiku-4-5-20251001",
	"claude-3-5-sonnet-20241022",
	"claude-3-5-haiku-20241022",
]

const PERMISSION_MODES := [
	"default",
	"plan",
	"bypass",
]


func _ready() -> void:
	# Populate model options
	for model in MODELS:
		_model_option.add_item(model)

	# Populate permission mode options
	for mode in PERMISSION_MODES:
		_permission_option.add_item(mode)

	# Load current settings
	_load_settings()

	confirmed.connect(_on_confirmed)


func _load_settings() -> void:
	if not _settings:
		return

	_api_key_input.text = _settings.get_api_key()
	_base_url_input.text = _settings.get_base_url()

	var current_model := _settings.get_model()
	for i in MODELS.size():
		if MODELS[i] == current_model:
			_model_option.selected = i
			break
	if _model_option.selected == -1:
		_model_option.selected = 0

	var current_perm := _settings.get_permission_mode()
	for i in PERMISSION_MODES.size():
		if PERMISSION_MODES[i] == current_perm:
			_permission_option.selected = i
			break


func _on_confirmed() -> void:
	if not _settings:
		return

	_settings.set_setting(GCSettings.API_KEY, _api_key_input.text)
	_settings.set_setting(GCSettings.MODEL, MODELS[_model_option.selected])
	_settings.set_setting(GCSettings.BASE_URL, _base_url_input.text)
	_settings.set_setting(GCSettings.PERMISSION_MODE, PERMISSION_MODES[_permission_option.selected])
