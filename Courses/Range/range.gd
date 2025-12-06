extends Node3D

enum LayoutType {
	DEFAULT = 0,
	OVERVIEW = 1,
	DETAIL = 2,
}

const LAYOUT_PATHS = {
	LayoutType.DEFAULT: "res://UI/Layouts/default_layout.tscn",
	LayoutType.OVERVIEW: "res://UI/Layouts/overview_layout.tscn",
	LayoutType.DETAIL: "res://UI/Layouts/detail_layout.tscn",
}

const LAYOUT_NAMES = {
	LayoutType.DEFAULT: "default",
	LayoutType.OVERVIEW: "overview",
	LayoutType.DETAIL: "detail",
}

var track_points : bool = false
var trail_timer : float = 0.0
var trail_resolution : float = 0.1
var apex := 0
var display_data: Dictionary = {
	"Distance": "---",
	"Carry": "---",
	"Offline": "---",
	"Apex": "---",
	"VLA": 0.0,
	"HLA": 0.0,
	"Speed": "---",
	"BackSpin": "---",
	"SideSpin": "---",
	"TotalSpin": "---",
	"SpinAxis": "---"
}
var ball_reset_time := 5.0
var auto_reset_enabled := false
var raw_ball_data: Dictionary = {}
var last_display: Dictionary = {}

var camera_controller: CameraController = null

var layout_container: Control = null
var current_layout_type: LayoutType = LayoutType.DEFAULT
var available_layout_types: Array[LayoutType] = [LayoutType.DEFAULT, LayoutType.OVERVIEW, LayoutType.DETAIL]
var current_layout_index: int = 0


func _ready() -> void:
	_setup_camera_system()


func _setup_camera_system() -> void:
	if has_node("PhantomCamera3D"):
		$PhantomCamera3D.queue_free()

	camera_controller = CameraController.new()
	camera_controller.name = "CameraController"
	add_child(camera_controller)

	if has_node("Player/Ball"):
		camera_controller.set_ball_target($Player/Ball)

	camera_controller.camera_changed.connect(_on_camera_changed)
	GlobalSettings.range_settings.camera_follow_mode.setting_changed.connect(set_camera_follow_mode)
	GlobalSettings.range_settings.surface_type.setting_changed.connect(_on_surface_changed)
	_apply_surface_to_ball()

	# Connect to EventBus for recording
	EventBus.recording_toggled.connect(_on_recording_toggled)
	EventBus.session_started.connect(_on_session_started)

	# Connect to SessionRecorder signals
	$SessionRecorder.recording_state.connect(_on_session_recorder_recording_state)
	$SessionRecorder.set_session.connect(_on_session_recorder_set_session)

	_setup_layout_system()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_L:
			_cycle_layout()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("reset"):
		_reset_display_data()
		$RangeUI.set_data(display_data)

	_handle_camera_input()


func _handle_camera_input() -> void:
	if not camera_controller:
		return

	if Input.is_action_just_pressed("ui_1"):
		_reset_camera_toggle()
		camera_controller.set_camera_mode(CameraController.CameraMode.BEHIND_BALL)
	elif Input.is_action_just_pressed("ui_2"):
		_reset_camera_toggle()
		camera_controller.set_camera_mode(CameraController.CameraMode.DOWN_THE_LINE)
	elif Input.is_action_just_pressed("ui_3"):
		_reset_camera_toggle()
		camera_controller.set_camera_mode(CameraController.CameraMode.FACE_ON)
	elif Input.is_action_just_pressed("ui_4"):
		_reset_camera_toggle()
		camera_controller.set_camera_mode(CameraController.CameraMode.BIRDS_EYE)
	elif Input.is_action_just_pressed("ui_5"):
		_reset_camera_toggle(true)
		camera_controller.set_camera_mode(CameraController.CameraMode.FOLLOW_BALL)
	elif Input.is_action_just_pressed("ui_c"):
		_reset_camera_toggle()
		camera_controller.next_camera()


func _on_tcp_client_hit_ball(data: Dictionary) -> void:
	raw_ball_data = data.duplicate()
	_update_ball_display()


func _process(_delta: float) -> void:
	# Refresh UI during flight/rollout so carry/apex update live; distance updates only at rest.
	if $Player.get_ball_state() != Enums.BallState.REST:
		_update_ball_display()


func _on_golf_ball_rest(_ball_data) -> void:
	# Show final shot numbers immediately on rest
	_update_ball_display()

	if GlobalSettings.range_settings.auto_ball_reset.value:
		await get_tree().create_timer(GlobalSettings.range_settings.ball_reset_timer.value).timeout
		_reset_display_data()
		$RangeUI.set_data(display_data)
		$Player.reset_ball()

	# No auto reset: leave final numbers visible


func _reset_camera_toggle(toggled_on: bool = false) -> void:
	GlobalSettings.range_settings.camera_follow_mode.set_value(toggled_on)


func _on_camera_changed(_camera_name: String) -> void:
	pass


func set_camera_follow_mode(_value = null) -> void:
	if GlobalSettings.range_settings.camera_follow_mode.value:
		camera_controller.set_camera_mode(CameraController.CameraMode.FOLLOW_BALL)
	else:
		camera_controller.set_camera_mode(CameraController.CameraMode.BEHIND_BALL)


func _apply_surface_to_ball() -> void:
	if $Player.has_node("Ball"):
		$Player/Ball.set_surface(GlobalSettings.range_settings.surface_type.value)


func _on_surface_changed(value) -> void:
	if $Player.has_node("Ball"):
		$Player/Ball.set_surface(value)


func _reset_display_data() -> void:
	raw_ball_data.clear()
	last_display.clear()
	display_data["Distance"] = "---"
	display_data["Carry"] = "---"
	display_data["Offline"] = "---"
	display_data["Apex"] = "---"
	display_data["VLA"] = 0.0
	display_data["HLA"] = 0.0
	display_data["Speed"] = "---"
	display_data["BackSpin"] = "---"
	display_data["SideSpin"] = "---"
	display_data["TotalSpin"] = "---"
	display_data["SpinAxis"] = "---"


func _update_ball_display() -> void:
	# Show distance continuously (updates during flight/rollout, final at rest)
	var show_distance: bool = true
	display_data = ShotFormatter.format_ball_display(raw_ball_data, $Player, GlobalSettings.range_settings.range_units.value, show_distance, display_data)
	last_display = display_data.duplicate()
	$RangeUI.set_data(display_data)


func _setup_layout_system() -> void:
	if not has_node("LayoutContainer"):
		layout_container = Control.new()
		layout_container.name = "LayoutContainer"
		layout_container.layout_mode = 1
		layout_container.anchors_preset = Control.PRESET_FULL_RECT
		add_child(layout_container)
	else:
		layout_container = $LayoutContainer

	for layout_type in available_layout_types:
		var layout_path = LAYOUT_PATHS[layout_type]
		var layout_name = LAYOUT_NAMES[layout_type]

		var layout_scene = load(layout_path)
		var layout = layout_scene.instantiate()
		layout.name = layout_name.capitalize() + "Layout"

		if layout.has_method("set_range"):
			layout.set_range(self)

		layout_container.add_child(layout)
		layout.hide()


		if layout.has_signal("layout_switch_requested"):
			layout.layout_switch_requested.connect(_on_layout_switch_requested)

	_switch_active_layout(LayoutType.DEFAULT)
	EventBus.connect("layout_changed", Callable(self, "_cycle_layout"))


func _switch_active_layout(layout_type: LayoutType) -> void:
	if layout_type not in available_layout_types:
		push_error("Layout type '%s' not found" % layout_type)
		return

	var current_layout_name = LAYOUT_NAMES[current_layout_type]
	if current_layout_name != "":
		var current_layout_node = layout_container.get_node_or_null(current_layout_name.capitalize() + "Layout")
		if current_layout_node:
			if current_layout_node.has_method("deactivate"):
				current_layout_node.deactivate()
			current_layout_node.hide()

	var new_layout_name = LAYOUT_NAMES[layout_type]
	var new_layout_node = layout_container.get_node_or_null(new_layout_name.capitalize() + "Layout")
	if new_layout_node:
		if new_layout_node.has_method("activate"):
			new_layout_node.activate()
		new_layout_node.show()

	current_layout_type = layout_type
	current_layout_index = available_layout_types.find(layout_type)
	print("Switched to layout: %s" % new_layout_name)


func switch_layout(layout_type: LayoutType) -> void:
	_switch_active_layout(layout_type)


func _cycle_layout(_layout_type: String = "") -> void:
	current_layout_index = (current_layout_index + 1) % available_layout_types.size()
	var next_layout_type = available_layout_types[current_layout_index]
	_switch_active_layout(next_layout_type)


func _on_layout_club_selected(club: String) -> void:
	print("Club selected from layout: %s" % club)


func _on_layout_switch_requested(layout_name: String) -> void:
	var layout_type = LayoutType.DEFAULT
	match layout_name:
		"Custom":
			layout_type = LayoutType.DEFAULT
		"Overview":
			layout_type = LayoutType.OVERVIEW
		"Detail":
			layout_type = LayoutType.DETAIL
	_switch_active_layout(layout_type)


func _get_active_layout() -> Control:
	var layout_name = LAYOUT_NAMES[current_layout_type]
	return layout_container.get_node_or_null(layout_name.capitalize() + "Layout")


func update_layout_data(data: Dictionary) -> void:
	var active_layout = _get_active_layout()
	if active_layout and active_layout.has_method("update_data"):
		active_layout.update_data(data)


func _on_recording_toggled() -> void:
	$SessionRecorder.toggle_recording()


func _on_session_started(user: String, dir: String) -> void:
	$SessionRecorder.username = user
	$SessionRecorder.folder_path = dir


func _get_range_header() -> Node:
	var active_layout = _get_active_layout()
	if active_layout:
		return active_layout.get_node_or_null("RangeHeaderContainer")
	return null


func _on_session_recorder_recording_state(value: bool) -> void:
	var range_header = _get_range_header()
	if range_header:
		range_header.set_recording_state(value)

		# Open session popup when recording starts
		if value:
			range_header.open_session_popup($SessionRecorder.username, $SessionRecorder.folder_path)


func _on_session_recorder_set_session(user: String, dir: String) -> void:
	var range_header = _get_range_header()
	if range_header:
		range_header.set_player_name(user)
		range_header.open_session_popup(user, dir)
