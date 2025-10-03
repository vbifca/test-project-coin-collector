extends Area2D
class_name Coin

signal collected(coin: Coin)
var _taken: bool = false  # защита от двойного срабатывания

func _on_area_entered(area: Area2D):
	if _is_player_node(area):
		_collect()
	else:
		if _is_player_node(area.get_parent()):
			_collect()

func _is_player_node(n: Node) -> bool:
	return n.is_in_group("Player")

func _collect() -> void:
	if _taken:
		return
	_taken = true
	emit_signal("collected", self)
	queue_free()
