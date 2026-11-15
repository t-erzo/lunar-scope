@tool
extends MeshInstance3D

enum BodyType { MOON, EARTH }

@export var body_type: BodyType = BodyType.MOON:
	set(value):
		body_type = value
		_apply_body_presets()
		if is_inside_tree():
			build_object()

@export var auto_scale_presets: bool = true

@export_group("Textures")
@export var heightmap: Texture2D
@export var color_map: Texture2D
@export var shift_color_longitude_180: bool = false

@export_group("Dimensions")
@export var radius: float = 20.0
@export var height_scale: float = 0.25
@export var radial_segments: int = 500
@export var rings: int = 256
@export_group("Textures")
@export var flip_texture_horizontal: bool = false
@export var flip_texture_vertical: bool = false


@export_group("Actions")
@export var generate: bool = false:
	set(value):
		if value:
			build_object()

func _ready() -> void:
	if auto_scale_presets:
		_apply_body_presets()
	build_object()

func _apply_body_presets() -> void:
	if not auto_scale_presets:
		return
	rotation_order = EULER_ORDER_ZXY
	if body_type == BodyType.MOON:
		radius = 20.0          # Real Moon radius: 1,737.4 km
		height_scale = 0.25    # Lunar craters & highlands
		rotation_degrees.z = 6.68 # Moon's axial tilt relative to ecliptic
	elif body_type == BodyType.EARTH:
		radius = 73.3          # Real Earth radius: 6,371 km (scaled to Moon = 20.0)
		height_scale = 0.35    # Continental elevation relief
		rotation_degrees.z = -23.44 # Earth's 23.44° axial tilt

func build_object() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = radial_segments
	sphere.rings = rings

	var mdt := MeshDataTool.new()
	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, sphere.get_mesh_arrays())
	mdt.create_from_surface(array_mesh, 0)

	if heightmap != null:
		var img: Image = heightmap.get_image()
		if img.is_compressed():
			img.decompress()

		var width: int = img.get_width()
		var height: int = img.get_height()

		for i in range(mdt.get_vertex_count()):
			var v: Vector3 = mdt.get_vertex(i)
			var uv: Vector2 = mdt.get_vertex_uv(i)
			var u := (1.0 - uv.x) if flip_texture_horizontal else uv.x
			var vv := (1.0 - uv.y) if flip_texture_vertical else uv.y
			var px: int = clampi(int(u * float(width - 1)), 0, width - 1)
			var py: int = clampi(int(vv * float(height - 1)), 0, height - 1)

			var elevation: float = img.get_pixel(px, py).r - 0.5
			var dir: Vector3 = v.normalized()
			mdt.set_vertex(i, dir * (radius + elevation * height_scale))

		for i in range(mdt.get_vertex_count()):
			mdt.set_vertex_normal(i, Vector3.ZERO)

		for f in range(mdt.get_face_count()):
			var a: int = mdt.get_face_vertex(f, 0)
			var b: int = mdt.get_face_vertex(f, 1)
			var c: int = mdt.get_face_vertex(f, 2)
			var va: Vector3 = mdt.get_vertex(a)
			var vb: Vector3 = mdt.get_vertex(b)
			var vc: Vector3 = mdt.get_vertex(c)
			var face_normal: Vector3 = (vc - va).cross(vb - va)
			mdt.set_vertex_normal(a, mdt.get_vertex_normal(a) + face_normal)
			mdt.set_vertex_normal(b, mdt.get_vertex_normal(b) + face_normal)
			mdt.set_vertex_normal(c, mdt.get_vertex_normal(c) + face_normal)

		for i in range(mdt.get_vertex_count()):
			mdt.set_vertex_normal(i, mdt.get_vertex_normal(i).normalized())

	array_mesh.clear_surfaces()
	mdt.commit_to_surface(array_mesh)
	mesh = array_mesh

	if color_map != null:
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = color_map
		mat.roughness = 0.85 if body_type == BodyType.MOON else 0.45
		if shift_color_longitude_180:
			mat.uv1_offset.x = 0.5
		if flip_texture_horizontal:
			mat.uv1_scale.x = -1.0
		if flip_texture_vertical:
			mat.uv1_scale.y = -1.0
		set_surface_override_material(0, mat)

	for child in get_children():
		if child is StaticBody3D:
			child.queue_free()

	create_trimesh_collision()
