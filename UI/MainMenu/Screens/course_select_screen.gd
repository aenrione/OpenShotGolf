extends Control


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var button = get_node("%CameraCheckButton")
	button.button_pressed = GlobalSettings.range_settings.camera_follow_mode.value
	GlobalSettings.range_settings.camera_follow_mode.setting_changed.connect(_on_setting_changed)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass


func _on_back_button_pressed() -> void:
	SceneManager.change_scene("res://UI/MainMenu/main_menu.tscn")
