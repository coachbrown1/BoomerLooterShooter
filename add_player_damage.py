import sys

file_path = "J:/BoomerShooter/boomer-shooter/Scripts/Player/player.gd"
with open(file_path, "r") as f:
    content = f.read()

damage_func = """

@export var max_health: int = 100
var current_health: int = max_health

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	current_health = max_health
	var hud = get_tree().root.get_node_or_null("TestRoom/HUD")
	if hud:
		hud.update_health(current_health)

func take_damage(amount: int) -> void:
	if current_health <= 0:
		return
	current_health -= amount
	current_health = max(0, current_health)
	
	var hud = get_tree().root.get_node_or_null("TestRoom/HUD")
	if hud:
		hud.update_health(current_health)
		
	if current_health <= 0:
		print("Player Died!")
"""

content = content.replace("func _ready() -> void:\n\tInput.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)", damage_func)

with open(file_path, "w") as f:
    f.write(content)
print("Updated player damage logic.")
