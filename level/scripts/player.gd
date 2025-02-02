extends CharacterBody3D
class_name Character

const NORMAL_SPEED = 6.0
const SPRINT_SPEED = 10.0
const JUMP_VELOCITY = 10

@onready var nickname: Label3D = $PlayerNick/Nickname
@onready var camera: Camera3D = get_node_or_null("Camera3D")

@onready var gun_raycast: RayCast3D = $Camera3D/gun/RayCast3D
@onready var gun_animation: AnimationPlayer = $Camera3D/gun/AnimationPlayer
var bullets_left = 40
var bullet = preload("res://bullet.tscn")

@export_category("Objects")
@export var _body: Node3D = null
@export var _spring_arm_offset: Node3D = null

@export_category("Skin Colors")
@export var blue_texture : CompressedTexture2D
@export var yellow_texture : CompressedTexture2D
@export var green_texture : CompressedTexture2D
@export var red_texture : CompressedTexture2D

var _current_speed: float
var _respawn_point = Vector3(0, 5, 0)
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var mouse_sensitivity = 0.002  
var health = 5

func _enter_tree():
	var id = multiplayer.get_unique_id()
	set_multiplayer_authority(id)

func _ready():
	if not is_multiplayer_authority():
		set_process(false)
		set_physics_process(false)
		if camera:
			camera.current = false
		return
	else:
		camera.current = true
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _input(event):
	if not is_multiplayer_authority():
		return
		
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * mouse_sensitivity)
		if camera:
			camera.rotate_x(event.relative.y * mouse_sensitivity)
			camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-75), deg_to_rad(75))

func _physics_process(delta):
	if not is_multiplayer_authority(): 
		return
	
	$Camera3D/Label.text = str(bullets_left) + " / 40"
	
	var current_scene = get_tree().get_current_scene()
	if current_scene and current_scene.has_method("is_chat_visible") and current_scene.is_chat_visible() and is_on_floor():
		freeze()
		return
	
	if health == 0:
		get_tree().quit()
	
	if not is_on_floor():
		velocity.y -= gravity * delta
		_body.animate(velocity)
		
	if is_on_floor():
		if Input.is_action_just_pressed("jump"):
			velocity.y = JUMP_VELOCITY
	else:
		velocity.y -= gravity * delta
	
	if Input.is_action_pressed("shoot") and bullets_left > 0:
		if !gun_animation.is_playing():
			gun_animation.play("shoot")
			shoot.rpc()

	if Input.is_action_just_pressed("reload"):
		gun_animation.play("reload")
		bullets_left = 40
	
	_move()
	move_and_slide()
	_body.animate(velocity)
	_check_fall_and_respawn()
	
func freeze():
	velocity.x = 0
	velocity.z = 0
	_current_speed = 0
	_body.animate(Vector3.ZERO)
	
func _move() -> void:
	if not is_multiplayer_authority():
		return  # تأكد أن اللاعب لا يتحرك إلا إذا كان هو صاحب التحكم

	var _input_direction: Vector2 = Input.get_vector("move_left", "move_right","move_forward", "move_backward")


	var _direction: Vector3 = global_transform.basis * Vector3(-_input_direction.x, 0, -_input_direction.y)
	_direction = _direction.normalized()

	is_running()

	if _direction:
		velocity.x = _direction.x * _current_speed
		velocity.z = _direction.z * _current_speed
		_body.apply_rotation(velocity)
	else:
		velocity.x = move_toward(velocity.x, 0, _current_speed)
		velocity.z = move_toward(velocity.z, 0, _current_speed)


func is_running() -> bool:
	if Input.is_action_pressed("shift"):
		_current_speed = SPRINT_SPEED
		return true
	else:
		_current_speed = NORMAL_SPEED
		return false
		
func _check_fall_and_respawn():
	if global_transform.origin.y < -15.0:
		_respawn()
		
func _respawn():
	global_transform.origin = _respawn_point
	velocity = Vector3.ZERO
	
@rpc("any_peer", "reliable")
func change_nick(new_nick: String):
	if nickname:
		nickname.text = new_nick
		
func get_texture_from_name(skin_name: String) -> CompressedTexture2D:
	match skin_name:
		"blue": return blue_texture
		"green": return green_texture
		"red": return red_texture
		"yellow": return yellow_texture
		_: return blue_texture
		
@rpc("any_peer", "reliable")
func set_player_skin(skin_name: String) -> void:
	var texture = get_texture_from_name(skin_name)
	var bottom: MeshInstance3D = get_node("3DGodotRobot/RobotArmature/Skeleton3D/Bottom")
	var chest: MeshInstance3D = get_node("3DGodotRobot/RobotArmature/Skeleton3D/Chest")
	var face: MeshInstance3D = get_node("3DGodotRobot/RobotArmature/Skeleton3D/Face")
	var limbs_head: MeshInstance3D = get_node("3DGodotRobot/RobotArmature/Skeleton3D/Llimbs and head")
	
	set_mesh_texture(bottom, texture)
	set_mesh_texture(chest, texture)
	set_mesh_texture(face, texture)
	set_mesh_texture(limbs_head, texture)
	
func set_mesh_texture(mesh_instance: MeshInstance3D, texture: CompressedTexture2D) -> void:
	if mesh_instance:
		var material := mesh_instance.get_surface_override_material(0)
		if material and material is StandardMaterial3D:
			var new_material := material
			new_material.albedo_texture = texture
			mesh_instance.set_surface_override_material(0, new_material)

func damage():
	health -= 1

@rpc("authority", "reliable")
func shoot():
	if bullets_left > 0:
		bullets_left -= 1
		var bullet_instance = bullet.instantiate()
		bullet_instance.position = gun_raycast.global_position
		bullet_instance.transform.basis = gun_raycast.global_transform.basis
		get_parent().add_child(bullet_instance)
