extends Node

# stage9 TDD 测试。run_and_verify 跑（项目上下文 deterministic）。

var cfg = {
	"character_name":"Jane","sleep_initial_max":100,"food_initial_max":100,
	"entertainment_initial_max":100,"social_initial_max":100,"health_initial_max":100,
	"physical_initial_max":100,"mental_initial_max":100,"money_initial_max":100,
	"sleep_initial_decay":6,"food_initial_decay":5,"entertainment_initial_decay":4,
	"social_initial_decay":3,"health_initial_decay":1,"physical_initial_decay":3,
	"mental_initial_decay":2,"money_initial_decay":1.5
}

func make_jane():
	var j = Character_Class.new(cfg)
	j.sleep = 50.0; j.food = 50.0; j.entertainment = 50.0; j.social = 50.0
	j.health = 50.0; j.physical = 50.0; j.mental = 50.0; j.money = 50.0
	j.sleep_deficit = 0.0; j.food_deficit = 0.0; j.entertainment_deficit = 0.0
	j.social_deficit = 0.0; j.health_deficit = 0.0; j.physical_deficit = 0.0; j.mental_deficit = 0.0
	j.activity_recency = {}
	return j

func has_eff(eff, need):
	return eff.has(need) and float(eff[need]) > 0.0

func _ready():
	TimeManager.game_minutes = 540.0  # 9:00 morning
	var results = []

	# T1: ent deficit 超阈 + food 安全 → 选 ent 补给（非 food 活动）
	var j1 = make_jane()
	j1.entertainment = 0.0
	j1.entertainment_deficit = 20.0
	j1.select_best_activity("morning")
	var e1 = j1.list_of_activities[str(j1.current_activity)]["effects"]
	var t1 = has_eff(e1, "entertainment") and not has_eff(e1, "food")
	print("T1 selected=%-18s pass=%s" % [str(j1.current_activity), t1])
	results.append(t1)

	# T2: ent deficit 超阈 + food 危机 → survival 优先选 food
	var j2 = make_jane()
	j2.entertainment = 0.0
	j2.entertainment_deficit = 20.0
	j2.food = 20.0
	j2.select_best_activity("morning")
	var e2 = j2.list_of_activities[str(j2.current_activity)]["effects"]
	var t2 = has_eff(e2, "food")
	print("T2 selected=%-18s pass=%s" % [str(j2.current_activity), t2])
	results.append(t2)

	# T3(v2 轮换): ent+phys 都超阈 → 连续两次 select 应轮换，第二次选 phys 补给
	var j3 = make_jane()
	j3.entertainment = 0.0
	j3.physical = 0.0
	j3.entertainment_deficit = 20.0
	j3.physical_deficit = 20.0
	j3.select_best_activity("morning")
	var c3a = str(j3.current_activity)
	j3.is_busy = false
	j3.remaining_hours = 0.0
	j3.activity_recency = {}
	j3.select_best_activity("morning")
	var c3b = str(j3.current_activity)
	var t3 = has_eff(j3.list_of_activities[c3b]["effects"], "physical")
	print("T3 first=%-18s second=%-18s second_is_phys=%s" % [c3a, c3b, t3])
	results.append(t3)

	# T5(双层 L1): night + sleep 低 → 强制 sleeping（非品质活动，治 v2 night 崩）
	var j5 = make_jane()
	j5.sleep = 20.0
	j5.entertainment = 0.0
	j5.physical = 0.0
	j5.entertainment_deficit = 20.0
	j5.physical_deficit = 20.0
	TimeManager.game_minutes = 23.0 * 60.0  # 23:00 night
	j5.select_best_activity("night")
	var c5 = str(j5.current_activity)
	var t5 = c5 == "sleeping"
	print("T5 night_sleep_low selected=%-18s is_sleeping=%s" % [c5, t5])
	results.append(t5)

	if results.all(func(v): return v):
		print("ALL PASS")
	else:
		print("FAIL — 不通过的: ", results)
	get_tree().quit()
