extends CharacterBody3D

signal health_changed(current: int, maximum: int)
signal stamina_changed(current: float, maximum: float)
signal magicka_changed(current: float, maximum: float)
signal died()

@export var move_speed := 6.5
@export var jump_velocity := 8.0
@export var gravity := 24.0
@export var max_health := 100
@export var mouse_sensitivity := 0.003
@export var attack_damage := 1
@export var attack_range := 2.1
@export var attack_arc_cos := 0.2
@export var attack_cooldown := 0.35
@export var attack_anim_duration := 0.24
@export var max_stamina := 100.0
@export var max_magicka := 100.0
@export var stamina_regen := 18.0
@export var stamina_regen_delay := 1.1
@export var jump_stamina_cost := 16.0
@export var attack_stamina_cost := 12.0

@onready var visuals: Node3D = $Visuals
@onready var pitch_pivot: Node3D = $CameraRig/PitchPivot
@onready var sword: Node3D = $CameraRig/PitchPivot/Camera3D/ViewModel/Sword

var health := max_health
var stamina := max_stamina
var magicka := max_magicka
var stamina_regen_cooldown := 0.0
var attack_timer := 0.0
var attack_anim_timer := 0.0
var sword_rest_position := Vector3.ZERO
var sword_rest_rotation := Vector3.ZERO
var sword_windup_position := Vector3.ZERO
var sword_swing_position := Vector3.ZERO
var sword_recover_position := Vector3.ZERO
var sword_windup_rotation := Vector3.ZERO
var sword_swing_rotation := Vector3.ZERO
var sword_recover_rotation := Vector3.ZERO


func _ready() -> void:
	sword_rest_position = sword.position
	sword_rest_rotation = sword.rotation
	sword_windup_position = sword_rest_position + Vector3(0.12, 0.1, -0.1)
	sword_swing_position = sword_rest_position + Vector3(-0.4, 0.18, 0.22)
	sword_recover_position = sword_rest_position + Vector3(-0.12, -0.04, 0.06)
	sword_windup_rotation = sword_rest_rotation + Vector3(0.24, 0.26, -0.26)
	sword_swing_rotation = sword_rest_rotation + Vector3(-0.22, -0.44, 0.28)
	sword_recover_rotation = sword_rest_rotation + Vector3(-0.08, -0.12, 0.1)

	health_changed.emit(health, max_health)
	stamina_changed.emit(stamina, max_stamina)
	magicka_changed.emit(magicka, max_magicka)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		pitch_pivot.rotate_x(-event.relative.y * mouse_sensitivity)
		pitch_pivot.rotation.x = clamp(pitch_pivot.rotation.x, -1.0, 0.3)

	if event.is_action_pressed("attack"):
		_try_attack()


func _physics_process(delta: float) -> void:
	attack_timer = max(attack_timer - delta, 0.0)
	attack_anim_timer = max(attack_anim_timer - delta, 0.0)
	stamina_regen_cooldown = max(stamina_regen_cooldown - delta, 0.0)
	if stamina_regen_cooldown <= 0.0 and stamina < max_stamina:
		stamina = min(stamina + stamina_regen * delta, max_stamina)
		stamina_changed.emit(stamina, max_stamina)

	var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var move_direction := (global_transform.basis * Vector3(input_vector.x, 0.0, input_vector.y)).normalized()

	if move_direction != Vector3.ZERO:
		velocity.x = move_direction.x * move_speed
		velocity.z = move_direction.z * move_speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, move_speed)
		velocity.z = move_toward(velocity.z, 0.0, move_speed)

	if not is_on_floor():
		velocity.y -= gravity * delta
	elif Input.is_action_just_pressed("jump") and stamina >= jump_stamina_cost:
		velocity.y = jump_velocity
		stamina = max(stamina - jump_stamina_cost, 0.0)
		stamina_regen_cooldown = stamina_regen_delay
		stamina_changed.emit(stamina, max_stamina)
	else:
		velocity.y = 0.0

	move_and_slide()
	_update_weapon_pose()


func apply_damage(amount: int) -> void:
	health = max(health - amount, 0)
	health_changed.emit(health, max_health)

	if health <= 0:
		died.emit()
		set_physics_process(false)
		set_process_input(false)


func _try_attack() -> void:
	if attack_timer > 0.0 or health <= 0 or stamina < attack_stamina_cost:
		return

	attack_timer = attack_cooldown
	attack_anim_timer = attack_anim_duration
	stamina = max(stamina - attack_stamina_cost, 0.0)
	stamina_regen_cooldown = stamina_regen_delay
	stamina_changed.emit(stamina, max_stamina)

	var forward := -global_transform.basis.z
	for node in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(node) or not (node is Node3D):
			continue

		var enemy: Node3D = node
		var to_enemy: Vector3 = enemy.global_position - global_position
		var flat_offset := Vector3(to_enemy.x, 0.0, to_enemy.z)
		if flat_offset.length() > attack_range:
			continue

		var direction := flat_offset.normalized()
		if forward.dot(direction) >= attack_arc_cos and enemy.has_method("apply_damage"):
			enemy.apply_damage(attack_damage)


func _update_weapon_pose() -> void:
	var target_rotation := sword_rest_rotation
	var target_position := sword_rest_position
	if attack_anim_timer > 0.0:
		var progress := 1.0 - (attack_anim_timer / attack_anim_duration)
		if progress < 0.22:
			var windup_t := _ease_out_cubic(progress / 0.22)
			target_rotation = sword_rest_rotation.lerp(sword_windup_rotation, windup_t)
			target_position = sword_rest_position.lerp(sword_windup_position, windup_t)
		elif progress < 0.62:
			var swing_t := _ease_in_cubic((progress - 0.22) / 0.4)
			target_rotation = sword_windup_rotation.lerp(sword_swing_rotation, swing_t)
			target_position = sword_windup_position.lerp(sword_swing_position, swing_t)
		else:
			var recover_t := _ease_out_quad((progress - 0.62) / 0.38)
			target_rotation = sword_swing_rotation.lerp(sword_recover_rotation, recover_t)
			target_position = sword_swing_position.lerp(sword_recover_position, recover_t)
			var settle_t := recover_t * recover_t
			target_rotation = target_rotation.lerp(sword_rest_rotation, settle_t)
			target_position = target_position.lerp(sword_rest_position, settle_t)

	sword.rotation = target_rotation
	sword.position = target_position


func _ease_in_cubic(value: float) -> float:
	return value * value * value


func _ease_out_cubic(value: float) -> float:
	var inv := 1.0 - value
	return 1.0 - inv * inv * inv


func _ease_out_quad(value: float) -> float:
	return 1.0 - (1.0 - value) * (1.0 - value)
