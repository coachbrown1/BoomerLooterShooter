extends CanvasLayer

@onready var screen_fx = $ScreenFX
@onready var health_label = $MarginContainer/HBoxContainer/HealthLabel
@onready var ammo_label = $MarginContainer/HBoxContainer/AmmoLabel

func _ready() -> void:
	# Print out a message so the user knows about the debug key
	print("Debug: Press 'G' to toggle Screen Effects (Saturation/Vignette)")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_G:
		if screen_fx:
			screen_fx.visible = !screen_fx.visible
			print("Screen Effects: ", "ON" if screen_fx.visible else "OFF")

func update_health(health: int) -> void:
	if not is_node_ready():
		await ready
	if health_label:
		health_label.text = "Health: " + str(health)

func update_ammo(ammo: int, max_ammo: int) -> void:
	if not is_node_ready():
		await ready
	if ammo_label:
		ammo_label.text = "Ammo: " + str(ammo) + " / " + str(max_ammo)
