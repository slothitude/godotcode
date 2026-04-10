@tool
extends PanelContainer
## Displays an image from base64 data with save-to-disk support

var _image_bytes: PackedByteArray

@onready var _source_label: Label = $VBox/Header/SourceLabel
@onready var _save_btn: Button = $VBox/Header/SaveBtn
@onready var _texture_rect: TextureRect = $VBox/TextureRect


func _ready() -> void:
	_save_btn.pressed.connect(_on_save_pressed)


func setup(base64_data: String, media_type: String, source_name: String) -> void:
	_source_label.text = source_name

	_image_bytes = Marshalls.base64_to_raw(base64_data)
	if _image_bytes.is_empty():
		_source_label.text = source_name + " (decode failed)"
		return

	var image := Image.new()
	var err := OK
	match media_type:
		"image/jpeg", "image/jpg":
			err = image.load_jpg_from_buffer(_image_bytes)
		_:
			err = image.load_png_from_buffer(_image_bytes)

	if err != OK:
		_source_label.text = source_name + " (load failed: %d)" % err
		return

	var texture := ImageTexture.create_from_image(image)
	_texture_rect.texture = texture

	# Cap display height at 300px, maintain aspect ratio
	var aspect := float(image.get_width()) / float(image.get_height())
	var display_h := mini(image.get_height(), 300)
	var display_w := int(display_h * aspect)
	_texture_rect.custom_minimum_size = Vector2(display_w, display_h)


func _on_save_pressed() -> void:
	if _image_bytes.is_empty():
		return

	var dialog := EditorFileDialog.new()
	dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	dialog.add_filter("*.png", "PNG Image")
	dialog.add_filter("*.jpg", "JPEG Image")
	dialog.current_file = "image_%d.png" % Time.get_ticks_msec()
	dialog.file_selected.connect(_on_file_selected.bind(dialog))
	add_child(dialog)
	dialog.popup_centered(Vector2i(600, 400))


func _on_file_selected(path: String, dialog: EditorFileDialog) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_buffer(_image_bytes)
		file.close()
	dialog.queue_free()
