extends Node

@export var config_path: String = "res://Config/config.json"

@export_group("World / Grid")
@export var world_path: NodePath
@export var allow_diagonals: bool = false
@export var origin: Vector2 = Vector2.ZERO         # глобальное смещение начала сетки
@export var tile_size: Vector2 = Vector2(32, 16)   # размер тайла (iso-ромб/косая сетка)
@export var spawn_area: Rect2 = Rect2(Vector2.ZERO, Vector2(640, 640)) # прямоугольник для спавна

# Колбэк проверки проходимости клетки: (global_pos: Vector2) -> bool
@export var is_walkable: Callable

@export_group("Scenes")
@export var player_scene: PackedScene
@export var enemy_scene: Array[PackedScene]
@export var coin_scene: PackedScene

@export_group("Counts")
@export_range(1, 500, 1) var coins_count: int = 20
@export_range(0, 200, 1) var enemies_count: int = 5

@export_group("Parents (optional)")
@export var player_parent_path: NodePath
@export var enemies_parent_path: NodePath
@export var coins_parent_path: NodePath

# --- Технические параметры ---
const MAX_TRIES_PER_ITEM := 200
const MAX_TRIES_PLAYER := 500

var _world: Node
var _player_parent: Node
var _enemies_parent: Node
var _coins_parent: Node

var player_score: int

# Используем Dictionary как множество занятых клеток: ключ = Vector2i, значение = true
var _occupied := {}

var _player_global: Vector2
var _player_nodepath: NodePath

signal coin_count_changed(new_value: int)
signal victory()
signal game_over()

# --- Конфиг ---

func _load_config() -> void:
	if not FileAccess.file_exists(config_path):
		push_warning("Spawner: config.json не найден по пути %s" % config_path)
		return
	var text := FileAccess.get_file_as_string(config_path)
	if text.is_empty():
		return
	var parsed := Dictionary(JSON.parse_string(text))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Spawner: config.json имеет неверный формат")
		return
	_apply_config(parsed as Dictionary)

func _apply_config(cfg: Dictionary) -> void:
	if cfg.has("spawner") and typeof(cfg.spawner) == TYPE_DICTIONARY:
		var s: Dictionary = cfg.spawner
		if s.has("coins_count"):
			coins_count = int(s.coins_count)
		if s.has("enemies_count"):
			enemies_count = int(s.enemies_count)
		if s.has("allow_diagonals"):
			allow_diagonals = bool(s.allow_diagonals)
		if s.has("spawn_area") and typeof(s.spawn_area) == TYPE_DICTIONARY:
			var a := Dictionary(s.spawn_area)
			if a.has("x") and a.has("y") and a.has("w") and a.has("h"):
				spawn_area = Rect2(
					Vector2(float(a.x), float(a.y)),
					Vector2(float(a.w), float(a.h))
				)
		if s.has("tile_size") and typeof(s.tile_size) == TYPE_DICTIONARY:
			var ts := Dictionary(s.tile_size)
			if ts.has("x") and ts.has("y"):
				tile_size = Vector2(float(ts.x), float(ts.y))
	print("Game controller config loaded")

# --- Жизненный цикл ---

func _ready() -> void:
	_load_config()

	_world = get_node(world_path) if world_path != NodePath() else null
	if _world == null:
		push_error("Spawner: world_path не указан.")
		return

	# если контейнеры не заданы — используем текущий узел
	_player_parent  = get_node(player_parent_path)  if player_parent_path  != NodePath() else self
	_enemies_parent = get_node(enemies_parent_path) if enemies_parent_path != NodePath() else self
	_coins_parent   = get_node(coins_parent_path)   if coins_parent_path   != NodePath() else self

	# Фолбэк проверки проходимости: используем поиск пути в одну точку
	if not is_walkable.is_valid():
		push_warning("Spawner: is_walkable не задан. Использую fallback через find_path_world(p, p).")
		is_walkable = Callable(self, "_fallback_is_walkable")

	_clear_previous()

	var saver = get_node("../GameSaver")
	if saver.has_save():
		saver.load_game()
	else:
		_spawn_all()

func _clear_previous() -> void:
	_occupied.clear()
	for c in _player_parent.get_children():
		c.queue_free()
	for c in _enemies_parent.get_children():
		c.queue_free()
	for c in _coins_parent.get_children():
		c.queue_free()

# --- Обработчики состояний игры ---

func _on_game_over() -> void:
	# Важный трюк: удаление/смена сцены вне физ.коллбэка
	await get_tree().process_frame
	var saver = get_node("../GameSaver")
	saver.clear_save()
	emit_signal("game_over")

func _on_coin_collected(coin: Coin) -> void:
	player_score += 1
	emit_signal("coin_count_changed", player_score)
	if player_score == coins_count:
		emit_signal("victory")

# --- Спавн набора объектов ---

func _spawn_all() -> void:
	var player_ok := _spawn_player()
	if not player_ok:
		push_error("Spawner: не удалось найти проходимое место для игрока.")
		return

	var placed_coins := _spawn_coins_reachable()
	if placed_coins < coins_count:
		push_warning("Spawner: размещено монет %d из %d (недостаточно достижимых клеток)." % [placed_coins, coins_count])

	var placed_enemies := _spawn_enemies()
	if placed_enemies < enemies_count:
		push_warning("Spawner: размещено врагов %d из %d." % [placed_enemies, enemies_count])

# --- Спавн игрока ---

func _spawn_player() -> bool:
	var tries := 0
	while tries < MAX_TRIES_PLAYER:
		tries += 1
		var cell = _rand_walkable_free_cell() # может вернуть null
		if cell == null:
			continue
		var c: Vector2i = cell
		var pos := _cell_center_to_global(c)

		# Доп. проверка: стартовая позиция не в тупике (есть хотя бы один сосед)
		if _has_any_walkable_neighbor(c):
			if player_scene == null:
				push_error("Spawner: player_scene не задан.")
				return false
			var player := player_scene.instantiate()
			player.global_position = pos
			_player_parent.add_child(player)
			_player_global = pos
			_player_nodepath = player.get_path()
			_mark_occupied(c)
			player.add_to_group("Player")
			player.connect("game_over", Callable(self, "_on_game_over"))
			return true
	return false

# --- Спавн монет: гарантируем достижимость от игрока ---

func _spawn_coins_reachable() -> int:
	if coin_scene == null:
		push_warning("Spawner: coin_scene не задан.")
		return 0

	var placed := 0
	var tries := 0
	while placed < coins_count and tries < MAX_TRIES_PER_ITEM * coins_count:
		tries += 1
		var cell = _rand_walkable_free_cell() # может вернуть null
		if cell == null:
			continue
		var c: Vector2i = cell
		var coin_pos := _cell_center_to_global(c)

		# Проверяем достижимость путём из мира
		var path: PackedVector2Array = _world.find_path_world(_player_global, coin_pos, allow_diagonals)
		if path.size() > 1:
			var coin := coin_scene.instantiate()
			coin.global_position = coin_pos
			_coins_parent.add_child(coin)
			_mark_occupied(c)
			coin.connect("collected", Callable(self, "_on_coin_collected"))
			placed += 1
			coin.add_to_group("Coin")
	return placed

# --- Спавн врагов (на проходимых клетках) ---

func _spawn_enemies() -> int:
	if enemy_scene.is_empty():
		push_warning("Spawner: enemy_scene пустой — врагов не будет.")
		return 0

	var placed := 0
	var tries := 0
	while placed < enemies_count and tries < MAX_TRIES_PER_ITEM * enemies_count:
		tries += 1
		var cell = _rand_walkable_free_cell() # может вернуть null
		if cell == null:
			continue
		var c: Vector2i = cell
		var pos := _cell_center_to_global(c)

		var ps := enemy_scene[randi() % enemy_scene.size()]
		if ps == null:
			continue

		var enemy := ps.instantiate()
		enemy.global_position = pos
		_enemies_parent.add_child(enemy)
		_mark_occupied(c)
		placed += 1

		# Передаём противнику ссылки на игрока и мир (через NodePath)
		enemy.Init(_player_nodepath, _world.get_path())
		enemy.add_to_group("Enemy")
	return placed

# --- Преобразование координат сетка/мир ---

func _global_to_cell(p: Vector2) -> Vector2i:
	var lx := (p.x - origin.x) / tile_size.x
	var ly := (p.y - origin.y) / tile_size.y
	return Vector2i(floor(lx), floor(ly))

func _cell_to_global(c: Vector2i) -> Vector2:
	return origin + Vector2(c.x * tile_size.x, c.y * tile_size.y)

func _cell_center_to_global(c: Vector2i) -> Vector2:
	return _cell_to_global(c) + tile_size * 0.5

# --- Генерация кандидатов клеток ---

func _rand_cell_in_area() -> Vector2i:
	var min_c := _global_to_cell(spawn_area.position)
	var max_c := _global_to_cell(spawn_area.position + spawn_area.size - Vector2(1, 1))
	var cx := randi_range(min_c.x, max_c.x)
	var cy := randi_range(min_c.y, max_c.y)
	return Vector2i(cx, cy)

func _is_free_cell(c: Vector2i) -> bool:
	return not _occupied.has(c)

func _mark_occupied(c: Vector2i) -> void:
	_occupied[c] = true

# ВАЖНО: возвращает либо Vector2i (успех), либо null (не нашли)
func _rand_walkable_free_cell():
	var i := 0
	while i < 200:
		i += 1
		var c := _rand_cell_in_area()
		if not _is_free_cell(c):
			continue
		var pos := _cell_center_to_global(c)
		if is_walkable.call(pos):
			return c
	return null

# Есть ли хотя бы один сосед, доступный для старта/спавна
func _has_any_walkable_neighbor(c: Vector2i) -> bool:
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0),
		Vector2i(0, 1), Vector2i(0, -1)
	]
	if allow_diagonals:
		dirs.append(Vector2i(1, 1))
		dirs.append(Vector2i(1, -1))
		dirs.append(Vector2i(-1, 1))
		dirs.append(Vector2i(-1, -1))
	for d in dirs:
		var n := c + d
		if _is_free_cell(n) and is_walkable.call(_cell_center_to_global(n)):
			return true
	return false

# --- Фолбэк, если не передан свой колбэк проходимости ---
# Идея: если мир способен вернуть путь из точки в неё же (узел найден),
# значит позиция попадает в проходимую клетку/граф.
func _fallback_is_walkable(p: Vector2) -> bool:
	var path: PackedVector2Array = _world.find_path_world(p, p, allow_diagonals)
	return path.size() > 0
