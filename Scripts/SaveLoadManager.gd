extends Node
class_name GameSave

const SAVE_PATH := "user://savegame.json"


func has_save(path: String = SAVE_PATH) -> bool:
	return FileAccess.file_exists(path)


func save_game(path: String = SAVE_PATH) -> void:
	var game_control := get_node("../GameController")
	var player_list := get_tree().get_nodes_in_group("Player")
	var player: Node = null
	if player_list.size() > 0:
		player = player_list[0]

	var coins := get_tree().get_nodes_in_group("Coin")
	var enemies := get_tree().get_nodes_in_group("Enemy")

	var data := {
		"version": 1,
		"meta": {"time_unix": Time.get_unix_time_from_system()},
		"score": game_control.get("player_score") as int,
		"player": {},
		"coins": [],
		"enemies": []
	}

	if player != null:
		data.player = {
			"scene": String(player.scene_file_path),
			"pos": [player.global_position.x, player.global_position.y]
		}

	for c in coins:
		data.coins.append({
			"scene": String(c.scene_file_path),
			"pos": [c.global_position.x, c.global_position.y]
		})

	for e in enemies:
		data.enemies.append({
			"scene": String(e.scene_file_path),
			"pos": [e.global_position.x, e.global_position.y]
		})

	var json := JSON.stringify(data, "\t")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(json)
	f.flush()
	f.close()


# вместо мгновенной пересборки — дайте движку удалить старые ноды
func load_game(path: String = SAVE_PATH) -> void:
	if not FileAccess.file_exists(path):
		return

	var text: String = FileAccess.get_file_as_string(path)
	var parsed :=Dictionary(JSON.parse_string(text))
	var data: Dictionary = parsed

	# узлы окружения
	var scene_root: Node = get_tree().current_scene
	var game_control: Node = null
	if scene_root.has_node("../GameController"):
		game_control = scene_root.get_node("../GameController")
	else:
		if scene_root.has_node("GameController"):
			game_control = scene_root.get_node("GameController")
		else:
			# последний шанс: поиск по имени в дереве
			for n in get_tree().get_nodes_in_group("GameController"):
				game_control = n
				break

	var world: Node = null
	if scene_root.has_node("../World"):
		world = scene_root.get_node("../World")
	else:
		if scene_root.has_node("World"):
			world = scene_root.get_node("World")
		else:
			# ищем любой узел с методом find_path_world
			var all_nodes: Array = scene_root.get_children()
			for n in all_nodes:
				if n.has_method("find_path_world"):
					world = n
					break

	# 1) удалить старые сущности
	_delete_group("Player")
	_delete_group("Enemy")
	_delete_group("Coin")
	await get_tree().process_frame

	# 2) восстановить счёт
	if game_control != null:
		if data.has("score"):
			game_control.set("player_score", int(data.get("score", 0)))
			if game_control.has_signal("coin_count_changed"):
				game_control.emit_signal("coin_count_changed", int(data.get("score", 0)))

	# 3) игрок
	var player_inst: Node2D = null
	var pd: Dictionary = data.get("player", {})
	var p_scene_path: String = String(pd.get("scene", ""))
	if p_scene_path != "":
		var p_scene: PackedScene = ResourceLoader.load(p_scene_path) as PackedScene
		if p_scene != null:
			player_inst = p_scene.instantiate()
			scene_root.add_child(player_inst)
			player_inst.add_to_group("Player")
			var ppos: Array = pd.get("pos", [0, 0])
			player_inst.global_position = Vector2(float(ppos[0]), float(ppos[1]))

	# ВАЖНО: подключаем сигнал Game Over к контроллеру
	_try_connect_player_game_over(player_inst, game_control)


	# 4) монеты + сигнал начисления
	var coins_arr: Array = data.get("coins", [])
	for cd in coins_arr:
		var c_scene: PackedScene = ResourceLoader.load(String(cd.scene)) as PackedScene
		if c_scene != null:
			var coin: Node2D = c_scene.instantiate()
			scene_root.add_child(coin)
			coin.add_to_group("Coin")
			var cp: Array = cd.get("pos", [0, 0])
			coin.global_position = Vector2(float(cp[0]), float(cp[1]))
			# переподключаем сигнал
			if coin.has_signal("collected") and game_control != null:
				if game_control.has_method("_on_coin_collected"):
					coin.connect("collected", Callable(game_control, "_on_coin_collected"))
				else:
					if game_control.has_method("on_coin_collected"):
						coin.connect("collected", Callable(game_control, "on_coin_collected"))

	# 5) враги + инициализация путей/цели
	var enemies_arr: Array = data.get("enemies", [])
	var player_np: NodePath = NodePath()
	var world_np: NodePath = NodePath()
	if player_inst != null:
		player_np = player_inst.get_path()
	if world != null:
		world_np = world.get_path()

	for ed in enemies_arr:
		var e_scene: PackedScene = ResourceLoader.load(String(ed.scene)) as PackedScene
		if e_scene != null:
			var e: Node2D = e_scene.instantiate()
			scene_root.add_child(e)
			e.add_to_group("Enemy")
			var ep: Array = ed.get("pos", [0, 0])
			e.global_position = Vector2(float(ep[0]), float(ep[1]))
			# ключевое: отдаём им цель и мир
			if e.has_method("Init"):
				if player_np != NodePath() and world_np != NodePath():
					e.call("Init", player_np, world_np)
				else:
					if e.has_variable("target_path") and player_np != NodePath():
						e.set("target_path", player_np)
					if e.has_variable("world_path") and world_np != NodePath():
						e.set("world_path", world_np)


func clear_save(path: String = SAVE_PATH) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


# --- internal ---

func _delete_group(group_name: String) -> void:
	var list: Array = get_tree().get_nodes_in_group(group_name)
	for n in list:
		n.process_mode = Node.PROCESS_MODE_DISABLED
		if n is CanvasItem:
			(n as CanvasItem).visible = false
		n.queue_free()
		
func _try_connect_player_game_over(player_inst: Node, game_control: Node) -> void:
	if player_inst == null:
		return
	if not player_inst.has_signal("game_over"):
		return
	if game_control != null:
		if game_control.has_method("_on_game_over"):
			player_inst.connect("game_over", Callable(game_control, "_on_game_over"))
		elif game_control.has_method("on_game_over"):
			player_inst.connect("game_over", Callable(game_control, "on_game_over"))
