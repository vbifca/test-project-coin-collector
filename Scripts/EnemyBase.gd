extends CharacterBody2D
class_name EnemyBase

# Путь до узла "мира" (в котором реализована функция поиска пути)
@export var world_path: NodePath
# Путь до цели (например, игрока)
@export var target_path: NodePath

# Скорость передвижения врага
@export var speed: float = 140.0

# Узел со спрайтом для проигрывания анимаций
@export var sprite_path: NodePath
@onready var sprite: AnimatedSprite2D = get_node(sprite_path) as AnimatedSprite2D

# --- Настройки поведения врага ---
@export_group("Tuning")
@export_range(2.0, 32.0, 0.5) var waypoint_reach_dist: float = 8.0        # радиус достижения точки пути
@export_range(0.05, 2.0, 0.05) var stuck_check_period: float = 0.25       # период проверки застревания
@export_range(0.1, 3.0, 0.1) var stuck_timeout: float = 0.8               # через сколько секунд считать застрявшим
@export_range(0.0, 50.0, 0.5) var stuck_speed_threshold: float = 5.0      # скорость ниже которой считается "застрял"
@export var allow_diagonals: bool = true                                  # можно ли ходить по диагонали

# --- Внутренние переменные ---
var _stuck_timer := 0.0
var _stuck_sample_timer := 0.0
var _last_pos: Vector2

var _target: Node2D
var _world: Node

# Путь, по которому движется враг
var path: PackedVector2Array = []
var path_index: int = 0
var moving: bool = false

# Установить новый путь
func set_path(new_path: PackedVector2Array) -> void:
	if new_path.is_empty():
		moving = false
		return
	path = new_path
	path_index = 0
	moving = true

# --- Выбор анимации бега в зависимости от направления движения ---
func _pick_run_anim(dir: Vector2) -> void:
	if dir.length() < 0.001:
		return
	dir = dir.normalized()
	var x := dir.x
	var y := dir.y
	var name := ""

	# Проверяем направление и выбираем анимацию
	if y < -0.382 and x < -0.382:
		name = "up_left"
	elif y < -0.382 and x > 0.382:
		name = "up_right"
	elif y > 0.382 and x < -0.382:
		name = "down_left"
	elif y > 0.382 and x > 0.382:
		name = "down_right"
	elif y < -0.5:
		name = "up"
	elif y > 0.5:
		name = "down"
	elif x < -0.0:
		name = "left"
	else:
		name = "right"

	# Если анимации нет — fallback
	if not sprite.sprite_frames.has_animation(name):
		name = "run_right"

	# Если уже играет нужная анимация — ничего не делаем
	if sprite.animation != name:
		sprite.play(name)

# Анимация ожидания
func _play_idle() -> void:
	if sprite.sprite_frames.has_animation("idle"):
		sprite.play("idle")
	else:
		sprite.stop()

# --- Движение вдоль пути ---
func _move_along_path(delta: float) -> void:
	if not moving:
		velocity = Vector2.ZERO
		_play_idle()
		return

	# Пропускаем точки, если они уже достигнуты
	while path_index < path.size() and global_position.distance_to(path[path_index]) <= waypoint_reach_dist:
		path_index += 1

	# Если достигли конца пути — останавливаемся
	if path_index >= path.size():
		moving = false
		velocity = Vector2.ZERO
		_play_idle()
		return

	var target_point: Vector2 = path[path_index]
	var to_target := target_point - global_position
	var dist_to_target := to_target.length()

	if dist_to_target > 0.0:
		var dir := to_target / dist_to_target
		velocity = dir * speed
		_pick_run_anim(velocity)
		move_and_slide()

		# Проверяем, проскочили ли точку
		var after_to_target := target_point - global_position
		if to_target.dot(after_to_target) <= 0.0 or after_to_target.length() <= waypoint_reach_dist:
			path_index += 1
	else:
		# Точка достигнута
		path_index += 1

# --- Проверка и обработка застревания ---
func _check_and_fix_stuck(delta: float) -> void:
	_stuck_sample_timer -= delta
	if _stuck_sample_timer <= 0.0:
		var moved_dist := _last_pos.distance_to(global_position)
		var approx_speed := moved_dist / maxf(stuck_check_period, 0.0001)
		_last_pos = global_position
		_stuck_sample_timer = stuck_check_period

		# Если враг двигается, но скорость слишком мала — считаем что застрял
		if moving and approx_speed < stuck_speed_threshold:
			_stuck_timer += stuck_check_period
		else:
			_stuck_timer = 0.0

		# Если таймер застревания превысил лимит — пробуем пересчитать путь
		if _stuck_timer >= stuck_timeout:
			_stuck_timer = 0.0
			if _target != null and _world != null:
				_request_path_to_target()
			else:
				# Иначе делаем «толчок» в сторону узла
				if path_index < path.size():
					var nudge := (path[path_index] - global_position).normalized() * 20.0
					global_position += nudge

# --- Запрос на пересчёт пути до игрока ---
func _request_path_to_target() -> void:
	if _world == null or _target == null:
		return
	var new_path: PackedVector2Array = _world.find_path_world(global_position, _target.global_position, allow_diagonals)
	if new_path.size() > 0:
		# Оптимизируем путь: удаляем слишком близкие точки
		path = _dedupe_waypoints(new_path, waypoint_reach_dist * 0.5)
		path_index = 0
		moving = true

# Убираем лишние подряд идущие точки в пути
func _dedupe_waypoints(src: PackedVector2Array, merge_dist: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var last: Vector2 = Vector2.INF
	for p in src:
		if last == Vector2.INF or last.distance_to(p) > merge_dist:
			out.append(p)
			last = p
	return out
