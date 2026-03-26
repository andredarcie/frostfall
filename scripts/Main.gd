extends Node3D

const TERRAIN_CENTER := Vector3(0.0, 0.0, -2.0)
const TERRAIN_HALF_SIZE := Vector2(88.0, 108.0)
const TERRAIN_SUBDIVISIONS_X := 168
const TERRAIN_SUBDIVISIONS_Z := 212
const REALISTIC_TREE_PATH := "res://assets/third_party/vegetation/pixabay/real_tree.glb"
const REALISTIC_BUSH_PATH := "res://assets/third_party/vegetation/pixabay/real_bush.glb"

@onready var world: Node3D = $World
@onready var player: Variant = $Player
@onready var enemies_root: Node3D = $Enemies
@onready var artifact_area: Area3D = $ArtifactArea
@onready var artifact_mesh: MeshInstance3D = $ArtifactArea/ArtifactMesh
@onready var compass_label: Label = $HUD/CompassPanel/CompassLabel
@onready var compass_markers: Control = $HUD/CompassPanel/CompassMarkers
@onready var quest_label: Label = $HUD/QuestLabel
@onready var status_label: Label = $HUD/StatusLabel
@onready var health_fill: ColorRect = $HUD/BottomHud/HealthFrame/HealthFill
@onready var health_label: Label = $HUD/BottomHud/HealthFrame/HealthLabel
@onready var magicka_fill: ColorRect = $HUD/BottomHud/MagickaFrame/MagickaFill
@onready var magicka_label: Label = $HUD/BottomHud/MagickaFrame/MagickaLabel
@onready var stamina_fill: ColorRect = $HUD/BottomHud/StaminaFrame/StaminaFill
@onready var stamina_label: Label = $HUD/BottomHud/StaminaFrame/StaminaLabel

var total_enemies := 0
var enemies_defeated := 0
var game_finished := false
var scene_time := 0.0
var asset_cache: Dictionary = {}
var vegetation_wind_shader: Shader


func _ready() -> void:
	_configure_input_map()
	_build_world()
	_snap_scene_nodes_to_terrain()

	total_enemies = enemies_root.get_child_count()
	for enemy in enemies_root.get_children():
		var enemy_ref: Variant = enemy
		enemy_ref.target = player
		enemy_ref.defeated.connect(_on_enemy_defeated)

	player.health_changed.connect(_on_player_health_changed)
	player.stamina_changed.connect(_on_player_stamina_changed)
	player.magicka_changed.connect(_on_player_magicka_changed)
	player.died.connect(_on_player_died)
	artifact_area.body_entered.connect(_on_artifact_area_body_entered)

	_on_player_health_changed(player.health, player.max_health)
	_on_player_stamina_changed(player.stamina, player.max_stamina)
	_on_player_magicka_changed(player.magicka, player.max_magicka)
	_update_objective_text()
	status_label.text = "Explore o vale gelado, derrote os guardioes e tome o fragmento."


func _process(delta: float) -> void:
	scene_time += delta
	_update_compass()
	_animate_artifact()


func _configure_input_map() -> void:
	_ensure_key_action("move_forward", 87)
	_ensure_key_action("move_back", 83)
	_ensure_key_action("move_left", 65)
	_ensure_key_action("move_right", 68)
	_ensure_key_action("jump", 32)
	_ensure_key_action("interact", 69)
	_ensure_mouse_action("attack", 1)


func _ensure_key_action(action: StringName, keycode: int) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)

	for event in InputMap.action_get_events(action):
		if event is InputEventKey and event.physical_keycode == keycode:
			return

	var input_event := InputEventKey.new()
	input_event.physical_keycode = keycode
	InputMap.action_add_event(action, input_event)


func _ensure_mouse_action(action: StringName, button_index: int) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)

	for event in InputMap.action_get_events(action):
		if event is InputEventMouseButton and event.button_index == button_index:
			return

	var input_event := InputEventMouseButton.new()
	input_event.button_index = button_index
	InputMap.action_add_event(action, input_event)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED

	if game_finished and event.is_action_pressed("ui_accept"):
		get_tree().reload_current_scene()


func _build_world() -> void:
	var grass_material: Material = _make_terrain_material()

	_create_terrain(grass_material)
	_spawn_dense_forest()
	_spawn_mist_layers()
	_spawn_snowfall()

	artifact_area.position = Vector3(0.0, 0.0, -72.0)


func _create_box_obstacle(name: String, position: Vector3, size: Vector3, material: Material) -> void:
	var body := StaticBody3D.new()
	body.name = name
	body.position = Vector3(position.x, _sample_terrain_height(position.x, position.z) + position.y, position.z)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)

	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	body.add_child(mesh_instance)

	world.add_child(body)


func _create_terrain(material: Material) -> void:
	var terrain_body := StaticBody3D.new()
	terrain_body.name = "Terrain"

	var mesh_instance := MeshInstance3D.new()
	var terrain_mesh := _build_terrain_mesh()
	mesh_instance.mesh = terrain_mesh
	mesh_instance.material_override = material
	terrain_body.add_child(mesh_instance)

	var collision := CollisionShape3D.new()
	collision.shape = terrain_mesh.create_trimesh_shape()
	terrain_body.add_child(collision)

	world.add_child(terrain_body)


func _build_terrain_mesh() -> ArrayMesh:
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	var step_x := (TERRAIN_HALF_SIZE.x * 2.0) / float(TERRAIN_SUBDIVISIONS_X)
	var step_z := (TERRAIN_HALF_SIZE.y * 2.0) / float(TERRAIN_SUBDIVISIONS_Z)

	for x_index in range(TERRAIN_SUBDIVISIONS_X):
		for z_index in range(TERRAIN_SUBDIVISIONS_Z):
			var x0 := TERRAIN_CENTER.x - TERRAIN_HALF_SIZE.x + float(x_index) * step_x
			var x1 := x0 + step_x
			var z0 := TERRAIN_CENTER.z - TERRAIN_HALF_SIZE.y + float(z_index) * step_z
			var z1 := z0 + step_z

			var v00 := Vector3(x0, _sample_terrain_height(x0, z0), z0)
			var v10 := Vector3(x1, _sample_terrain_height(x1, z0), z0)
			var v01 := Vector3(x0, _sample_terrain_height(x0, z1), z1)
			var v11 := Vector3(x1, _sample_terrain_height(x1, z1), z1)

			surface_tool.add_vertex(v00)
			surface_tool.add_vertex(v10)
			surface_tool.add_vertex(v11)

			surface_tool.add_vertex(v00)
			surface_tool.add_vertex(v11)
			surface_tool.add_vertex(v01)

	surface_tool.generate_normals()
	return surface_tool.commit()


func _sample_terrain_height(x: float, z: float) -> float:
	var local_x: float = x - TERRAIN_CENTER.x
	var local_z: float = z - TERRAIN_CENTER.z

	var broad_hills: float = sin(local_x * 0.082) * 1.9 + cos(local_z * 0.071) * 1.55
	var ridge: float = sin((local_x + local_z) * 0.046) * 1.35 + cos((local_x - local_z) * 0.034) * 1.15
	var detail: float = sin(local_x * 0.23) * 0.24 + cos(local_z * 0.19) * 0.22
	var raw_height: float = (broad_hills + ridge) * 0.95 + detail

	var center_distance: float = Vector2(local_x * 0.9, local_z).length()
	var outer_relief: float = _smoothstep(8.0, 84.0, center_distance)
	var height: float = raw_height * outer_relief

	var path_blend: float = 1.0 - _smoothstep(1.8, 7.8, abs(local_x))
	var path_length_blend: float = 1.0 - _smoothstep(48.0, 90.0, abs(local_z))
	height *= 1.0 - (path_blend * path_length_blend * 0.55)

	var altar_mound: float = max(0.0, 1.0 - Vector2(local_x * 0.08, local_z + 72.0).length() / 14.0) * 1.9
	height += altar_mound

	var near_hill_left: float = max(0.0, 1.0 - Vector2((local_x + 34.0) * 0.13, (local_z - 18.0) * 0.12).length() / 5.8) * 3.4
	var near_hill_right: float = max(0.0, 1.0 - Vector2((local_x - 38.0) * 0.13, (local_z - 14.0) * 0.12).length() / 5.8) * 3.0
	var mid_ridge_left: float = max(0.0, 1.0 - Vector2((local_x + 42.0) * 0.1, (local_z + 26.0) * 0.08).length() / 6.8) * 3.0
	var mid_ridge_right: float = max(0.0, 1.0 - Vector2((local_x - 40.0) * 0.1, (local_z + 22.0) * 0.08).length() / 6.6) * 2.8
	var far_ridge: float = max(0.0, 1.0 - Vector2(local_x * 0.045, (local_z + 74.0) * 0.07).length() / 8.2) * 3.6
	height += near_hill_left + near_hill_right + mid_ridge_left + mid_ridge_right + far_ridge

	var edge_x: float = _smoothstep(58.0, 84.0, abs(local_x))
	var edge_z: float = _smoothstep(68.0, 104.0, abs(local_z))
	var mountain_mask: float = max(edge_x, edge_z)
	var mountain_noise: float = sin(local_x * 0.06) * 5.4 + cos(local_z * 0.05) * 4.2 + sin((local_x - local_z) * 0.025) * 3.2
	var mountain_ridges: float = abs(sin(local_x * 0.11 + local_z * 0.03)) * 4.5 + abs(cos(local_z * 0.09 - local_x * 0.02)) * 3.6
	var mountain_height: float = 28.0 + mountain_noise + mountain_ridges
	height += max(0.0, mountain_height) * mountain_mask

	var corner_mask: float = _smoothstep(78.0, 128.0, Vector2(abs(local_x), abs(local_z)).length())
	height += corner_mask * 18.0

	return height


func _smoothstep(edge0: float, edge1: float, value: float) -> float:
	var t: float = clamp((value - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _spawn_external_asset(asset_path: String, position: Vector3, rotation_degrees: Vector3 = Vector3.ZERO, scale_value: Vector3 = Vector3.ONE) -> Node3D:
	var scene: PackedScene = _load_external_scene(asset_path)
	if scene == null:
		return Node3D.new()

	var instance: Node = scene.instantiate()
	if instance is Node3D:
		instance.position = Vector3(position.x, _sample_terrain_height(position.x, position.z) + position.y, position.z)
		instance.rotation_degrees = rotation_degrees
		instance.scale = scale_value
		_apply_vegetation_wind(instance, asset_path)

	world.add_child(instance)
	return instance


func _load_external_scene(asset_path: String) -> PackedScene:
	if asset_cache.has(asset_path):
		return asset_cache[asset_path] as PackedScene

	var scene: PackedScene = load(asset_path) as PackedScene
	asset_cache[asset_path] = scene
	return scene


func _spawn_dense_forest() -> void:
	for x in range(-78, 79, 7):
		for z in range(-96, 73, 7):
			var x_float: float = float(x)
			var z_float: float = float(z)
			var path_clearance: bool = abs(x_float) < 16.0 and z_float > -86.0 and z_float < 64.0
			var spawn_clearance: bool = abs(x_float) < 28.0 and z_float > 14.0 and z_float < 62.0
			var altar_clearance: bool = abs(x_float) < 12.0 and z_float > -84.0 and z_float < -52.0
			if path_clearance or spawn_clearance or altar_clearance:
				continue

			var density_noise: float = sin(x_float * 0.31 + z_float * 0.17) + cos(z_float * 0.27 - x_float * 0.19)
			if density_noise < 0.18 and abs(x_float) < 66.0:
				continue

			var x_offset: float = sin(x_float * 1.73 + z_float * 0.63) * 0.95
			var z_offset: float = cos(z_float * 1.41 - x_float * 0.52) * 0.95
			var pos := Vector3(x_float + x_offset, 0.0, z_float + z_offset)
			var selector: int = abs(int(x_float * 17.0 + z_float * 13.0)) % 12
			var rotation_y: float = wrapf(x_float * 11.0 + z_float * 7.0 + density_noise * 35.0, 0.0, 360.0)

			if selector <= 5:
				var tree_scale: float = 2.7 + float(selector) * 0.22 + max(density_noise, 0.0) * 0.28
				_spawn_external_asset(REALISTIC_TREE_PATH, pos, Vector3(0.0, rotation_y, 0.0), Vector3.ONE * tree_scale)
			elif selector <= 8:
				var bush_scale: float = 0.18 + float(selector - 5) * 0.04
				_spawn_external_asset(REALISTIC_BUSH_PATH, pos, Vector3(0.0, rotation_y, 0.0), Vector3.ONE * bush_scale)

	for patch_x in range(-70, 71, 18):
		for patch_z in range(-86, 64, 18):
			var patch_center := Vector3(float(patch_x) + sin(float(patch_z) * 0.7) * 1.2, 0.0, float(patch_z) + cos(float(patch_x) * 0.5) * 1.2)
			if abs(patch_center.x) < 12.0 and patch_center.z > -22.0 and patch_center.z < 16.0:
				continue
			for shrub_index in range(2):
				var angle: float = float(shrub_index) * 2.09 + sin(patch_center.x * 0.2 + float(shrub_index))
				var radius: float = 0.9 + float(shrub_index) * 0.55
				var shrub_pos := patch_center + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
				var shrub_scale: float = 0.24 + float(shrub_index) * 0.05
				_spawn_external_asset(REALISTIC_BUSH_PATH, shrub_pos, Vector3(0.0, angle * 60.0, 0.0), Vector3.ONE * shrub_scale)

	for flank_tree in [
		Vector3(-22.0, 0.0, 16.0),
		Vector3(-18.0, 0.0, 12.0),
		Vector3(21.0, 0.0, 15.0),
		Vector3(18.0, 0.0, 10.0),
		Vector3(-20.0, 0.0, -23.0),
		Vector3(22.0, 0.0, -22.0)
	]:
		_spawn_external_asset(REALISTIC_TREE_PATH, flank_tree, Vector3(0.0, float(int(flank_tree.x * 7.0 + flank_tree.z * 5.0) % 360), 0.0), Vector3.ONE * 4.1)

	for mid_shrub in [
		Vector3(-8.0, 0.0, 6.0),
		Vector3(7.0, 0.0, 7.0),
		Vector3(-5.0, 0.0, -4.0),
		Vector3(6.0, 0.0, -6.0)
	]:
		_spawn_external_asset(REALISTIC_BUSH_PATH, mid_shrub, Vector3(0.0, float(int(mid_shrub.x * 13.0) % 360), 0.0), Vector3.ONE * 0.26)


func _spawn_mist_layers() -> void:
	var mist_material: ShaderMaterial = _make_mist_material()
	for mist_data in [
		{"position": Vector3(0.0, 5.0, -20.0), "size": Vector2(180.0, 28.0), "alpha": 0.72},
		{"position": Vector3(0.0, 8.0, -40.0), "size": Vector2(230.0, 34.0), "alpha": 0.82},
		{"position": Vector3(-52.0, 8.0, -20.0), "size": Vector2(128.0, 28.0), "alpha": 0.62},
		{"position": Vector3(52.0, 8.2, -20.0), "size": Vector2(128.0, 28.0), "alpha": 0.62},
		{"position": Vector3(0.0, 13.0, -70.0), "size": Vector2(320.0, 52.0), "alpha": 0.95},
		{"position": Vector3(0.0, 18.0, -106.0), "size": Vector2(380.0, 62.0), "alpha": 1.0},
		{"position": Vector3(0.0, 24.0, -146.0), "size": Vector2(430.0, 72.0), "alpha": 1.0},
		{"position": Vector3(0.0, 31.0, -186.0), "size": Vector2(480.0, 84.0), "alpha": 1.0}
	]:
		var mist_plane := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = mist_data["size"]
		mist_plane.mesh = plane
		mist_plane.position = mist_data["position"]
		mist_plane.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		mist_plane.material_override = mist_material.duplicate()
		var material_ref: ShaderMaterial = mist_plane.material_override
		material_ref.set_shader_parameter("alpha_strength", mist_data["alpha"])
		world.add_child(mist_plane)


func _spawn_snowfall() -> void:
	_spawn_snow_layer(
		"SnowNear",
		Vector3(0.0, 18.0, 10.0),
		3800,
		8.0,
		Vector3(32.0, 6.0, 34.0),
		Vector2(0.12, 0.16),
		Vector3(0.24, -1.0, 0.1),
		26.0,
		Vector2(3.2, 5.2),
		Vector3(0.28, -1.9, 0.18),
		Vector2(0.7, 1.05),
		0.96
	)
	_spawn_snow_layer(
		"SnowMid",
		Vector3(0.0, 28.0, -8.0),
		6200,
		10.0,
		Vector3(78.0, 4.0, 92.0),
		Vector2(0.08, 0.11),
		Vector3(0.2, -1.0, 0.08),
		18.0,
		Vector2(2.4, 4.1),
		Vector3(0.2, -1.55, 0.12),
		Vector2(0.46, 0.78),
		0.88
	)
	_spawn_snow_layer(
		"SnowFar",
		Vector3(0.0, 40.0, -54.0),
		7600,
		12.0,
		Vector3(128.0, 8.0, 150.0),
		Vector2(0.045, 0.07),
		Vector3(0.14, -1.0, 0.05),
		12.0,
		Vector2(1.6, 3.0),
		Vector3(0.12, -1.2, 0.07),
		Vector2(0.24, 0.42),
		0.68
	)
	_spawn_snow_layer(
		"SnowGust",
		Vector3(0.0, 3.4, -6.0),
		3400,
		6.5,
		Vector3(94.0, 1.2, 108.0),
		Vector2(0.06, 0.12),
		Vector3(0.95, -0.12, 0.22),
		10.0,
		Vector2(5.8, 8.8),
		Vector3(0.65, -0.12, 0.18),
		Vector2(0.5, 0.9),
		0.46
	)


func _spawn_snow_layer(
	layer_name: String,
	position: Vector3,
	amount: int,
	lifetime: float,
	emission_extents: Vector3,
	quad_size: Vector2,
	direction: Vector3,
	spread: float,
	velocity_range: Vector2,
	gravity: Vector3,
	scale_range: Vector2,
	alpha: float
) -> void:
	var snow := GPUParticles3D.new()
	snow.name = layer_name
	snow.position = position
	snow.amount = amount
	snow.lifetime = lifetime
	snow.preprocess = lifetime
	snow.visibility_aabb = AABB(Vector3(-emission_extents.x * 1.4, -40.0, -emission_extents.z * 1.4), Vector3(emission_extents.x * 2.8, 90.0, emission_extents.z * 2.8))
	snow.draw_pass_1 = QuadMesh.new()
	var quad := snow.draw_pass_1 as QuadMesh
	quad.size = quad_size

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = emission_extents
	process.direction = direction
	process.spread = spread
	process.initial_velocity_min = velocity_range.x
	process.initial_velocity_max = velocity_range.y
	process.gravity = gravity
	process.scale_min = scale_range.x
	process.scale_max = scale_range.y
	process.angular_velocity_min = -0.6
	process.angular_velocity_max = 0.6
	process.damping_min = 0.02
	process.damping_max = 0.18
	process.color = Color(0.97, 0.99, 1.0, alpha)
	process.hue_variation_min = -0.01
	process.hue_variation_max = 0.01
	snow.process_material = process

	var snow_material := StandardMaterial3D.new()
	snow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	snow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	snow_material.albedo_color = Color(0.97, 0.99, 1.0, alpha)
	snow_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	snow_material.no_depth_test = true
	snow_material.disable_receive_shadows = true
	quad.material = snow_material

	world.add_child(snow)




func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	return material


func _make_terrain_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 grass_low : source_color = vec4(0.63, 0.67, 0.7, 1.0);
uniform vec4 grass_high : source_color = vec4(0.84, 0.87, 0.9, 1.0);
uniform vec4 dirt_color : source_color = vec4(0.46, 0.48, 0.5, 1.0);
uniform vec4 rock_color : source_color = vec4(0.28, 0.31, 0.34, 1.0);
uniform float roughness_value : hint_range(0.0, 1.0) = 0.96;
uniform float metallic_value : hint_range(0.0, 1.0) = 0.0;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_NORMAL_MATRIX * NORMAL));
}

void fragment() {
	float height_mask = clamp((world_pos.y + 1.5) / 14.0, 0.0, 1.0);
	float slope_mask = 1.0 - clamp(world_normal.y, 0.0, 1.0);
	float broad_noise = sin(world_pos.x * 0.12) * 0.5 + cos(world_pos.z * 0.1) * 0.5;
	float fine_noise = sin(world_pos.x * 0.75 + world_pos.z * 0.4) * 0.5 + cos(world_pos.z * 0.66 - world_pos.x * 0.31) * 0.5;
	float ridge_noise = abs(sin(world_pos.x * 0.18 + world_pos.z * 0.04)) * 0.5 + abs(cos(world_pos.z * 0.16 - world_pos.x * 0.03)) * 0.5;
	float blend_noise = broad_noise * 0.18 + fine_noise * 0.08;

	float snow_mask = clamp(height_mask * 0.85 + (1.0 - slope_mask) * 0.42 + blend_noise * 0.35, 0.0, 1.0);
	vec3 snow_color = mix(grass_low.rgb, grass_high.rgb, snow_mask);
	float rock_mask = clamp(slope_mask * 1.18 + height_mask * 0.24 + ridge_noise * 0.38 - 0.16, 0.0, 1.0);
	vec3 stone_mix = mix(dirt_color.rgb, rock_color.rgb, rock_mask);
	vec3 ridge_highlight = mix(stone_mix, vec3(0.56, 0.6, 0.64), clamp(ridge_noise * slope_mask * 0.38, 0.0, 1.0));
	vec3 final_color = mix(ridge_highlight, snow_color, clamp(0.4 + snow_mask - slope_mask * 0.52 - ridge_noise * 0.12, 0.0, 1.0));

	ALBEDO = final_color;
	ROUGHNESS = roughness_value;
	METALLIC = metallic_value;
	SPECULAR = 0.18;
}
"""

	var material := ShaderMaterial.new()
	material.shader = shader
	return material


func _apply_vegetation_wind(root_node: Node, asset_path: String) -> void:
	var sway_strength: float = 0.07 if asset_path == REALISTIC_TREE_PATH else 0.04
	var sway_speed: float = 0.95 if asset_path == REALISTIC_TREE_PATH else 1.25
	var bend_start: float = 0.24 if asset_path == REALISTIC_TREE_PATH else 0.1

	for child: Node in _collect_mesh_instances(root_node):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue

		for surface_index in range(mesh_instance.mesh.get_surface_count()):
			var source_material: Material = mesh_instance.get_active_material(surface_index)
			if source_material == null:
				source_material = mesh_instance.mesh.surface_get_material(surface_index)
			mesh_instance.set_surface_override_material(surface_index, _make_wind_material(source_material, sway_strength, sway_speed, bend_start))


func _collect_mesh_instances(root_node: Node) -> Array[Node]:
	var results: Array[Node] = []
	if root_node is MeshInstance3D:
		results.append(root_node)
	for child: Node in root_node.get_children():
		results.append_array(_collect_mesh_instances(child))
	return results


func _make_wind_material(source_material: Material, sway_strength: float, sway_speed: float, bend_start: float) -> ShaderMaterial:
	if vegetation_wind_shader == null:
		vegetation_wind_shader = Shader.new()
		vegetation_wind_shader.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform float alpha_scissor : hint_range(0.0, 1.0) = 0.3;
uniform float roughness_value : hint_range(0.0, 1.0) = 1.0;
uniform float specular_value : hint_range(0.0, 1.0) = 0.15;
uniform float sway_strength : hint_range(0.0, 0.3) = 0.06;
uniform float sway_speed : hint_range(0.0, 4.0) = 1.0;
uniform float bend_start : hint_range(-1.0, 2.0) = 0.2;

varying vec3 world_pos;

void vertex() {
	float mask = clamp((VERTEX.y - bend_start) * 0.55, 0.0, 1.0);
	float gust = sin(TIME * sway_speed + (NODE_POSITION_WORLD.x * 0.22) + (NODE_POSITION_WORLD.z * 0.17));
	float flutter = cos(TIME * (sway_speed * 1.7) + VERTEX.y * 1.6 + NODE_POSITION_WORLD.x * 0.12);
	VERTEX.x += (gust * 0.14 + flutter * 0.05) * sway_strength * mask;
	VERTEX.z += (gust * 0.08 + flutter * 0.04) * sway_strength * mask;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 tex = texture(albedo_texture, UV) * albedo_tint;
	ALBEDO = tex.rgb;
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor;
	ROUGHNESS = roughness_value;
	SPECULAR = specular_value;
}
"""

	var shader_material := ShaderMaterial.new()
	shader_material.shader = vegetation_wind_shader
	shader_material.set_shader_parameter("sway_strength", sway_strength)
	shader_material.set_shader_parameter("sway_speed", sway_speed)
	shader_material.set_shader_parameter("bend_start", bend_start)

	if source_material is BaseMaterial3D:
		var base_material := source_material as BaseMaterial3D
		shader_material.set_shader_parameter("albedo_tint", base_material.albedo_color)
		shader_material.set_shader_parameter("roughness_value", base_material.roughness)
		shader_material.set_shader_parameter("specular_value", base_material.metallic_specular)
		if base_material.albedo_texture != null:
			shader_material.set_shader_parameter("albedo_texture", base_material.albedo_texture)
		if base_material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			shader_material.set_shader_parameter("alpha_scissor", 0.15)

	return shader_material


func _make_mist_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform vec4 mist_color : source_color = vec4(0.86, 0.91, 0.94, 1.0);
uniform float alpha_strength : hint_range(0.0, 1.0) = 0.28;
uniform float drift_speed = 0.03;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = UV;
	float edge_fade = smoothstep(0.0, 0.14, uv.x) * (1.0 - smoothstep(0.86, 1.0, uv.x));
	float height_fade = smoothstep(0.0, 0.18, uv.y) * (1.0 - smoothstep(0.72, 1.0, uv.y));
	float noise_a = sin((world_pos.x + TIME * 16.0 * drift_speed) * 0.085) * 0.5 + 0.5;
	float noise_b = cos((world_pos.z - TIME * 22.0 * drift_speed) * 0.11 + uv.x * 5.0) * 0.5 + 0.5;
	float noise_c = sin((world_pos.x + world_pos.z) * 0.045 - TIME * 8.0 * drift_speed) * 0.5 + 0.5;
	float fog_mask = edge_fade * height_fade * mix(0.62, 1.0, noise_a * 0.45 + noise_b * 0.35 + noise_c * 0.2);

	ALBEDO = mist_color.rgb;
	ALPHA = fog_mask * alpha_strength;
}
"""

	var material := ShaderMaterial.new()
	material.shader = shader
	return material


func _snap_scene_nodes_to_terrain() -> void:
	player.position.y = _sample_terrain_height(player.position.x, player.position.z) + 0.25

	for enemy in enemies_root.get_children():
		if enemy is Node3D:
			enemy.position.y = _sample_terrain_height(enemy.position.x, enemy.position.z) + 0.05

	artifact_area.position.y = _sample_terrain_height(artifact_area.position.x, artifact_area.position.z)


func _on_player_health_changed(current: int, maximum: int) -> void:
	_update_bar(health_fill, float(current) / float(maximum), 278.0)
	health_label.text = ""


func _on_player_stamina_changed(current: float, maximum: float) -> void:
	_update_bar(stamina_fill, current / maximum, 278.0)
	stamina_label.text = ""


func _on_player_magicka_changed(current: float, maximum: float) -> void:
	_update_bar(magicka_fill, current / maximum, 278.0)
	magicka_label.text = ""


func _on_enemy_defeated(_enemy: Node3D) -> void:
	enemies_defeated += 1
	_update_objective_text()
	if enemies_defeated < total_enemies:
		status_label.text = "Guardiao derrotado. Restam %d." % [total_enemies - enemies_defeated]
	else:
		status_label.text = "O santuario foi destrancado. Va ate o fragmento dourado."


func _on_artifact_area_body_entered(body: Node3D) -> void:
	if body != player or game_finished:
		return

	if enemies_defeated < total_enemies:
		status_label.text = "Uma runa fria bloqueia o altar. Derrote todos os guardioes."
		return

	game_finished = true
	quest_label.text = "Reino salvo por enquanto."
	status_label.text = "Voce tomou o Fragmento da Coroa. Pressione Enter para jogar novamente."
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_player_died() -> void:
	game_finished = true
	quest_label.text = "Voce caiu nas neves."
	status_label.text = "Os guardioes venceram. Pressione Enter para tentar novamente."
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _update_objective_text() -> void:
	quest_label.text = "Derrote %d/%d guardioes e recupere o fragmento." % [enemies_defeated, total_enemies]


func _update_bar(bar: ColorRect, ratio: float, max_width: float) -> void:
	ratio = clamp(ratio, 0.0, 1.0)
	bar.size.x = max_width * ratio


func _update_compass() -> void:
	var yaw: float = wrapf(rad_to_deg(player.rotation.y), 0.0, 360.0)
	var facing: String = _get_facing_label(yaw)
	compass_label.text = facing
	_update_enemy_compass_markers()


func _update_enemy_compass_markers() -> void:
	for child: Node in compass_markers.get_children():
		child.queue_free()

	var player_forward := Vector2(-player.global_transform.basis.z.x, -player.global_transform.basis.z.z).normalized()
	var player_right := Vector2(player.global_transform.basis.x.x, player.global_transform.basis.x.z).normalized()
	var marker_width := compass_markers.size.x
	var marker_center_y := 8.0

	for enemy in enemies_root.get_children():
		if not is_instance_valid(enemy):
			continue

		var to_enemy3: Vector3 = enemy.global_position - player.global_position
		var to_enemy: Vector2 = Vector2(to_enemy3.x, to_enemy3.z)
		if to_enemy.length() < 0.1:
			continue

		var direction: Vector2 = to_enemy.normalized()
		var side: float = player_right.dot(direction)
		var forward_amount: float = player_forward.dot(direction)
		var angle: float = atan2(side, forward_amount)
		var normalized_angle: float = clamp(angle / deg_to_rad(90.0), -1.0, 1.0)
		var x_pos: float = marker_width * 0.5 + normalized_angle * (marker_width * 0.46)

		var marker := ColorRect.new()
		marker.color = Color(0.82, 0.2, 0.2, 0.95)
		marker.custom_minimum_size = Vector2(6.0, 6.0)
		marker.position = Vector2(x_pos - 3.0, marker_center_y)
		compass_markers.add_child(marker)


func _animate_artifact() -> void:
	artifact_mesh.position.y = 1.35 + sin(scene_time * 1.8) * 0.22
	artifact_mesh.rotate_y(0.01)


func _get_facing_label(yaw: float) -> String:
	if yaw >= 337.5 or yaw < 22.5:
		return "N"
	if yaw < 67.5:
		return "NE"
	if yaw < 112.5:
		return "E"
	if yaw < 157.5:
		return "SE"
	if yaw < 202.5:
		return "S"
	if yaw < 247.5:
		return "SW"
	if yaw < 292.5:
		return "W"
	return "NW"
