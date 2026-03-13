extends Node
class_name EventBus

# Dungeon Events
signal room_entered(room_id: int, player_id: int)
signal generation_completed()
signal encounter_started(encounter_id: String)
signal encounter_ended(encounter_id: String)
signal floor_completed(floor_number: int)

# Combat Events
signal player_died(player_id: int)
signal enemy_died(enemy_id: int)
signal boss_spawned(boss_node: Node3D)

# Items and Inventory
signal item_picked_up(item_data: Resource, player_id: int)
signal weapon_switched(weapon: Node3D, player_id: int)
