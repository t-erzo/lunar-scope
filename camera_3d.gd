extends Camera3D
var ospherepos = Vector3()
var touching = "false"
func _physics_process(_delta: float) -> void:
	var mousexy: Vector2 = get_viewport().get_mouse_position()
	var rorigin: Vector3 = project_ray_origin(mousexy)
	var rend: Vector3 = rorigin + project_ray_normal(mousexy) * 1000
	var space_content = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(rorigin, rend)
	var result: Dictionary = space_content.intersect_ray(query)
	if result:
		ospherepos = result.position
		touching = "true"
	else:
		touching = "false"
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and touching == "true":
		$CSGSphere3D.osphere(ospherepos)
func _ready() -> void:
	pass
func _process(_delta: float) -> void:
	pass
