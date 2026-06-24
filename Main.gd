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

var sleep_label
var food_label
var entertainment_label
var social_label
var health_label
var physical_label
var mental_label
var activity_label
var time_label
var status_label
var speed_label
var money_label

func _ready():
	sleep_label = get_node("SleepLabel")
	food_label = get_node("FoodLabel")
	entertainment_label = get_node("EntertainmentLabel")
	social_label = get_node("SocialLabel")
	health_label = get_node("HealthLabel")
	physical_label = get_node("PhysicalLabel")
	mental_label = get_node("MentalLabel")
	activity_label = get_node("ActivityLabel")
	time_label = get_node("TimeLabel")
	status_label = get_node("StatusLabel")
	speed_label = get_node("SpeedLabel")
	money_label = get_node("MoneyLabel")
	jane = Character_Class.new(jane_config_dict)

func _process(_delta):
	var dm = TimeManager.consume_delta()
	jane.tick(dm, TimeManager.get_day_part())
	update_gui()

func update_gui():
	sleep_label.text = "Sleep: " + str(int(jane.sleep))
	food_label.text = "Food: " + str(int(jane.food))
	entertainment_label.text = "Entertainment: " + str(int(jane.entertainment))
	social_label.text = "Social: " + str(int(jane.social))
	health_label.text = "Health: " + str(int(jane.health))
	physical_label.text = "Physical: " + str(int(jane.physical))
	mental_label.text = "Mental: " + str(int(jane.mental))
	money_label.text = "Money: " + str(int(jane.money))
	activity_label.text = "Activity: " + (jane.current_activity if jane.current_activity != "" else "—")
	time_label.text = "Time: " + TimeManager.get_clock_string() + " (" + TimeManager.get_day_part() + ")"
	var status = "Idle" if not jane.is_busy else (jane.current_activity + " · 剩 " + str("%.1f" % jane.remaining_hours) + "h")
	status_label.text = "Status: " + status
	var sp = "paused" if TimeManager.paused else (str(TimeManager.speed_scale) + "x")
	speed_label.text = "Speed: " + sp + "   [1/2/3 切速 · Space 暂停]"

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: TimeManager.set_speed(1.0)
			KEY_2: TimeManager.set_speed(2.0)
			KEY_3: TimeManager.set_speed(3.0)
			KEY_SPACE: TimeManager.toggle_pause()
