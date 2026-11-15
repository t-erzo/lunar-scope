extends Node

@export var moon_node: Node3D
@export var earth_node: Node3D
@export var sun_light: DirectionalLight3D
@export var camera_node: Camera3D
@export var moon_marker: Node3D
@export var earth_marker: Node3D
@export var best_pole_marker: Node3D
@export var moon_radius_godot: float = 20.0
@export var sun_node: Node3D

const REAL_MOON_RADIUS_KM = 1737.4
const REAL_EARTH_RADIUS_KM = 6371.0
const AU_KM = 149597870.7
const C_KM_S = 299792.458
const SOLAR_CONSTANT_WM2 = 1361.0
const MONTH_NAMES = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

# Active Coordinates (Default: 38.68° N, -121.18° W)
var earth_lat_deg: float = 38.68
var earth_lon_deg: float = -121.18

var moon_lat_deg: float = -89.5
var moon_lon_deg: float = 0.0

# Saved Comparison Slot
var pinned_summary: String = "No point pinned yet.\nClick 'Pin Point for Comparison' below."

# Date & Time State
var sel_year: int = 2026
var sel_month: int = 11
var sel_day: int = 15
var sel_step_30m: int = 24
var sim_seconds_offset: float = 0.0
var is_playing_time: bool = false

# Candidate Grid Points & 3D Visual Nodes
var candidate_coords: Array[Vector2] = []
var grid_point_meshes: Array[MeshInstance3D] = []

# UI References
var month_year_label: Label
var calendar_grid: GridContainer
var day_buttons: Array[Button] = []
var time_label: Label
var time_slider: HSlider
var play_btn: Button
var lat_input: LineEdit
var lon_input: LineEdit
var site_list_vbox: VBoxContainer
var telemetry_label: RichTextLabel
var compare_label: Label

func _ready() -> void:
	if earth_node:
		earth_node.rotation_order = EULER_ORDER_ZXY
	if moon_node:
		moon_node.rotation_order = EULER_ORDER_ZXY

	_generate_lunar_grid_points()
	_build_mission_gui()
	_refresh_calendar_grid()
	_update_simulation()

func _generate_lunar_grid_points() -> void:
	candidate_coords.clear()

	# 1. High-density South Pole points (-82° to -89.5°)
	for lat in [-89.5, -87.5, -85.0, -82.5]:
		for lon in [-135.0, -90.0, -45.0, 0.0, 45.0, 90.0, 135.0, 180.0]:
			candidate_coords.append(Vector2(lat, lon))

	# 2. Global sample grid (-60° to +60°)
	for lat in [-60.0, -30.0, 0.0, 30.0, 60.0]:
		for lon in [-90.0, -45.0, 0.0, 45.0, 90.0, 180.0]:
			candidate_coords.append(Vector2(lat, lon))

	var pt_sphere := SphereMesh.new()
	pt_sphere.radius = 0.28
	pt_sphere.height = 0.56
	pt_sphere.radial_segments = 10
	pt_sphere.rings = 6

	for _i in range(candidate_coords.size()):
		var mi := MeshInstance3D.new()
		mi.mesh = pt_sphere
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mi.material_override = mat
		if moon_node:
			moon_node.add_child(mi)
		else:
			add_child(mi)
		grid_point_meshes.append(mi)

func _process(delta: float) -> void:
	if is_playing_time:
		# Advance 2 hours (7200 sec) per real second so Earth spins smoothly
		sim_seconds_offset += delta * 7200.0
		while sim_seconds_offset >= 1800.0:
			sim_seconds_offset -= 1800.0
			_advance_time_step(1)
		_update_simulation()

func _apply_earth_coordinates() -> void:
	if lat_input and lon_input:
		earth_lat_deg = clampf(lat_input.text.to_float(), -90.0, 90.0)
		earth_lon_deg = clampf(lon_input.text.to_float(), -180.0, 180.0)
		lat_input.text = "%.2f" % earth_lat_deg
		lon_input.text = "%.2f" % earth_lon_deg
		lat_input.release_focus()
		lon_input.release_focus()
		_update_simulation()

func _get_earth_visual_radius() -> float:
	if earth_node:
		var r: float = earth_node.radius if ("radius" in earth_node) else ((REAL_EARTH_RADIUS_KM / REAL_MOON_RADIUS_KM) * moon_radius_godot)
		return r * earth_node.scale.x
	return (REAL_EARTH_RADIUS_KM / REAL_MOON_RADIUS_KM) * moon_radius_godot

func _lat_lon_to_vec3(lat_deg: float, lon_deg: float) -> Vector3:
	var lat := deg_to_rad(lat_deg)
	var lon := deg_to_rad(lon_deg)
	return Vector3(
		cos(lat) * sin(lon),
		sin(lat),
		cos(lat) * cos(lon)
	).normalized()

@warning_ignore("integer_division")
@warning_ignore("integer_division")
func _update_simulation() -> void:
	var base_unix := Time.get_unix_time_from_datetime_dict({
		"year": sel_year,
		"month": sel_month,
		"day": sel_day,
		"hour": (sel_step_30m * 30) / 60,
		"minute": (sel_step_30m * 30) % 60,
		"second": 0
	})
	var unix_time: float = float(base_unix) + sim_seconds_offset
	var dt := Time.get_datetime_dict_from_unix_time(int(unix_time))

	time_label.text = "Date: %04d-%02d-%02d  |  Time: %02d:%02d UTC" % [
		dt["year"], dt["month"], dt["day"], dt["hour"], dt["minute"]
	]

	# 1. Compute Moon-centered Earth & Sun vectors
	var positions := _compute_ephemeris_km(unix_time)
	var earth_km: Vector3 = positions["earth"]
	var sun_km: Vector3 = positions["sun"]

	var km_to_units: float = moon_radius_godot / REAL_MOON_RADIUS_KM
	var earth_godot := Vector3(earth_km.x, earth_km.z, -earth_km.y) * km_to_units
	var sun_dir_godot := Vector3(sun_km.x, sun_km.z, -sun_km.y).normalized()

	# 2. Place Earth & Spin Smoothly by Greenwich Mean Sidereal Time (GMST)
	if earth_node:
		earth_node.global_position = earth_godot
		var d_j2000: float = (unix_time - 946728000.0) / 86400.0
		var gmst_deg: float = fmod(280.46061837 + 360.98564736629 * d_j2000, 360.0)
		earth_node.rotation.y = deg_to_rad(gmst_deg)

	# 3. Tidally Lock Moon's Prime Meridian toward Earth
	if moon_node:
		var to_earth_flat := Vector3(earth_godot.x, 0.0, earth_godot.z).normalized()
		if to_earth_flat.length_squared() > 0.001:
			moon_node.rotation.y = atan2(to_earth_flat.x, to_earth_flat.z)

	# 4. Aim Sunlight
	if sun_light and sun_dir_godot != Vector3.ZERO:
		sun_light.look_at_from_position(sun_dir_godot * 500.0, Vector3.ZERO, Vector3.UP)

	if sun_node and sun_dir_godot != Vector3.ZERO:
		# Place Sun at 10,000 units with radius 46.55 -> exact 0.53° true angular size from the Moon
		var moon_center := moon_node.global_position if moon_node else Vector3.ZERO
		sun_node.global_position = moon_center + sun_dir_godot * 10000.0

	# 5. Snap Pink EarthMarker Directly onto Earth's Surface at (earth_lat_deg, earth_lon_deg)
	var earth_visual_r := _get_earth_visual_radius()
	var earth_local_dir := _lat_lon_to_vec3(earth_lat_deg, earth_lon_deg)
	var earth_base_normal := (earth_node.global_transform.basis.orthonormalized() * earth_local_dir).normalized() if earth_node else earth_local_dir
	var earth_base_world := (earth_node.global_position if earth_node else earth_godot) + earth_base_normal * (earth_visual_r + 0.5)
	if earth_marker:
		earth_marker.top_level = true
		earth_marker.global_position = earth_base_world

	# 6. Evaluate, Color & Rank All Lunar Surface Points
	_evaluate_and_rank_points(earth_base_world, earth_base_normal, sun_dir_godot)

	# 7. Update Selected Lunar Point Marker & Telemetry
	var moon_local_dir := _lat_lon_to_vec3(moon_lat_deg, moon_lon_deg)
	var moon_world_normal := (moon_node.global_transform.basis.orthonormalized() * moon_local_dir).normalized() if moon_node else moon_local_dir
	var moon_site_world := (moon_node.global_position if moon_node else Vector3.ZERO) + moon_world_normal * moon_radius_godot
	if moon_marker:
		moon_marker.top_level = true
		moon_marker.global_position = moon_site_world

	_update_telemetry_panel(unix_time, moon_site_world, moon_world_normal, earth_base_world, earth_base_normal, sun_dir_godot)

func _evaluate_and_rank_points(
	earth_base_world: Vector3,
	earth_base_normal: Vector3,
	sun_dir_godot: Vector3
) -> void:
	for child in site_list_vbox.get_children():
		child.queue_free()

	var scored_points: Array[Dictionary] = []
	var best_pole_score: float = -999999.0
	var best_pole_world_pos: Vector3 = Vector3.ZERO

	for i in range(candidate_coords.size()):
		var pt: Vector2 = candidate_coords[i]
		var lat := pt.x
		var lon := pt.y
		var is_south_pole := lat <= -80.0

		var local_dir := _lat_lon_to_vec3(lat, lon)
		var world_normal := (moon_node.global_transform.basis.orthonormalized() * local_dir).normalized() if moon_node else local_dir
		var world_pos := (moon_node.global_position if moon_node else Vector3.ZERO) + world_normal * moon_radius_godot

		var sun_elev_deg := rad_to_deg(asin(clampf(world_normal.dot(sun_dir_godot), -1.0, 1.0)))
		var power_wm2 := maxf(0.0, sin(deg_to_rad(sun_elev_deg))) * SOLAR_CONSTANT_WM2

		var dir_to_base := (earth_base_world - world_pos).normalized()
		var moon_elev_ok := world_normal.dot(dir_to_base) > 0.0
		var earth_elev_ok := earth_base_normal.dot(-dir_to_base) > 0.0
		var comm_ok := moon_elev_ok and earth_elev_ok

		var score := (1000.0 if comm_ok else 0.0) + power_wm2 + (150.0 if is_south_pole else 0.0)

		var mi := grid_point_meshes[i]
		mi.position = local_dir * (moon_radius_godot + 0.15)
		var mat := mi.material_override as StandardMaterial3D
		if mat:
			if comm_ok and power_wm2 > 100.0:
				mat.albedo_color = Color(0.1, 1.0, 0.2)
			elif comm_ok:
				mat.albedo_color = Color(1.0, 0.85, 0.1)
			else:
				mat.albedo_color = Color(0.35, 0.35, 0.4)

		if is_south_pole and score > best_pole_score:
			best_pole_score = score
			best_pole_world_pos = world_pos

		scored_points.append({
			"lat": lat,
			"lon": lon,
			"south_pole": is_south_pole,
			"comm_ok": comm_ok,
			"power_wm2": power_wm2,
			"score": score
		})

	if best_pole_marker and best_pole_world_pos != Vector3.ZERO:
		best_pole_marker.top_level = true
		best_pole_marker.global_position = best_pole_world_pos

	scored_points.sort_custom(func(a, b): return a["score"] > b["score"])

	var show_count := mini(scored_points.size(), 15)
	for i in range(show_count):
		var s: Dictionary = scored_points[i]
		var tag := "[SOUTH POLE] " if s["south_pole"] else ""
		var comm_tag := "COMMS:OK" if s["comm_ok"] else "NO-LOS"
		var btn := Button.new()
		btn.focus_mode = Control.FOCUS_NONE
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.text = "#%d %s(%.1f°, %.1f°) | %.0f W/m² | %s" % [i + 1, tag, s["lat"], s["lon"], s["power_wm2"], comm_tag]
		btn.pressed.connect(func():
			moon_lat_deg = s["lat"]
			moon_lon_deg = s["lon"]
			_update_simulation()
		)
		site_list_vbox.add_child(btn)

func _update_telemetry_panel(
	unix_time: float,
	moon_site_pos: Vector3,
	moon_normal: Vector3,
	earth_base_pos: Vector3,
	earth_base_normal: Vector3,
	sun_dir: Vector3
) -> void:
	# --- SOLAR POWER ---
	var sun_elev_deg := rad_to_deg(asin(clampf(moon_normal.dot(sun_dir), -1.0, 1.0)))
	var is_daylight := sun_elev_deg > 0.0
	var solar_eff_pct := maxf(0.0, sin(deg_to_rad(sun_elev_deg))) * 100.0
	var power_wm2 := (solar_eff_pct / 100.0) * SOLAR_CONSTANT_WM2
	var solar_hours := _scan_window_hours(unix_time, true, is_daylight)
	var solar_window_txt := ("%.1f hrs until Sunset" % solar_hours) if is_daylight else ("%.1f hrs until Sunrise" % solar_hours)

	# --- EARTH BASE COMMUNICATION WINDOW ---
	var site_to_base := earth_base_pos - moon_site_pos
	var dist_km := site_to_base.length() * (REAL_MOON_RADIUS_KM / moon_radius_godot)
	var dir_to_base := site_to_base.normalized()

	var earth_elev_deg := rad_to_deg(asin(clampf(moon_normal.dot(dir_to_base), -1.0, 1.0)))
	var base_elev_deg := rad_to_deg(asin(clampf(earth_base_normal.dot(-dir_to_base), -1.0, 1.0)))
	var link_active := (earth_elev_deg > 0.0) and (base_elev_deg > 0.0)

	var comm_hours := _scan_window_hours(unix_time, false, link_active)
	var comm_window_txt := ("%.1f hrs remaining in window" % comm_hours) if link_active else ("Next window in %.1f hrs" % comm_hours)

	var link_badge := "[color=lime]LINK ACTIVE[/color]" if link_active else (
		"[color=red]EARTH POINT ROTATED AWAY[/color]" if earth_elev_deg > 0.0 else "[color=orange]BELOW LUNAR HORIZON[/color]"
	)

	var txt := ""
	txt += "[b]SELECTED EARTH POINT:[/b] %.2f° Lat, %.2f° Lon\n" % [earth_lat_deg, earth_lon_deg]
	txt += "[b]SELECTED LUNAR POINT:[/b] %.2f° Lat, %.2f° Lon\n\n" % [moon_lat_deg, moon_lon_deg]

	txt += "[b]--- SOLAR POWER OUTPUT ---[/b]\n"
	txt += "Irradiance: [color=yellow]%.0f W/m²[/color] (%.0f%% eff)\n" % [power_wm2, solar_eff_pct]
	txt += "Sun Elevation: %.1f°\n" % sun_elev_deg
	txt += "Solar Window: %s\n\n" % solar_window_txt

	txt += "[b]--- COMMS WINDOW ---[/b]\n"
	txt += "Status: %s\n" % link_badge
	txt += "Window: %s\n" % comm_window_txt
	txt += "Earth Elev (Moon): %.1f° | Moon Elev (Earth): %.1f°\n" % [earth_elev_deg, base_elev_deg]
	txt += "Distance: %.0f km (%.2fs signal delay)" % [dist_km, dist_km / C_KM_S]

	telemetry_label.text = txt

func _scan_window_hours(start_unix: float, check_solar: bool, current_state: bool) -> float:
	var moon_local := _lat_lon_to_vec3(moon_lat_deg, moon_lon_deg)
	var earth_local := _lat_lon_to_vec3(earth_lat_deg, earth_lon_deg)
	var km_to_units: float = moon_radius_godot / REAL_MOON_RADIUS_KM
	var earth_r_units := _get_earth_visual_radius()

	for step in range(1, 672):
		var t: float = start_unix + float(step) * 1800.0
		var pos := _compute_ephemeris_km(t)
		var e_km: Vector3 = pos["earth"]
		var s_km: Vector3 = pos["sun"]

		var e_godot := Vector3(e_km.x, e_km.z, -e_km.y) * km_to_units
		var s_dir := Vector3(s_km.x, s_km.z, -s_km.y).normalized()

		var to_e := Vector3(e_godot.x, 0.0, e_godot.z).normalized()
		var moon_rot_y := atan2(to_e.x, to_e.z)
		var m_norm := moon_local.rotated(Vector3.UP, moon_rot_y)

		if check_solar:
			var is_day := m_norm.dot(s_dir) > 0.0
			if is_day != current_state:
				return float(step) * 0.5
		else:
			var d_j2000: float = (t - 946728000.0) / 86400.0
			var gmst_rad := deg_to_rad(fmod(280.46061837 + 360.98564736629 * d_j2000, 360.0))
			var e_basis := Basis(Vector3.UP, gmst_rad) * Basis(Vector3.FORWARD, deg_to_rad(23.44))
			var e_norm := (e_basis * earth_local).normalized()
			var e_base_pos := e_godot + e_norm * earth_r_units
			var m_site_pos := m_norm * moon_radius_godot
			var dir_to_base := (e_base_pos - m_site_pos).normalized()
			var active := (m_norm.dot(dir_to_base) > 0.0) and (e_norm.dot(-dir_to_base) > 0.0)
			if active != current_state:
				return float(step) * 0.5

	return 336.0

func _advance_time_step(delta_steps: int) -> void:
	sel_step_30m += delta_steps
	while sel_step_30m >= 48:
		sel_step_30m -= 48
		sel_day += 1
		if sel_day > _days_in_month(sel_year, sel_month):
			sel_day = 1
			_change_month(1)
			return
	time_slider.set_value_no_signal(sel_step_30m)
	_refresh_calendar_grid()

func _build_mission_gui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	# === LEFT PANEL: Calendar, Time & Earth Coordinate Input ===
	var left_panel := PanelContainer.new()
	left_panel.position = Vector2(16, 16)
	canvas.add_child(left_panel)

	var l_margin := MarginContainer.new()
	l_margin.add_theme_constant_override("margin_left", 10)
	l_margin.add_theme_constant_override("margin_right", 10)
	l_margin.add_theme_constant_override("margin_top", 10)
	l_margin.add_theme_constant_override("margin_bottom", 10)
	left_panel.add_child(l_margin)

	var l_vbox := VBoxContainer.new()
	l_vbox.add_theme_constant_override("separation", 6)
	l_margin.add_child(l_vbox)

	# Month/Year Nav
	var nav_hbox := HBoxContainer.new()
	l_vbox.add_child(nav_hbox)

	var prev_year_btn := Button.new()
	prev_year_btn.focus_mode = Control.FOCUS_NONE
	prev_year_btn.text = "<<"
	prev_year_btn.pressed.connect(func(): _change_month(-12))
	nav_hbox.add_child(prev_year_btn)

	var prev_month_btn := Button.new()
	prev_month_btn.focus_mode = Control.FOCUS_NONE
	prev_month_btn.text = "<"
	prev_month_btn.pressed.connect(func(): _change_month(-1))
	nav_hbox.add_child(prev_month_btn)

	month_year_label = Label.new()
	month_year_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	month_year_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav_hbox.add_child(month_year_label)

	var next_month_btn := Button.new()
	next_month_btn.focus_mode = Control.FOCUS_NONE
	next_month_btn.text = ">"
	next_month_btn.pressed.connect(func(): _change_month(1))
	nav_hbox.add_child(next_month_btn)

	var next_year_btn := Button.new()
	next_year_btn.focus_mode = Control.FOCUS_NONE
	next_year_btn.text = ">>"
	next_year_btn.pressed.connect(func(): _change_month(12))
	nav_hbox.add_child(next_year_btn)

	# Calendar Grid
	calendar_grid = GridContainer.new()
	calendar_grid.columns = 7
	l_vbox.add_child(calendar_grid)
	for i in range(42):
		var btn := Button.new()
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(32, 26)
		btn.toggle_mode = true
		calendar_grid.add_child(btn)
		day_buttons.append(btn)

	# Time Slider + Play/Pause
	time_label = Label.new()
	l_vbox.add_child(time_label)

	var slider_hbox := HBoxContainer.new()
	l_vbox.add_child(slider_hbox)

	time_slider = HSlider.new()
	time_slider.focus_mode = Control.FOCUS_NONE
	time_slider.min_value = 0
	time_slider.max_value = 47
	time_slider.step = 1
	time_slider.value = sel_step_30m
	time_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	time_slider.value_changed.connect(func(v):
		sel_step_30m = int(v)
		sim_seconds_offset = 0.0
		_update_simulation()
	)
	slider_hbox.add_child(time_slider)

	play_btn = Button.new()
	play_btn.focus_mode = Control.FOCUS_NONE
	play_btn.text = "Play"
	play_btn.pressed.connect(func():
		is_playing_time = not is_playing_time
		play_btn.text = "Pause" if is_playing_time else "Play"
	)
	slider_hbox.add_child(play_btn)

	# Earth Latitude & Longitude Input Boxes
	var coord_hdr := Label.new()
	coord_hdr.text = "Earth Base Coordinates (Lat / Lon):"
	l_vbox.add_child(coord_hdr)

	var coord_hbox := HBoxContainer.new()
	l_vbox.add_child(coord_hbox)

	lat_input = LineEdit.new()
	lat_input.placeholder_text = "Lat (-90..90)"
	lat_input.text = "%.2f" % earth_lat_deg
	lat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lat_input.text_submitted.connect(func(_t): _apply_earth_coordinates())
	coord_hbox.add_child(lat_input)

	lon_input = LineEdit.new()
	lon_input.placeholder_text = "Lon (-180..180)"
	lon_input.text = "%.2f" % earth_lon_deg
	lon_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lon_input.text_submitted.connect(func(_t): _apply_earth_coordinates())
	coord_hbox.add_child(lon_input)

	var apply_btn := Button.new()
	apply_btn.focus_mode = Control.FOCUS_NONE
	apply_btn.text = "Set Earth Point"
	apply_btn.pressed.connect(_apply_earth_coordinates)
	l_vbox.add_child(apply_btn)

	var hint := Label.new()
	hint.text = "Hotkeys: View Earth | View Moon"
	l_vbox.add_child(hint)

	# === RIGHT PANEL: Ranked Lunar Points + Live Telemetry ===
	var right_panel := PanelContainer.new()
	right_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	right_panel.position = Vector2(-395, 16)
	right_panel.custom_minimum_size = Vector2(380, 0)
	canvas.add_child(right_panel)

	var r_margin := MarginContainer.new()
	r_margin.add_theme_constant_override("margin_left", 12)
	r_margin.add_theme_constant_override("margin_right", 12)
	r_margin.add_theme_constant_override("margin_top", 12)
	r_margin.add_theme_constant_override("margin_bottom", 12)
	right_panel.add_child(r_margin)

	var r_vbox := VBoxContainer.new()
	r_vbox.add_theme_constant_override("separation", 8)
	r_margin.add_child(r_vbox)

	telemetry_label = RichTextLabel.new()
	telemetry_label.bbcode_enabled = true
	telemetry_label.fit_content = true
	telemetry_label.custom_minimum_size = Vector2(355, 195)
	r_vbox.add_child(telemetry_label)

	var pin_btn := Button.new()
	pin_btn.focus_mode = Control.FOCUS_NONE
	pin_btn.text = "Pin Point for Comparison"
	pin_btn.pressed.connect(func():
		pinned_summary = "[Pinned] " + telemetry_label.get_parsed_text().left(160)
		compare_label.text = pinned_summary
	)
	r_vbox.add_child(pin_btn)

	compare_label = Label.new()
	compare_label.text = pinned_summary
	compare_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r_vbox.add_child(compare_label)

	var rank_header := Label.new()
	rank_header.text = "Ranked Lunar Points (Green = Best Power + Comms):"
	r_vbox.add_child(rank_header)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(355, 200)
	r_vbox.add_child(scroll)

	site_list_vbox = VBoxContainer.new()
	site_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(site_list_vbox)

func _change_month(delta: int) -> void:
	sel_month += delta
	while sel_month > 12:
		sel_month -= 12
		sel_year += 1
	while sel_month < 1:
		sel_month += 12
		sel_year -= 1
	sel_day = mini(sel_day, _days_in_month(sel_year, sel_month))
	_refresh_calendar_grid()
	_update_simulation()

func _refresh_calendar_grid() -> void:
	month_year_label.text = "%s %d" % [MONTH_NAMES[sel_month - 1], sel_year]
	var first_day_unix := Time.get_unix_time_from_datetime_dict({
		"year": sel_year, "month": sel_month, "day": 1, "hour": 12, "minute": 0, "second": 0
	})
	var start_weekday: int = Time.get_datetime_dict_from_unix_time(first_day_unix)["weekday"]
	var total_days: int = _days_in_month(sel_year, sel_month)

	for i in range(42):
		var btn := day_buttons[i]
		for conn in btn.pressed.get_connections():
			btn.pressed.disconnect(conn["callable"])
		var day_num: int = i - start_weekday + 1
		if day_num >= 1 and day_num <= total_days:
			btn.text = str(day_num)
			btn.disabled = false
			btn.button_pressed = (day_num == sel_day)
			btn.pressed.connect(func():
				sel_day = day_num
				sim_seconds_offset = 0.0
				_refresh_calendar_grid()
				_update_simulation()
			)
		else:
			btn.text = ""
			btn.disabled = true
			btn.button_pressed = false

func _days_in_month(y: int, m: int) -> int:
	if m == 4 or m == 6 or m == 9 or m == 11:
		return 30
	elif m == 2:
		var is_leap := (y % 4 == 0 and y % 100 != 0) or (y % 400 == 0)
		return 29 if is_leap else 28
	return 31

func _compute_ephemeris_km(unix_time: float) -> Dictionary:
	var d: float = (unix_time - 946728000.0) / 86400.0

	var L_prime := deg_to_rad(fmod(218.3164477 + 13.17639648 * d, 360.0))
	var D := deg_to_rad(fmod(297.8501921 + 12.19074912 * d, 360.0))
	var M := deg_to_rad(fmod(357.5291092 + 0.98560028 * d, 360.0))
	var M_prime := deg_to_rad(fmod(134.9633964 + 13.06499295 * d, 360.0))
	var F := deg_to_rad(fmod(93.2720950 + 13.22935024 * d, 360.0))

	var moon_lon := L_prime + deg_to_rad(
		6.288774 * sin(M_prime)
		+ 1.274027 * sin(2.0 * D - M_prime)
		+ 0.658314 * sin(2.0 * D)
		+ 0.213618 * sin(2.0 * M_prime)
		- 0.185116 * sin(M)
		- 0.114332 * sin(2.0 * F)
	)
	var moon_lat := deg_to_rad(
		5.128122 * sin(F)
		+ 0.280602 * sin(M_prime + F)
		+ 0.277693 * sin(M_prime - F)
		+ 0.173237 * sin(2.0 * D - F)
	)
	var moon_dist_km := (
		385000.56
		- 20905.355 * cos(M_prime)
		- 3699.111 * cos(2.0 * D - M_prime)
		- 2955.968 * cos(2.0 * D)
		- 569.925 * cos(2.0 * M_prime)
	)

	var cos_mlat := cos(moon_lat)
	var earth_rel_moon_km := Vector3(
		-moon_dist_km * cos_mlat * cos(moon_lon),
		-moon_dist_km * cos_mlat * sin(moon_lon),
		-moon_dist_km * sin(moon_lat)
	)

	var L_sun := deg_to_rad(fmod(280.460 + 0.9856474 * d, 360.0))
	var sun_lon := L_sun + deg_to_rad(1.915 * sin(M) + 0.020 * sin(2.0 * M))
	var sun_dist_km := AU_KM * (1.00014 - 0.01671 * cos(M) - 0.00014 * cos(2.0 * M))

	var sun_rel_earth_km := Vector3(
		sun_dist_km * cos(sun_lon),
		sun_dist_km * sin(sun_lon),
		0.0
	)

	return {
		"earth": earth_rel_moon_km,
		"sun": earth_rel_moon_km + sun_rel_earth_km
	}
