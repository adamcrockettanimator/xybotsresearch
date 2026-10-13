extends Node

# Menu-owned roster handed to the match scene. Every character begins vacant;
# a false slot becomes a bot only after the lobby starts the match.
var human_slots: Array[bool] = [false, false, false, false]
var slot_device_ids: Array[int] = [-1, -1, -1, -1]

func set_human_slot(slot_index: int, is_human: bool) -> void:
	if slot_index >= 0 and slot_index < human_slots.size():
		human_slots[slot_index] = is_human
		if not is_human:
			slot_device_ids[slot_index] = -1

func claim_slot(slot_index: int, device_id: int) -> void:
	if slot_index >= 0 and slot_index < human_slots.size():
		human_slots[slot_index] = true
		slot_device_ids[slot_index] = device_id

func is_human_slot(slot_index: int) -> bool:
	return slot_index >= 0 and slot_index < human_slots.size() and human_slots[slot_index]

func device_for_human_slot(slot_index: int) -> int:
	if not is_human_slot(slot_index) or slot_index >= slot_device_ids.size():
		return -1
	return slot_device_ids[slot_index]

func assign_device_to_human_slot(slot_index: int, device_id: int) -> bool:
	if not is_human_slot(slot_index) or slot_index >= slot_device_ids.size():
		return false
	for other_index in range(slot_device_ids.size()):
		if other_index != slot_index and is_human_slot(other_index) and slot_device_ids[other_index] == device_id:
			return false
	slot_device_ids[slot_index] = device_id
	return true

func release_slot(slot_index: int) -> void:
	set_human_slot(slot_index, false)
