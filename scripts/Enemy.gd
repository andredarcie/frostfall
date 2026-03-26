extends CharacterBody3D

signal defeated(enemy: Node3D)

const WARRIOR_MODEL_PATH := "res://assets/third_party/medieval-warrior/quaternius-clean/knight_character.fbx"

@export var move_speed := 3.5
@export var gravity := 24.0
@export var max_health := 3
@export var detection_range := 12.0
@export var attack_range := 1.6
@export var attack_damage := 12
@export var attack_cooldown := 1.1
@export var patrol_radius := 2.8

@onready var visuals: Node3D = $Visuals

var target: Node3D
var home_position := Vector3.ZERO
var health := max_health
var attack_timer := 0.0
var patrol_angle := 0.0
var warrior_instance: Node3D
var warrior_animation_player: AnimationPlayer


func _ready() -> void:
	health = max_health
	home_position = global_position
	add_to_group("enemies")
	_attach_warrior_model()


func _physics_process(delta: float) -> void:
	attack_timer = max(attack_timer - delta, 0.0)

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	var desired_velocity := _get_desired_velocity(delta)
	velocity.x = desired_velocity.x
	velocity.z = desired_velocity.z

	if desired_velocity.length_squared() > 0.05:
		look_at(global_position + Vector3(desired_velocity.x, 0.0, desired_velocity.z), Vector3.UP)

	move_and_slide()
	_update_warrior_animation(desired_velocity)


func apply_damage(amount: int) -> void:
	health -= amount
	scale = Vector3.ONE * 0.92

	if health <= 0:
		defeated.emit(self)
		queue_free()


func _get_desired_velocity(delta: float) -> Vector3:
	if is_instance_valid(target):
		var to_target := target.global_position - global_position
		var flat_offset := Vector3(to_target.x, 0.0, to_target.z)
		var distance := flat_offset.length()

		if distance <= detection_range:
			if distance <= attack_range:
				_try_attack()
				return Vector3.ZERO
			return flat_offset.normalized() * move_speed

	patrol_angle += delta * 0.8
	var patrol_target := home_position + Vector3(cos(patrol_angle), 0.0, sin(patrol_angle)) * patrol_radius
	var patrol_direction := patrol_target - global_position
	patrol_direction.y = 0.0
	if patrol_direction.length() < 0.2:
		return Vector3.ZERO
	return patrol_direction.normalized() * move_speed * 0.5


func _try_attack() -> void:
	if attack_timer > 0.0 or not is_instance_valid(target):
		return

	attack_timer = attack_cooldown
	if target.has_method("apply_damage"):
		target.apply_damage(attack_damage)


func _attach_warrior_model() -> void:
	var warrior_scene: PackedScene = load(WARRIOR_MODEL_PATH)
	if warrior_scene == null:
		return

	var generated: Node = warrior_scene.instantiate()
	if not (generated is Node3D):
		return

	for child: Node in visuals.get_children():
		if child is VisualInstance3D:
			child.visible = false

	warrior_instance = generated
	warrior_instance.position = Vector3(0.0, 1.0, 0.0)
	warrior_instance.rotation_degrees = Vector3(0.0, 180.0, 0.0)
	warrior_instance.scale = Vector3.ONE * 0.72
	visuals.add_child(warrior_instance)

	warrior_animation_player = warrior_instance.get_node_or_null("AnimationPlayer")
	if warrior_animation_player != null:
		warrior_animation_player.play("HumanArmature|Idle_swordRight")


func _update_warrior_animation(desired_velocity: Vector3) -> void:
	if warrior_animation_player == null:
		return

	var desired_animation := "HumanArmature|Idle_swordRight"
	if attack_timer > attack_cooldown - 0.15:
		desired_animation = "HumanArmature|Run_swordAttack"
	elif desired_velocity.length_squared() > 0.05:
		desired_animation = "HumanArmature|Walking"

	if warrior_animation_player.current_animation != desired_animation:
		warrior_animation_player.play(desired_animation)
