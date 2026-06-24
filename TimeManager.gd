extends Node

const BASE_MIN_PER_SEC: float = 5.0

const DAY_PART_BOUNDS = {
	"night": [22, 6],     # [start, end]；end < start 表示跨日。4 区间互斥全覆盖 0-23，遍历顺序无关
	"morning": [6, 12],
	"afternoon": [12, 18],
	"evening": [18, 22],
}

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
	for dp in DAY_PART_BOUNDS:
		var s: int = DAY_PART_BOUNDS[dp][0]
		var e: int = DAY_PART_BOUNDS[dp][1]
		if e > s:
			if h >= s and h < e:
				return dp
		else:
			if h >= s or h < e:
				return dp
	return "night"

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

func get_day_part_remaining_hours() -> float:
	var end_hour: int = DAY_PART_BOUNDS[get_day_part()][1]
	var cur_min := float(int(floor(game_minutes)) % 1440)
	var diff := float(end_hour * 60) - cur_min
	if diff <= 0.0:
		diff += 1440.0
	return diff / 60.0
