extends CanvasLayer
class_name UIManager

@export var coin_label_path: NodePath
@export var exit_button_path: NodePath

# Панель конца игры (накладывается поверх)
@export var overlay_path: NodePath
@export var result_label_path: NodePath          # Label внутри overlay
@export var exit_after_end_button_path: NodePath # Button внутри overlay

# Узел контроллера игры, от которого приходят сигналы
@export var game_controller_path: NodePath       # GameController (узел, эмитит сигналы)

var _coin_label: Label
var _exit_button: Button

var _overlay: Control
var _result_label: Label
var _restart_button: Button
var _exit_after_end_button: Button

var _game_controller: Node

func _ready() -> void:
	# UI должен работать при паузе

	_coin_label = get_node(coin_label_path) as Label
	_exit_button = get_node(exit_button_path) as Button
	if _exit_button:
		_exit_button.pressed.connect(_on_exit_pressed)

	_overlay = get_node(overlay_path) as Control
	_result_label = get_node(result_label_path) as Label
	_exit_after_end_button = get_node(exit_after_end_button_path) as Button

	if _overlay:
		_overlay.visible = false

	if _exit_after_end_button:
		_exit_after_end_button.pressed.connect(_on_after_exit_pressed)

	_game_controller = get_node(game_controller_path)
	if _game_controller:
		_game_controller.victory.connect(_on_game_controller_victory)
		_game_controller.game_over.connect(_on_game_controller_game_over)

func _on_exit_pressed() -> void:
	var saver := get_node("../GameSaver")
	if saver:
		saver.save_game()
	get_tree().change_scene_to_file("res://Scenes/MainMenu.tscn")

func _on_after_exit_pressed() -> void:
	Engine.time_scale = 1
	get_tree().change_scene_to_file("res://Scenes/MainMenu.tscn")

func _on_game_controller_coin_count_changed(new_value: int) -> void:
	if _coin_label:
		_coin_label.text = "Coins: %d" % new_value

func _on_game_controller_victory() -> void:
	_show_victory()

func _on_game_controller_game_over() -> void:
	_show_game_over()

# --- Вспомогательные методы показа конца игры ---

func _show_victory() -> void:
	if _overlay:
		_overlay.visible = true
	if _result_label:
		_result_label.text = "Победа!"
	Engine.time_scale = 0
	var saver := get_node("../GameSaver")
	if saver:
		saver.clear_save()

func _show_game_over() -> void:
	if _overlay:
		_overlay.visible = true
	if _result_label:
		_result_label.text = "Поражение"
	Engine.time_scale = 0
	var saver := get_node("../GameSaver")
	if saver:
		saver.clear_save()
