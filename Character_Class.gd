class_name Character_Class
extends Node

var Name_of_character

var sleep_max
var food_max
var entertainment_max
var social_max
var health_max
var physical_max
var mental_max

var sleep_decay
var food_decay
var entertainment_decay
var social_decay
var health_decay
var physical_decay
var mental_decay

var sleep
var food
var entertainment
var social
var health
var physical
var mental

# money（阶段3 新增，第 8 need）
var money_max
var money_decay
var money

# 活动持续状态
var current_activity: String = ""
var remaining_hours: float = 0.0
var is_busy: bool = false

# recency（阶段5：选过活动降 utility 逼轮换）
var activity_recency: Dictionary = {}
var RECENCY_PENALTY: float = 10.0

const DEFAULT_DURATION_HOURS: float = 2.0

func _init(config = {}):
	Name_of_character = config["character_name"]
	sleep_max = config["sleep_initial_max"]
	food_max = config["food_initial_max"]
	entertainment_max = config["entertainment_initial_max"]
	social_max = config["social_initial_max"]
	health_max = config["health_initial_max"]
	physical_max = config["physical_initial_max"]
	mental_max = config["mental_initial_max"]
	money_max = config["money_initial_max"]
	sleep_decay = config["sleep_initial_decay"]
	food_decay = config["food_initial_decay"]
	entertainment_decay = config["entertainment_initial_decay"]
	social_decay = config["social_initial_decay"]
	health_decay = config["health_initial_decay"]
	physical_decay = config["physical_initial_decay"]
	mental_decay = config["mental_initial_decay"]
	money_decay = config["money_initial_decay"]
	sleep = round(sleep_max / 2)
	food = round(food_max / 2)
	entertainment = round(entertainment_max / 2)
	social = round(social_max / 2)
	health = round(health_max / 2)
	physical = round(physical_max / 2)
	mental = round(mental_max / 2)
	money = round(money_max / 2)

# 全部活动表。effects 为 per_hour 毛速率;duration_hours 未标吃默认 2h;allowed_during 未标则任意时段。
var list_of_activities = {
	"sleeping": {"effects": {"sleep": 15, "health": 2, "mental": 3}, "duration_hours": 8, "allowed_during": ["night"]},
	"take_a_nap": {"effects": {"sleep": 12}, "duration_hours": 1, "allowed_during": ["afternoon", "evening"]},
	"eating_at_home": {"effects": {"food": 55, "health": 4}, "duration_hours": 1},
	"eating_out": {"effects": {"food": 30, "social": 5, "entertainment": 5, "money": -5}, "duration_hours": 2},
	"grocery_shopping": {"effects": {"food": 15, "physical": 5, "money": -9}, "duration_hours": 2},
	"going_to_the_gym": {"effects": {"physical": 12, "health": 5, "money": -9}, "duration_hours": 2},
	"socializing_at_cafe": {"effects": {"social": 8, "food": 10, "money": -5}, "duration_hours": 2},
	"watching_movie": {"effects": {"entertainment": 10, "mental": -1, "money": -9}, "duration_hours": 2},
	"reading": {"effects": {"mental": 12, "entertainment": 5}, "duration_hours": 1},
	"working_overtime": {"effects": {"mental": -3, "physical": -4, "food": -5, "money": 20}, "duration_hours": 4, "allowed_during": ["morning", "afternoon"]},
	"going_to_doctor": {"effects": {"health": 12, "money": -14}, "duration_hours": 2},
	"playing_sports": {"effects": {"physical": 12, "social": 5, "health": 4, "money": -5}, "duration_hours": 2},
	"taking_a_bath": {"effects": {"health": 8, "mental": 6}, "duration_hours": 1},
	"cooking": {"effects": {"food": 20, "mental": 4}, "duration_hours": 1},
	"going_to_a_concert": {"effects": {"entertainment": 8, "social": 5, "money": -9}, "duration_hours": 3},
	"visiting_family": {"effects": {"social": 8, "mental": 4}, "duration_hours": 3},
	"doing_yoga": {"effects": {"health": 8, "mental": 8}, "duration_hours": 1},
	"online_shopping": {"effects": {"entertainment": 8, "mental": -1, "money": -9}, "duration_hours": 1},
	"playing_video_games": {"effects": {"entertainment": 10, "mental": -2, "money": -5}, "duration_hours": 2},
	"going_to_a_museum": {"effects": {"entertainment": 5, "mental": 6, "money": -5}, "duration_hours": 3},
	"gardening": {"effects": {"mental": 5, "physical": 5}, "duration_hours": 2},
	"taking_a_walk": {"effects": {"health": 5, "mental": 5, "physical": 5}, "duration_hours": 1},
	"going_to_the_beach": {"effects": {"entertainment": 5, "health": 4, "money": -9}, "duration_hours": 3},
	"visiting_a_spa": {"effects": {"health": 8, "mental": 6, "money": -14}, "duration_hours": 3},
	"going_fishing": {"effects": {"entertainment": 5, "mental": 4, "money": -5}, "duration_hours": 3},
	"painting": {"effects": {"mental": 6, "entertainment": 5}, "duration_hours": 2},
	"writing": {"effects": {"mental": 4}, "duration_hours": 2},
	"going_to_a_party": {"effects": {"social": 10, "entertainment": 10, "money": -9}, "duration_hours": 3},
	"volunteering": {"effects": {"social": 5, "mental": 5}, "duration_hours": 3},
	"going_to_a_library": {"effects": {"mental": 8}, "duration_hours": 2},
	"cleaning_the_house": {"effects": {"health": 4, "mental": -2}, "duration_hours": 2}
}

func _decay_need(need_name: String, hours: float) -> void:
	var rate: float = get(str(need_name) + "_decay")
	set(need_name, max(0.0, float(get(need_name)) - rate * hours))

func _apply_effects_hourly(effects: Dictionary, hours: float) -> void:
	for need in effects:
		var mx: float = get(str(need) + "_max")
		set(need, clamp(float(get(need)) + effects[need] * hours, 0.0, mx))

# 角色自治主循环。① decay 用完整 hours;② effects 用 actual=min(hours,remaining) 钳到剩余;③ 空闲则选活动。
func tick(delta_minutes: float, day_part: String) -> void:
	var hours: float = delta_minutes / 60.0
	if hours <= 0.0:
		return
	_decay_need("sleep", hours)
	_decay_need("food", hours)
	_decay_need("entertainment", hours)
	_decay_need("social", hours)
	_decay_need("health", hours)
	_decay_need("physical", hours)
	_decay_need("mental", hours)
	_decay_need("money", hours)
	for k in activity_recency:
		activity_recency[k] = max(0.0, activity_recency[k] - 0.15 * hours)
	if is_busy:
		var actual: float = min(hours, remaining_hours)
		_apply_effects_hourly(list_of_activities[current_activity]["effects"], actual)
		remaining_hours -= hours
		if remaining_hours <= 0.0:
			is_busy = false
			current_activity = ""
	else:
		select_best_activity(day_part)

func get_activities(day_part: String, _character_name: String) -> Dictionary:
	var result: Dictionary = {}
	for act_name in list_of_activities:
		var act = list_of_activities[act_name]
		var allowed = act.get("allowed_during", [])
		if allowed.is_empty() or day_part in allowed:
			result[act_name] = act
	return result

func calculate_utility(activity: Dictionary) -> float:
	var total_utility: float = 0.0
	var duration: float = activity.get("duration_hours", DEFAULT_DURATION_HOURS)
	for need in activity["effects"].keys():
		var effect_ph: float = activity["effects"][need]
		var decay_ph: float = get(str(need) + "_decay")
		var current: float = get(need)
		var mx: float = get(str(need) + "_max")
		# money 是资源型 need：消费负 effect 不被下界 clamp 抹掉（消除非单调 DEFECT money-utility-clamp-nonmonotonic，阶段7），其余 need 维持 clamp 净模型
		var raw_change: float = current + (effect_ph - decay_ph) * duration
		var net_change: float = (min(raw_change, mx) if need == "money" else clamp(raw_change, 0.0, mx)) - current
		var urgency: float = float(mx - current) / float(mx)
		total_utility += net_change * urgency
	return total_utility

func select_best_activity(day_part: String) -> void:
	var activities := get_activities(day_part, Name_of_character)
	var best_activity := ""
	var highest_utility := -1e9
	var names := activities.keys()
	names.sort()   # 确定遍历顺序：消除 GDScript Dictionary 跨运行哈希顺序导致的非确定选择（阶段7 发现）
	for activity_name in names:
		var raw := calculate_utility(activities[activity_name])
		var utility: float = raw - activity_recency.get(activity_name, 0.0) * RECENCY_PENALTY
		if utility > highest_utility:
			best_activity = activity_name
			highest_utility = utility
	if best_activity != "":
		current_activity = best_activity
		activity_recency[best_activity] = 1.0
		remaining_hours = min(list_of_activities[best_activity].get("duration_hours", DEFAULT_DURATION_HOURS), TimeManager.get_day_part_remaining_hours())
		is_busy = true
