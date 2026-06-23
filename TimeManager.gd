extends Node

const BASE_MIN_PER_SEC: float = 5.0

var game_minutes: float = 480.0
var speed_scale: float = 1.0
var paused: bool = false
var _last_consumed_game_minutes: float = 480.0

func _process(delta: float) -> void:
	if not paused:
		game_minutes += BASE_MIN_PER_SEC * speed_scale * delta

func get_hour() -> int:
	return int(floor(game_minutes / 60.0)) % 24

func get_day_part() -> String:
	var h := get_hour()
	if h >= 22 or h < 6:
		return "night"
	if h < 12:
		return "morning"
	if h < 18:
		return "afternoon"
	return "evening"

func get_clock_string() -> String:
	var total := int(floor(game_minutes)) % 1440
	var hh := int(total / 60.0)
	var mm := total % 60
	return "%02d:%02d" % [hh, mm]

func consume_delta() -> float:
	var d := game_minutes - _last_consumed_game_minutes
	_last_consumed_game_minutes = game_minutes
	return d

func set_speed(n: float) -> void:
	speed_scale = n

func toggle_pause() -> void:
	paused = not paused
