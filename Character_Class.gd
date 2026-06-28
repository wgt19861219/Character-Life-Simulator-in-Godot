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
var last_forced_need: String = ""   # stage9 v2 轮换：上次硬触发补的 need，本次优先换一个（避免 ent 独占）

# need deficit（阶段8：长期低位 need 累计亏欠，select 时驱动均衡；money 不参与）
# 用直接成员变量（非字典）：execute_gdscript 对 Dictionary 操作非确定（Godot 4.7 + Node 不入树 bug），
# 直接属性 + set/get 稳定（stage7 _decay_need 已验证）
var sleep_deficit: float = 0.0
var food_deficit: float = 0.0
var entertainment_deficit: float = 0.0
var social_deficit: float = 0.0
var health_deficit: float = 0.0
var physical_deficit: float = 0.0
var mental_deficit: float = 0.0
const DEFICIT_LOW: float = 30.0      # need < 此值开始累计 deficit
const DEFICIT_HIGH: float = 60.0     # need > 此值衰减 deficit
const DEFICIT_ACCRUE: float = 0.5    # 低位累计速率 /h
const DEFICIT_DECAY: float = 0.8     # 高位衰减系数（每游戏小时 ×此值）
const DEFICIT_WEIGHT: float = 0.5    # select 时 deficit 加成权重（Task3 集成调；0.5 平衡 ent/phys 补偿与 money/night 不回归）
const FORCE_DEFICIT_THRESHOLD: float = 15.0   # stage9：deficit 超此值的品质 need 强制补给，打破 max-choose「永远的第二名」

# stage10：每日品质配额（只 ent/phys —— 目标 need；social/mental/health 仍走 L2 deficit）
# 直接成员变量（非 Dictionary）：execute_gdscript 对 Node 字典/属性非确定，直接属性稳定（stage8 §4.1 教训）
var entertainment_quota_target: float = 3.0   # 每天 ent 补给目标 h（Task5 集成调）
var physical_quota_target: float = 3.0
var entertainment_quota_done: float = 0.0     # 今日已补给 h
var physical_quota_done: float = 0.0
var _last_day: int = -1                       # 跨天重置用（tick 开头判定）

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
	# stage10：跨天重置（tick 开头，修跨天 busy actual 归属）
	var today: int = TimeManager.get_day()
	if today != _last_day:
		_last_day = today
		entertainment_quota_done = 0.0
		physical_quota_done = 0.0
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
	# need deficit 更新（阶段8：长期低位 need 累计亏欠，select 时驱动均衡；money 不参与）
	for need_name in ["sleep", "food", "entertainment", "social", "health", "physical", "mental"]:
		var cur_d: float = float(get(need_name))
		var def_prop: String = need_name + "_deficit"
		var prev_d: float = float(get(def_prop))
		if cur_d < DEFICIT_LOW:
			set(def_prop, prev_d + DEFICIT_ACCRUE * hours)
		elif cur_d > DEFICIT_HIGH:
			set(def_prop, prev_d * pow(DEFICIT_DECAY, hours))
	if is_busy:
		var actual: float = min(hours, remaining_hours)
		_apply_effects_hourly(list_of_activities[current_activity]["effects"], actual)
		# stage10：累计今日品质配额（只 ent/phys；按 actual；sleeping/work 不计）
		var eff: Dictionary = list_of_activities[current_activity]["effects"]
		if float(eff.get("entertainment", 0)) > 0.0:
			entertainment_quota_done += actual
		if float(eff.get("physical", 0)) > 0.0:
			physical_quota_done += actual
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

func _commit_activity(act_name: String) -> void:
	current_activity = act_name
	activity_recency[act_name] = 1.0
	remaining_hours = min(list_of_activities[act_name].get("duration_hours", DEFAULT_DURATION_HOURS), TimeManager.get_day_part_remaining_hours())
	is_busy = true

# 该 need 的补给活动中 utility 最高的（供 survival 层用）
func _best_replenish(need_name: String, day_part: String) -> String:
	var acts := get_activities(day_part, Name_of_character)
	var best := ""
	var best_u := -1e9
	var names := acts.keys()
	names.sort()
	for an in names:
		var eff = acts[an]["effects"]
		if eff.has(need_name) and float(eff[need_name]) > 0.0:
			var u := calculate_utility(acts[an])
			if u > best_u:
				best_u = u
				best = an
	return best

# stage10：该 need 正 effect 活动里 effect 值最高、且 food 不跌穿 15 的（food 预算过滤）
# L1.5 配额层与 L2 deficit 层共用（强制补给层统一 effect 最高策略）
func _best_replenish_safe(need_name: String, day_part: String) -> String:
	var acts := get_activities(day_part, Name_of_character)
	var best: String = ""
	var best_effect: float = -1e9
	var names := acts.keys()
	names.sort()
	for an in names:
		var eff: Dictionary = acts[an]["effects"]
		if not (eff.has(need_name) and float(eff[need_name]) > 0.0):
			continue
		var dur: float = float(acts[an].get("duration_hours", DEFAULT_DURATION_HOURS))
		var food_after: float = float(food) + (float(eff.get("food", 0.0)) - float(food_decay)) * dur
		if food_after < 15.0:
			continue
		if float(eff[need_name]) > best_effect:
			best_effect = float(eff[need_name])
			best = an
	return best

# L1 survival 强制层（双层调度）：food/money/sleep 低于安全线 → 强制补给，优先于品质/utility
func _pick_survival_activity(day_part: String) -> String:
	if food < 25.0:
		return _best_replenish("food", day_part)
	if money < 15.0:
		if get_activities(day_part, Name_of_character).has("working_overtime"):
			return "working_overtime"
	if day_part == "night" and sleep < 30.0:
		return "sleeping"
	return ""

# stage10 L1.5 品质配额：今日未达配额的 ent/phys，守卫满足则强制补给（proactive 保底）
func _pick_quota_activity(day_part: String) -> String:
	# 跨天重置已在 tick 开头完成，此处只读 owe
	var ent_owe: bool = entertainment_quota_done < entertainment_quota_target
	var phys_owe: bool = physical_quota_done < physical_quota_target
	var need: String = ""
	if ent_owe and phys_owe:
		# 都欠时选 deficit 高的（谁更亏先补谁）
		need = "entertainment" if entertainment_deficit >= physical_deficit else "physical"
	elif ent_owe:
		need = "entertainment"
	elif phys_owe:
		need = "physical"
	if need == "":
		return ""    # 配额满 → fallback L2
	# survival 守卫（沿用 L2：food>=35 / money>=20）
	if food < 35.0 or money < 20.0:
		return ""    # survival 紧 → 让位
	return _best_replenish_safe(need, day_part)

func select_best_activity(day_part: String) -> void:
	# L1 survival 强制（双层调度）：刚需优先于品质/utility（治 v2 night 崩 + 强化 food/money/sleep）
	var surv := _pick_survival_activity(day_part)
	if surv != "":
		_commit_activity(surv)
		return
	# L1.5 品质配额（stage10）：今日未达配额的 ent/phys，守卫满足则 proactive 强制补给
	var quota := _pick_quota_activity(day_part)
	if quota != "":
		_commit_activity(quota)
		return
	# L2 品质 deficit 轮换（stage9 v2）：找 deficit 最大且超阈的品质 need，强制补给，打破 max-choose「永远的第二名」
	var forced_need := ""
	var forced_def := FORCE_DEFICIT_THRESHOLD
	for need_name in ["entertainment", "physical", "social", "mental", "health", "sleep"]:
		var d := float(get(str(need_name) + "_deficit"))
		if d > forced_def:
			forced_def = d
			forced_need = need_name
	# 轮换：若最大 need == last_forced_need 且还有别的超阈 need，换第二个（治 phys 永远轮不到）
	if forced_need != "" and forced_need == last_forced_need:
		var alt_need := ""
		var alt_def := FORCE_DEFICIT_THRESHOLD
		for need_name in ["entertainment", "physical", "social", "mental", "health", "sleep"]:
			if need_name == last_forced_need:
				continue
			var d := float(get(str(need_name) + "_deficit"))
			if d > alt_def:
				alt_def = d
				alt_need = need_name
		if alt_need != "":
			forced_need = alt_need
	# survival 守卫（v2 收紧 food 25→35，给 night 8h decay buffer）+ money
	if forced_need != "" and food >= 35.0 and money >= 20.0:
		var f_best := _best_replenish_safe(forced_need, day_part)
		if f_best != "":
			last_forced_need = forced_need
			_commit_activity(f_best)
			return
	var activities := get_activities(day_part, Name_of_character)
	var best_activity := ""
	var highest_utility := -1e9
	var names := activities.keys()
	names.sort()   # 确定遍历顺序：消除 GDScript Dictionary 跨运行哈希顺序导致的非确定选择（阶段7 发现）
	for activity_name in names:
		var raw := calculate_utility(activities[activity_name])
		var utility: float = raw - activity_recency.get(activity_name, 0.0) * RECENCY_PENALTY
		# deficit 加成：活动对该 need 有正 effect 时，按该 need 累计 deficit 加 utility（money 不参与；阶段8）
		var effects = activities[activity_name]["effects"]
		for need_name in effects:
			if effects[need_name] > 0 and need_name != "money":
				utility += float(get(str(need_name) + "_deficit")) * DEFICIT_WEIGHT
		if utility > highest_utility:
			best_activity = activity_name
			highest_utility = utility
	if best_activity != "":
		_commit_activity(best_activity)
