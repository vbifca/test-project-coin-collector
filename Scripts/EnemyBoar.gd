extends EnemyBase
class_name EnemyWanderer

# --- Параметры блуждания ---
@export_group("Wander")
@export_range(64.0, 4096.0, 1.0) var wander_radius: float = 640.0        # радиус, в пределах которого враг ищет случайную цель
@export_range(0.1, 5.0, 0.1) var repath_interval: float = 0.8            # период пересчёта пути до цели
@export_range(1, 64, 1) var random_goal_attempts: int = 16               # сколько раз пытаться найти валидную цель
@export_range(2.0, 64.0, 0.5) var goal_reached_distance: float = 12.0    # расстояние, при котором считаем цель достигнутой
@export_range(0.0, 5.0, 0.1) var idle_time_min: float = 0.2              # минимальное время ожидания
@export_range(0.0, 5.0, 0.1) var idle_time_max: float = 0.8              # максимальное время ожидания

@export_group("World")

# --- Служебные таймеры и флаги ---
var _repath_timer := 0.0           # таймер пересчёта пути
var _idle_timer := 0.0             # таймер ожидания между целями
var _has_goal := false             # есть ли текущая цель
var _goal_global := Vector2.ZERO   # глобальные координаты цели

# Путь до конфигурационного файла
@export var config_path: String = "res://Config/config.json"

# --- Загрузка и применение настроек ---
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
	# ожидаем секцию: { "enemies": { "wanderer": { ... } } }
	if not (cfg.has("enemies") and typeof(cfg.enemies) == TYPE_DICTIONARY):
		return
	var enemies := cfg.enemies as Dictionary
	if not (enemies.has("wanderer") and typeof(enemies.wanderer) == TYPE_DICTIONARY):
		return
	var w := enemies.wanderer as Dictionary

	# Пути и общие флаги
	if w.has("world_path"):
		world_path = NodePath(String(w.world_path))
	if w.has("target_path"):
		target_path = NodePath(String(w.target_path))
	if w.has("allow_diagonals"):
		allow_diagonals = bool(w.allow_diagonals)

	# Параметры блуждания
	if w.has("wander_radius"):
		wander_radius = clamp(float(w.wander_radius), 0.0, 16384.0)
	if w.has("repath_interval"):
		repath_interval = clamp(float(w.repath_interval), 0.05, 10.0)
	if w.has("random_goal_attempts"):
		random_goal_attempts = clamp(int(w.random_goal_attempts), 1, 1024)
	if w.has("goal_reached_distance"):
		goal_reached_distance = clamp(float(w.goal_reached_distance), 1.0, 256.0)
	if w.has("idle_time_min"):
		idle_time_min = max(0.0, float(w.idle_time_min))
	if w.has("idle_time_max"):
		idle_time_max = max(0.0, float(w.idle_time_max))
	if idle_time_max < idle_time_min:
		# защита от неверных значений: если max < min, меняем местами
		var t := idle_time_min
		idle_time_min = idle_time_max
		idle_time_max = t

	# Параметры базового класса
	if w.has("speed"):
		speed = max(0.0, float(w.speed))
	if w.has("sprite_path"):
		sprite_path = NodePath(String(w.sprite_path))
	print("Boar config loaded")

# --- Инициализация ---
func Init(playerPath: NodePath, worldPath: NodePath) -> void:
	if worldPath != NodePath():
		world_path = worldPath
	_world = get_node(world_path) if world_path != NodePath() else null

func _ready() -> void:
	_load_config()
	_last_pos = global_position
	_idle_timer = 0.0
	_repath_timer = repath_interval

# --- Основная логика ---
func _physics_process(delta: float) -> void:
	if _world == null:
		return

	# если цели нет — ждём и выбираем новую
	if not _has_goal:
		_idle_timer -= delta
		if _idle_timer <= 0.0:
			_pick_new_goal()
	else:
		# если цель есть — периодически перепрокладываем путь
		_repath_timer -= delta
		if _repath_timer <= 0.0:
			_request_path_to_goal()
			_repath_timer = repath_interval

	# движение по текущему пути
	_move_along_path(delta)

	# проверка: достигли цели?
	if _has_goal and global_position.distance_to(_goal_global) <= goal_reached_distance:
		_clear_goal_with_idle()

	# проверка застревания (из базового класса)
	_check_and_fix_stuck(delta)

# --- Внутренние функции ---
# Выбирает случайную новую цель в пределах wander_radius
func _pick_new_goal() -> void:
	var found := false
	var attempts := int(clamp(random_goal_attempts, 1, 1024))
	var start := global_position

	for i in attempts:
		var dir := Vector2(
			randf() * 2.0 - 1.0,
			randf() * 2.0 - 1.0
		)
		if dir.length() == 0.0:
			continue
		dir = dir.normalized()
		var dist := randf() * wander_radius
		var candidate := start + dir * dist

		# проверка: можно ли дойти до этой точки
		var path := PackedVector2Array(_world.find_path_world(start, candidate, allow_diagonals))
		if path.size() >= 2:
			_goal_global = candidate
			set_path(path)
			_has_goal = true
			_repath_timer = repath_interval
			found = true
			break

	# если не нашли цель — подождём и попробуем позже
	if not found:
		_clear_goal_with_idle()

# Перепрокладывает путь до текущей цели
func _request_path_to_goal() -> bool:
	if not _has_goal or _world == null:
		return false
	var path := PackedVector2Array(_world.find_path_world(global_position, _goal_global, allow_diagonals))
	if path.size() >= 2:
		set_path(path)
		return true
	return false

# Сбрасывает цель и назначает время простоя
func _clear_goal_with_idle() -> void:
	_has_goal = false
	_goal_global = global_position
	_idle_timer = randf_range(idle_time_min, idle_time_max)
