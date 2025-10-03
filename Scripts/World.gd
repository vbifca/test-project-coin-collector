@tool
extends TileMapLayer

@export_range(20, 1024, 1) var width: int = 40
@export_range(20, 1024, 1) var height: int = 80

@export var tile_source_id: int = 0

@export var atlas_water: Vector2i = Vector2i(0, 0)
@export var atlas_sand:  Vector2i = Vector2i(1, 0)
@export var atlas_grass: Vector2i = Vector2i(2, 0)
@export var atlas_rock:  Vector2i = Vector2i(3, 0)
@export var atlas_snow:  Vector2i = Vector2i(4, 0)

@export var seed: int = 12345
@export var frequency: float = 0.08
@export var octaves: int = 4
@export var lacunarity: float = 2.0
@export var gain: float = 0.5

@export var t_water: float = -0.3
@export var t_sand:  float = -0.1
@export var t_grass: float =  0.35
@export var t_rock:  float =  0.65

@export var generate_on_ready: bool = true
@export var center_layer_origin: bool = true

# ---- Новое: «бордюр» по периметру карты ----
@export_group("Borders")
@export var enforce_border: bool = true
@export_range(1, 8, 1) var border_thickness: int = 1
# Если нужен другой тайл-барьер — укажите тут; по умолчанию используем воду
@export var border_atlas: Vector2i = Vector2i(10, 10)

var _noise := FastNoiseLite.new()
var grid: Array = []

func _ready() -> void:
	seed = randi() % 1000
	grid.clear()
	grid.resize(height)
	for y in range(height):
		var row: Array = []
		row.resize(width)
		for x in range(width):
			row[x] = true
		grid[y] = row

	if Engine.is_editor_hint():
		if generate_on_ready:
			generate()
	else:
		generate()

@export_category("Actions")
@export var regenerate_button := false:
	set(value):
		if value:
			regenerate_button = false
			generate()

func _config_noise() -> void:
	_noise.seed = seed
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = frequency
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = octaves
	_noise.fractal_lacunarity = lacunarity
	_noise.fractal_gain = gain

func generate() -> void:
	_config_noise()
	clear()

	# 1) Основная генерация
	for y in range(height):
		for x in range(width):
			var n: float = _noise.get_noise_2d(float(x), float(y))
			var atlas: Vector2i = _pick_atlas(n)
			if atlas == atlas_water:
				grid[y][x] = false
			set_cell(Vector2i(x, y), tile_source_id, atlas)

	# 2) Применяем непроходимую рамку (стены/вода) по краям
	if enforce_border:
		_apply_border()

	update_internals()

func _pick_atlas(n: float) -> Vector2i:
	if n < t_water:
		return atlas_water
	elif n < t_sand:
		return atlas_sand
	elif n < t_grass:
		return atlas_grass
	elif n < t_rock:
		return atlas_rock
	else:
		return atlas_snow

func randomize_and_generate() -> void:
	seed = randi()
	generate()

# --- Грид/бордюр ---

func _apply_border() -> void:
	var t := clampi(border_thickness, 1, min(width, height) / 2)
	for y in range(height):
		for x in range(width):
			var on_border := x < t or y < t or x >= width - t or y >= height - t
			if on_border:
				grid[y][x] = false
				set_cell(Vector2i(x, y), tile_source_id, border_atlas)

# --- Поиск пути в клетках ---

func find_path_cells(
	start_cell: Vector2i,
	goal_cell: Vector2i,
	allow_diagonals: bool = false
) -> PackedVector2Array:
	if grid.is_empty():
		return PackedVector2Array()

	# Кламп в пределах карты на случай «вылета» координат
	start_cell = _clamp_cell(start_cell)
	goal_cell  = _clamp_cell(goal_cell)

	if not (_is_walkable(start_cell) and _is_walkable(goal_cell)):
		return PackedVector2Array()

	var astar := AStarGrid2D.new()
	astar.region = Rect2i(0, 0, width, height)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER if not allow_diagonals else AStarGrid2D.DIAGONAL_MODE_ALWAYS
	astar.default_compute_heuristic = (AStarGrid2D.HEURISTIC_MANHATTAN if not allow_diagonals else AStarGrid2D.HEURISTIC_EUCLIDEAN)
	astar.update()

	for y in range(height):
		for x in range(width):
			if not bool(grid[y][x]):
				astar.set_point_solid(Vector2i(x, y), true)

	astar.update()
	return astar.get_point_path(start_cell, goal_cell)

# --- Поиск пути в мировых координатах ---

func find_path_world(
	start_global: Vector2,
	goal_global: Vector2,
	allow_diagonals: bool = false
) -> PackedVector2Array:
	var start_cell := local_to_map(to_local(start_global))
	var goal_cell  := local_to_map(to_local(goal_global))

	# Кламп к границам карты, чтобы не обращаться к grid вне диапазона
	start_cell = _clamp_cell(start_cell)
	goal_cell  = _clamp_cell(goal_cell)

	var cell_path := find_path_cells(start_cell, goal_cell, allow_diagonals)
	if cell_path.is_empty():
		return PackedVector2Array()

	var world_path := PackedVector2Array()
	for i in cell_path:
		var cell: Vector2i = i
		var local_pos: Vector2 = map_to_local(cell)
		world_path.append(to_global(local_pos))

	return world_path

# --- Утилиты ---

func world_to_cell(world_pos: Vector2) -> Vector2i:
	return _clamp_cell(local_to_map(to_local(world_pos)))

func cell_to_world(cell: Vector2i) -> Vector2:
	return to_global(map_to_local(_clamp_cell(cell)))

func _clamp_cell(c: Vector2i) -> Vector2i:
	return Vector2i(clampi(c.x, 0, width - 1), clampi(c.y, 0, height - 1))

func _is_in_bounds(c: Vector2i, w: int, h: int) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < w and c.y < h

func _is_walkable(c: Vector2i) -> bool:
	return grid[c.y][c.x]
	
# --- API для персонажа ---

# Явная проверка "в пределах карты"
func is_in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < width and c.y < height

# Можно ли ходить по клетке
func is_cell_walkable(c: Vector2i) -> bool:
	if not is_in_bounds(c):
		return false
	return bool(grid[c.y][c.x])

# Вода ли эта клетка (по атласу)
func is_cell_water(c: Vector2i) -> bool:
	if not is_in_bounds(c):
		return false
	var atlas := get_cell_atlas_coords(c)
	return atlas == atlas_water

# Центр клетки в мировых координатах (для приземления)
func cell_to_world_center(c: Vector2i) -> Vector2:
	return to_global(map_to_local(_clamp_cell(c)))
