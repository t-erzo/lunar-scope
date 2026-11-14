@tool
extends MeshInstance3D

@export_group("Textures")
@export var heightmap: Texture2D
@export var color_map: Texture2D
@export var shift_color_longitude_180: bool = false

@export_group("Dimensions")
@export var radius: float = 20.0
@export var height_scale: float = 0.25
@export var radial_segments: int = 500
@export var rings: int = 256

@export_group("Actions")
@export var generate: bool = false:
	set(value):
		if value:
			build_moon()
func _ready() -> void:
	build_moon()

func build_moon() -> void:
	if heightmap == null:
		push_warning("MoonTerrain: Please assign ldem_4.png to Heightmap first.")
		return

	var img: Image = heightmap.get_image()
	if img.is_compressed():
		img.decompress()

	var width: int = img.get_width()
	var height: int = img.get_height()

	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = radial_segments
	sphere.rings = rings

	var mdt := MeshDataTool.new()
	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, sphere.get_mesh_arrays())
	mdt.create_from_surface(array_mesh, 0)


	for i in range(mdt.get_vertex_count()):
		var v: Vector3 = mdt.get_vertex(i)
		var uv: Vector2 = mdt.get_vertex_uv(i)
		var px: int = clampi(int(uv.x * float(width - 1)), 0, width - 1)
		var py: int = clampi(int(uv.y * float(height - 1)), 0, height - 1)

		
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
		mat.roughness = 0.5
		if shift_color_longitude_180:
			mat.uv1_offset.x = 0.5
		set_surface_override_material(0, mat)
