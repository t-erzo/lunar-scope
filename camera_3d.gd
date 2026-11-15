extends Camera3D

@export var fly_speed: float = 50.0
@export var mouse_sensitivity: float = 0.003

var is_flying: bool = false
var yaw: float = 0.0
var pitch: float = 0.0

func _ready() -> void:
	var rot := rotation
	yaw = rot.y
	pitch = rot.x

func _input(event: InputEvent) -> void:
	# Do not trigger 1 or 2 while typing numbers inside a Latitude/Longitude box
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_1 or event.physical_keycode == KEY_1 or event.keycode == KEY_KP_1:
			_jump_to_body("Earth", 220.0, 120.0)
		elif event.keycode == KEY_2 or event.physical_keycode == KEY_2 or event.keycode == KEY_KP_2:
			_jump_to_body("Moon", 65.0, 40.0)

func _jump_to_body(node_name: String, view_dist: float, new_speed: float) -> void:
	var target := get_tree().root.find_child(node_name, true, false) as Node3D
	if not target:
		print("Could not find 3D node named: ", node_name)
		return

	global_position = target.global_position + Vector3(0.0, view_dist * 0.25, view_dist)
	look_at(target.global_position, Vector3.UP)
	yaw = rotation.y
	pitch = rotation.x
	fly_speed = new_speed

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		is_flying = event.pressed
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if is_flying else Input.MOUSE_MODE_VISIBLE

	if is_flying and event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			fly_speed = clampf(fly_speed * 1.25, 0.5, 50000.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			fly_speed = clampf(fly_speed / 1.25, 0.5, 50000.0)

	if is_flying and event is InputEventMouseMotion:
		yaw -= event.relative.x * mouse_sensitivity
		pitch = clampf(pitch - event.relative.y * mouse_sensitivity, -PI * 0.49, PI * 0.49)
		rotation = Vector3(pitch, yaw, 0.0)

func _process(delta: float) -> void:
	if not is_flying:
		return

	var input_dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): input_dir.z -= 1.0
	if Input.is_key_pressed(KEY_S): input_dir.z += 1.0
	if Input.is_key_pressed(KEY_A): input_dir.x -= 1.0
	if Input.is_key_pressed(KEY_D): input_dir.x += 1.0
	if Input.is_key_pressed(KEY_Q): input_dir.y -= 1.0
	if Input.is_key_pressed(KEY_E): input_dir.y += 1.0

	if input_dir != Vector3.ZERO:
		var speed := fly_speed * (3.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
		translate(input_dir.normalized() * speed * delta)
