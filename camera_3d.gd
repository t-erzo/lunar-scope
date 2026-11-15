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
