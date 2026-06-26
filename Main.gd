extends Control

var jane
var jane_config_dict = {
	"character_name": "Jane",
	"sleep_initial_max": 100,
	"food_initial_max": 100,
	"entertainment_initial_max": 100,
	"social_initial_max": 100,
	"health_initial_max": 100,
	"physical_initial_max": 100,
	"mental_initial_max": 100,
	"sleep_initial_decay": 6,
	"food_initial_decay": 5,
	"entertainment_initial_decay": 4,
	"social_initial_decay": 3,
	"health_initial_decay": 1,
	"physical_initial_decay": 3,
	"mental_initial_decay": 2,
	"money_initial_max": 100,
	"money_initial_decay": 1.5
}

# need 配置：[jane 成员属性名, 场景行节点前缀]；顺序对应 tscn 自上而下
const NEEDS := [
	["sleep", "Sleep"],
	["food", "Food"],
	["entertainment", "Entertainment"],
	["social", "Social"],
	["health", "Health"],
	["physical", "Physical"],
	["mental", "Mental"],
	["money", "Money"],
]

# 缓存控件引用：need 属性名 -> ProgressBar / 数值 Label（_ready 一次性取，避免每帧 get_node）
var need_bars := {}
var need_vals := {}

var activity_label
var status_label
var time_label
var speed_label

func _ready():
	for entry in NEEDS:
		var prop: String = entry[0]
		var prefix: String = entry[1]
		need_bars[prop] = get_node("Margin/VBox/" + prefix + "Row/" + prefix + "Bar")
		need_vals[prop] = get_node("Margin/VBox/" + prefix + "Row/" + prefix + "Val")
	activity_label = get_node("Margin/VBox/ActivityLabel")
	status_label = get_node("Margin/VBox/StatusLabel")
	time_label = get_node("Margin/VBox/TimeLabel")
	speed_label = get_node("Margin/VBox/SpeedLabel")
	jane = Character_Class.new(jane_config_dict)

func _process(_delta):
	var dm = TimeManager.consume_delta()
	jane.tick(dm, TimeManager.get_day_part())
	update_gui()

func update_gui():
	for entry in NEEDS:
		var prop: String = entry[0]
		var v: int = int(jane.get(prop))
		need_bars[prop].value = v
		need_bars[prop].modulate = _need_color(v)
		need_vals[prop].text = str(v)
	activity_label.text = "Activity: " + (jane.current_activity if jane.current_activity != "" else "—")
	var status = "Idle" if not jane.is_busy else (jane.current_activity + " · 剩 " + str("%.1f" % jane.remaining_hours) + "h")
	status_label.text = "Status: " + status
	time_label.text = "Time: " + TimeManager.get_clock_string() + " (" + TimeManager.get_day_part() + ")"
	var sp = "paused" if TimeManager.paused else (str(TimeManager.speed_scale) + "x")
	speed_label.text = "Speed: " + sp + "   [1/2/3 切速 · Space 暂停]"

# need 值染色：< 30 危(红) / < 60 警(黄) / >= 60 佳(绿)。一眼看出哪个 need 快崩
func _need_color(v: int) -> Color:
	if v < 30:
		return Color(0.90, 0.30, 0.30)
	elif v < 60:
		return Color(0.95, 0.72, 0.25)
	else:
		return Color(0.30, 0.80, 0.40)

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: TimeManager.set_speed(1.0)
			KEY_2: TimeManager.set_speed(2.0)
			KEY_3: TimeManager.set_speed(3.0)
			KEY_SPACE: TimeManager.toggle_pause()
