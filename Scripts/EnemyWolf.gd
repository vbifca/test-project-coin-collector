extends EnemyBase
class_name EnemyChaser

@export_group("Target")
# Дистанции включения/выключения погони (гистерезис, чтобы не дёргался на границе)
@export_range(1.0, 2000.0, 1.0) var chase_start_distance: float = 320.0
@export_range(1.0, 3000.0, 1.0) var chase_stop_distance: float = 560.0
# Как часто перепрокладывать путь во время погони
@export_range(0.1, 3.0, 0.1) var chase_repath_interval: float = 0.3

@export_group("World")

# Флаги и таймеры режима погони
var _in_chase := false
var _repath_timer := 0.0

# Опциональная внешняя конфигурация
@export var config_path: String = "res://Config/config.json"

# --- Загрузка/применение конфига ---
func _load_config() -> void:
	if not FileAccess.file_exists(config_path):
		return
	var text := FileAccess.get_file_as_string(config_path)
	if text.is_empty():
		return
	var parsed := Dictionary(JSON.parse_string(text))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	_apply_config(parsed as Dictionary)

func _apply_config(cfg: Dictionary) -> void:
	# ожидаем: { "enemies": { "chaser": { ... } } }
	if not (cfg.has("enemies") and typeof(cfg.enemies) == TYPE_DICTIONARY):
		return
	var enemies := cfg.enemies as Dictionary
	if not (enemies.has("chaser") and typeof(enemies.chaser) == TYPE_DICTIONARY):
		return
	var c := enemies.chaser as Dictionary

	# Пути к узлам (необязательно)
	if c.has("world_path"):
		world_path = NodePath(String(c.world_path))
	if c.has("target_path"):
		target_path = NodePath(String(c.target_path))

	# Параметры погони
	if c.has("chase_start_distance"):
		chase_start_distance = clamp(float(c.chase_start_distance), 1.0, 10000.0)
	if c.has("chase_stop_distance"):
		chase_stop_distance = clamp(float(c.chase_stop_distance), 1.0, 20000.0)
	if c.has("chase_repath_interval"):
		chase_repath_interval = clamp(float(c.chase_repath_interval), 0.05, 10.0)

	# Флаги/настройки базового класса
	if c.has("allow_diagonals"):
		allow_diagonals = bool(c.allow_diagonals)
	if c.has("speed"):
		speed = max(0.0, float(c.speed))
	if c.has("sprite_path"):
		sprite_path = NodePath(String(c.sprite_path))

	# Простая защита от неверной конфигурации гистерезиса
	if chase_stop_distance <= chase_start_distance:
		chase_stop_distance = chase_start_distance + 32.0

	print("Wolf config loaded")

# Удобная инициализация из спавнера
func Init(playerPath: NodePath, worldPath: NodePath) -> void:
	_load_config() # конфиг может переопределить пути
	target_path = playerPath
	if worldPath != NodePath():
		world_path = worldPath
	# Кэшируем ссылки, если пути заданы
	_target = get_node(target_path) as Node2D if target_path != NodePath() else null
	_world  = get_node(world_path)  if world_path != NodePath() else null

func _ready() -> void:
	# Подстраховка, если Init не вызывался
	_target = get_node(target_path) as Node2D if target_path != NodePath() else null
	_world  = get_node(world_path)  if world_path != NodePath() else null
	_last_pos = global_position

func _physics_process(delta: float) -> void:
	# Управление состоянием погони (вкл/выкл по дистанциям)
	if _target != null and _world != null and is_instance_valid(_target):
		var dist := global_position.distance_to(_target.global_position)

		if _in_chase:
			if dist > chase_stop_distance:
				_in_chase = false
		else:
			if dist < chase_start_distance:
				_in_chase = true
				_request_path_to_target()      # первый расчёт пути сразу при входе в погоню
				_repath_timer = chase_repath_interval

		# Пока гонимся — периодически перепрокладываем путь
		if _in_chase:
			_repath_timer -= delta
			if _repath_timer <= 0.0:
				_request_path_to_target()
				_repath_timer = chase_repath_interval

	# Движение по текущему пути (реализовано в EnemyBase)
	_move_along_path(delta)

	# Авто-детект застревания (EnemyBase) — при необходимости сам пересчитает путь
	_check_and_fix_stuck(delta)
