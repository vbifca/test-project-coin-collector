extends CharacterBody2D

signal game_over()

@export var speed: float = 160.0
@export var sprite_path: NodePath
@export_range(0.0, 0.5, 0.01) var input_deadzone: float = 0.1

# Конфиг
@export var config_path: String = "res://Config/config.json"

# Группа врагов (может переопределяться конфигом)
var _enemy_group := "Enemy"

# --- Параметры JUMP / DASH ---
@export_group("Jump")
@export var world_path: NodePath = "/root/Node2D/World"   # узел мира, от которого ждём методы поиска/проверки клеток
@export_range(1, 6, 1) var jump_tiles: int = 3            # сколько клеток максимум «перелетаем» вперёд
@export_range(0.05, 1.0, 0.01) var jump_duration: float = 0.4
@export_range(0.1, 3.0, 0.05) var jump_cooldown: float = 0.6
@export var allow_diagonals_in_jump: bool = true          # можно ли прыгать по диагонали (для изометрии часто нужно)

# Внутреннее состояние прыжка
var _is_jumping := false
var _jump_from: Vector2
var _jump_to: Vector2
var _jump_t := 0.0
var _jump_cd_timer := 0.0
var _pre_jump_collision_mask: int = 0

# Последнее направление ввода — чтобы можно было прыгнуть «с места»
var _last_dir := Vector2.DOWN

@onready var _sprite: AnimatedSprite2D = _resolve_sprite()
@onready var _has_anim: Dictionary = _build_anim_map()
@onready var _world: Node = get_node(world_path) if world_path != NodePath() else null

# Имена анимаций по секторам (по часам, шаг 45°)
const _DIR_NAMES: PackedStringArray = [
	"right", "up_right", "up", "up_left", "left", "down_left", "down", "down_right"
]

func _ready() -> void:
	# Подтягиваем конфиг (может поменять скорость, deadzone, пути к спрайту и т.д.)
	_load_config()
	# Если конфиг поменял world_path — актуализируем ссылку на мир
	if world_path != NodePath():
		_world = get_node_or_null(world_path)

func _physics_process(dt: float) -> void:
	# Кулдаун прыжка
	if _jump_cd_timer > 0.0:
		_jump_cd_timer = maxf(0.0, _jump_cd_timer - dt)

	# Если уже в прыжке — интерполируем позицию и выходим
	if _is_jumping:
		_process_jump(dt)
		return

	# Читаем ввод осей
	var input_vec := _read_input()
	if input_vec.length() >= input_deadzone:
		_last_dir = input_vec.normalized()

	# Старт прыжка по кнопке
	if Input.is_action_just_pressed("jump") and not _is_jumping and _jump_cd_timer <= 0.0:
		if _try_start_jump():
			return # прыжок перехватывает управление движением

	# Обычное перемещение
	if input_vec.length() < input_deadzone:
		velocity = Vector2.ZERO
		_play_idle()
	else:
		var v := input_vec.normalized() * speed
		velocity = v
		_play_move(v)

	move_and_slide()

# Суммируем оси (WASD/стрелки/аналог)
func _read_input() -> Vector2:
	var x := Input.get_action_strength("right") - Input.get_action_strength("left")
	var y := Input.get_action_strength("down")  - Input.get_action_strength("up")
	return Vector2(x, y)

# -------------------- JUMP CORE --------------------

func _try_start_jump() -> bool:
	# Направление прыжка — из последнего валидного ввода
	var dir: Vector2 = _choose_jump_dir(_last_dir)
	if dir == Vector2.ZERO:
		print("Jump cancelled: no direction")
		return false

	# Нужен валидный мир и его API (координатная сетка + проверка проходимости)
	if _world == null:
		print("Jump cancelled: no world assigned")
		return false
	if not (_world.has_method("world_to_cell") and _world.has_method("cell_to_world_center") and _world.has_method("is_cell_walkable")):
		print("Jump cancelled: world missing required methods")
		return false

	# Переводим позицию в координаты клетки
	var start_cell: Vector2i = _world.world_to_cell(global_position)
	var step: Vector2i = _dir_to_cell_step(dir) # шаг по клеткам для одного «тика» прыжка
	if step == Vector2i.ZERO:
		print("Jump cancelled: invalid step direction")
		return false

	var current: Vector2i = start_cell
	var landing_cell: Vector2i = start_cell
	var found_ground: bool = false

	# Проходим клетки по направлению прыжка, пока не встретим сушу (walkable && !water)
	for i in jump_tiles:
		current += step

		# Если мир умеет проверять границы — используем
		if _world.has_method("is_in_bounds") and not _world.is_in_bounds(current):
			print("Jump cancelled: out of bounds at ", current)
			return false

		var walkable: bool = bool(_world.is_cell_walkable(current))
		var water: bool = _world.has_method("is_cell_water") and bool(_world.is_cell_water(current))

		# стена → прыжок запрещаем сразу
		if not walkable and not water:
			print("Jump cancelled: wall at ", current)
			return false

		# первая найденная суша — будущая точка приземления
		if walkable and not water:
			landing_cell = current
			found_ground = true

	if not found_ground:
		print("Jump cancelled: no ground found within range")
		return false

	var target: Vector2 = _world.cell_to_world_center(landing_cell)

	# --- подготовка прыжка ---
	_jump_from = global_position
	_jump_to = target
	_jump_t = 0.0
	_is_jumping = true
	velocity = Vector2.ZERO

	# На время прыжка отключаем маску столкновений, чтобы «пролетать» триггеры/стены
	_pre_jump_collision_mask = collision_mask
	collision_mask = 0

	# Анимация «jump», если есть; иначе — направление бега до точки
	if _has_anim.get("jump", false):
		_sprite.play("jump")
	else:
		_play_move((_jump_to - _jump_from).normalized() * speed)

	print("Jump started from", _jump_from, "to", _jump_to)
	return true

# Интерполяция прыжка во времени
func _process_jump(dt: float) -> void:
	_jump_t += dt / jump_duration
	var t := float(clamp(_jump_t, 0.0, 1.0))
	var eased := _ease_in_out_quad(t) # небольшое сглаживание
	global_position = _jump_from.lerp(_jump_to, eased)

	if t >= 1.0:
		_finish_jump()

# Завершение прыжка: возвращаем маску, вешаем кд, уходим в idle
func _finish_jump() -> void:
	_is_jumping = false
	collision_mask = _pre_jump_collision_mask
	_jump_cd_timer = jump_cooldown
	_play_idle()

# Нормализация и запрет диагоналей (если выключены)
func _choose_jump_dir(dir: Vector2) -> Vector2:
	if dir.length() < 0.001:
		return Vector2.ZERO
	if allow_diagonals_in_jump:
		return dir.normalized()
	# без диагоналей — выбираем доминирующую ось
	return Vector2(
		signf(dir.x) if absf(dir.x) >= absf(dir.y) else 0.0,
		0.0 if absf(dir.x) >= absf(dir.y) else signf(dir.y)
	)

# Маппинг «направление → шаг по клеткам» для изометрической сетки
# Примечание: значения (0,2), (1,2) и т.п. подобраны под вашу world_to_cell;
# если шаг "вниз" уходит по диагонали — корректируйте здесь под свою геометрию TileMap.
func _dir_to_cell_step(dir: Vector2) -> Vector2i:
	if dir == Vector2.ZERO:
		return Vector2i.ZERO

	# Обрезаем мелкие шумы стика, чтобы «вниз» не превращался в «вниз-вправо»
	var dx := 0
	var dy := 0
	if absf(dir.x) > 0.3:
		dx = 1 if dir.x > 0 else -1
	if absf(dir.y) > 0.3:
		dy = 1 if dir.y > 0 else -1

	var step := Vector2i.ZERO
	if dx == 0 and dy > 0:       # вниз
		step = Vector2i(0, 2)
	elif dx == 0 and dy < 0:     # вверх
		step = Vector2i(0, -2)
	elif dy == 0 and dx > 0:     # вправо
		step = Vector2i(1, 0)
	elif dy == 0 and dx < 0:     # влево
		step = Vector2i(-1, 0)
	elif dx > 0 and dy > 0:      # вниз+вправо
		step = Vector2i(1, 2)
	elif dx < 0 and dy > 0:      # вниз+влево
		step = Vector2i(-1, 2)
	elif dx > 0 and dy < 0:      # вверх+вправо
		step = Vector2i(1, -2)
	elif dx < 0 and dy < 0:      # вверх+влево
		step = Vector2i(-1, -2)

	return step

# Плавная ease in/out-кривая
func _ease_in_out_quad(x: float) -> float:
	return 2.0 * x * x if x < 0.5 else 1.0 - pow(-2.0 * x + 2.0, 2.0) * 0.5

# -------------------- Анимации/движение --------------------

func _play_move(v: Vector2) -> void:
	var dir_name: String = _vector_to_dir_name(v)
	_play_anim(dir_name)

func _play_idle() -> void:
	# «idle_<последнее_направление>», если есть; иначе просто стоп
	var current: String = _sprite.animation
	var base_dir: String = _extract_dir_from_name(current)
	var idle_name: String = ("idle_" + base_dir) if base_dir != "" else "idle_down"
	var has_idle: bool = bool(_has_anim.get(idle_name, false))
	if has_idle:
		if _sprite.animation != idle_name or not _sprite.is_playing():
			_sprite.play(idle_name)
	else:
		_sprite.stop()

# Выбор именованного сектора по вектору скорости
func _vector_to_dir_name(v: Vector2) -> String:
	var angle := atan2(-v.y, v.x)
	var sector := int(roundi(angle / (PI / 4.0)))
	sector = posmod(sector, 8)
	return _DIR_NAMES[sector]

# Воспроизведение нужной анимации с фолбэком
func _play_anim(dir_name: String) -> void:
	var has_anim: bool = bool(_has_anim.get(dir_name, false))
	if has_anim:
		if _sprite.animation != dir_name or not _sprite.is_playing():
			_sprite.play(dir_name)
		return

	var fb := _fallback_dir(dir_name)
	if fb != "" and bool(_has_anim.get(fb, false)):
		if _sprite.animation != fb or not _sprite.is_playing():
			_sprite.play(fb)
		return

	if not _sprite.is_playing():
		_sprite.stop()

func _fallback_dir(dir_name: String) -> String:
	match dir_name:
		"up_right":
			return "up" if bool(_has_anim.get("up", false)) else "right"
		"up_left":
			return "up" if bool(_has_anim.get("up", false)) else "left"
		"down_left":
			return "down" if bool(_has_anim.get("down", false)) else "left"
		"down_right":
			return "down" if bool(_has_anim.get("down", false)) else "right"
		_:
			return ""

# Достаём «направление» из имени текущей анимации (для idle-логики)
func _extract_dir_from_name(anim_name: String) -> String:
	if anim_name == "":
		return ""
	var parts: PackedStringArray = anim_name.split("_")
	var start := 0
	if parts.size() > 0 and parts[0] == "idle":
		start = 1
	if start >= parts.size():
		return ""
	var res := parts[start]
	for i in range(start + 1, parts.size()):
		res += "_" + parts[i]
	return res

# Разрешение узла-спрайта (из поля или по умолчанию — дочерний $AnimatedSprite2D)
func _resolve_sprite() -> AnimatedSprite2D:
	if sprite_path != NodePath():
		return get_node(sprite_path) as AnimatedSprite2D
	return $AnimatedSprite2D

# Кэш наличия анимаций: { "run_right": true, ... }
func _build_anim_map() -> Dictionary:
	var map := {}
	var frames := _sprite.sprite_frames
	if frames:
		for name in frames.get_animation_names():
			map[name] = true
	return map

# -------------------- Конфиг --------------------

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
	# player.speed, player.input_deadzone, player.sprite_path, jump_*, gameplay.enemy_group
	if cfg.has("player") and typeof(cfg.player) == TYPE_DICTIONARY:
		var p: Dictionary = cfg.player
		if p.has("speed"):
			speed = float(p.speed)
		if p.has("input_deadzone"):
			input_deadzone = clamp(float(p.input_deadzone), 0.0, 0.5)
		if p.has("sprite_path"):
			sprite_path = NodePath(String(p.sprite_path))
			if has_node(sprite_path):
				_sprite = _resolve_sprite()
				_has_anim = _build_anim_map()
		if p.has("jump_tiles"):
			jump_tiles = int(p.jump_tiles)
		if p.has("jump_duration"):
			jump_duration = maxf(0.05, float(p.jump_duration))
		if p.has("jump_cooldown"):
			jump_cooldown = maxf(0.05, float(p.jump_cooldown))
	print("Player config loaded")

	if cfg.has("gameplay") and typeof(cfg.gameplay) == TYPE_DICTIONARY:
		var g: Dictionary = cfg.gameplay
		if g.has("enemy_group"):
			_enemy_group = String(g.enemy_group)

# -------------------- Столкновения --------------------
# Важно: убедись, что сигнал Area2D.area_entered подключён к этому методу (через редактор или кодом).

func _on_area_2d_area_entered(area: Area2D) -> void:
	# Если сам Area2D помечен как Enemy — сразу Гейм-овер
	if area.is_in_group(_enemy_group):
		_game_over()
		return
	# Либо его родитель — враг (коллайдер/триггер — дочерний)
	var p := area.get_parent()
	if p and is_instance_valid(p) and p.is_in_group(_enemy_group):
		_game_over()

func _game_over() -> void:
	# Только сигналим — удаление / смена сцен делать извне (из GameController),
	# чтобы избежать ошибок «удаление в физическом коллбэке».
	emit_signal("game_over")
