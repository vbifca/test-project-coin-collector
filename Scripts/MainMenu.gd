extends Node


func _on_play_button_up() -> void:
	get_tree().change_scene_to_file("res://Scenes/MainScene.tscn")


func _on_exit_button_up() -> void:
	get_tree().quit()
