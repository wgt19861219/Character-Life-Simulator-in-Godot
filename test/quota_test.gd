extends Node

const CFG := {"character_name":"Jane","sleep_initial_max":100,"food_initial_max":100,"entertainment_initial_max":100,"social_initial_max":100,"health_initial_max":100,"physical_initial_max":100,"mental_initial_max":100,"money_initial_max":100,"sleep_initial_decay":6,"food_initial_decay":5,"entertainment_initial_decay":4,"social_initial_decay":3,"health_initial_decay":1,"physical_initial_decay":3,"mental_initial_decay":2,"money_initial_decay":1.5}

func _ready() -> void:
	var fail: Array = []
	_test_get_day(fail)
	_test_quota_accrual(fail)
	_test_quota_day_reset(fail)
	_test_quota_cross_day_busy(fail)
	_test_best_replenish_safe(fail)
	_test_pick_quota(fail)
	print("QUOTA_TEST PASS" if fail.is_empty() else "QUOTA_TEST FAIL " + str(fail))
	get_tree().quit()

# Task 1：get_day 基于 game_minutes/1440
func _test_get_day(fail: Array) -> void:
	TimeManager.game_minutes = 480.0
	if TimeManager.get_day() != 0:
		fail.append("get_day(480)=期望0 得%d" % TimeManager.get_day())
	TimeManager.game_minutes = 1440.0
	if TimeManager.get_day() != 1:
		fail.append("get_day(1440)=期望1 得%d" % TimeManager.get_day())
	TimeManager.game_minutes = 1920.0
	if TimeManager.get_day() != 1:
		fail.append("get_day(1920)=期望1 得%d" % TimeManager.get_day())
	TimeManager.game_minutes = 2880.0
	if TimeManager.get_day() != 2:
		fail.append("get_day(2880)=期望2 得%d" % TimeManager.get_day())

# Task 2：按 actual 累计品质配额（reading: ent+5；2h actual → done=2）
func _test_quota_accrual(fail: Array) -> void:
	var C = preload("res://Character_Class.gd")
	var j = C.new(CFG)
	j.current_activity = "reading"
	j.is_busy = true
	j.remaining_hours = 2.0
	TimeManager.game_minutes = 600.0
	for i in range(2):
		j.tick(60.0, "afternoon")
	if abs(j.entertainment_quota_done - 2.0) > 0.01:
		fail.append("accrual: ent done=期望2.0 得%.2f" % j.entertainment_quota_done)

# Task 2：跨天重置（get_day 跳变 → done 清零）
func _test_quota_day_reset(fail: Array) -> void:
	var C = preload("res://Character_Class.gd")
	var j = C.new(CFG)
	j.entertainment_quota_done = 2.5
	j.physical_quota_done = 1.0
	j._last_day = 0
	TimeManager.game_minutes = 1440.0
	j.tick(60.0, "night")
	if abs(j.entertainment_quota_done) > 0.01 or abs(j.physical_quota_done) > 0.01:
		fail.append("day_reset: 未清零 ent=%.2f phys=%.2f" % [j.entertainment_quota_done, j.physical_quota_done])

# Task 2：跨天 busy 时 actual 归新 day（M3 回归——不丢失）
func _test_quota_cross_day_busy(fail: Array) -> void:
	var C = preload("res://Character_Class.gd")
	var j = C.new(CFG)
	j.current_activity = "reading"
	j.is_busy = true
	j.remaining_hours = 3.0
	j.entertainment_quota_done = 2.0
	j._last_day = 0
	TimeManager.game_minutes = 1440.0
	j.tick(60.0, "night")
	if j._last_day != 1:
		fail.append("cross_day: _last_day=期望1 得%d" % j._last_day)
	if abs(j.entertainment_quota_done - 1.0) > 0.01:
		fail.append("cross_day: ent done=期望1.0(归新day) 得%.2f" % j.entertainment_quota_done)

# Task 3：_best_replenish_safe 选 effect 最高（非 utility 最高）+ food 预算过滤（M1）
func _test_best_replenish_safe(fail: Array) -> void:
	var C = preload("res://Character_Class.gd")
	var j = C.new(CFG)
	j.entertainment = 10.0
	j.mental = 10.0
	j.food = 80.0
	j.money = 80.0
	var picked = j._best_replenish_safe("entertainment", "afternoon")
	if picked == "":
		fail.append("effect_max: 期望ent活动 得空")
	else:
		var ent_eff = float(j.list_of_activities[picked]["effects"].get("entertainment", 0))
		if ent_eff != 10.0:
			fail.append("effect_max: 期望ent effect=10 得%s(eff=%.0f)" % [picked, ent_eff])
	var j2 = C.new(CFG)
	j2.entertainment = 10.0
	j2.food = 16.0
	j2.money = 80.0
	var picked2 = j2._best_replenish_safe("entertainment", "afternoon")
	if picked2 != "":
		var p2 = j2.list_of_activities[picked2]
		var dur2 = float(p2.get("duration_hours", 2.0))
		var food_after2 = float(j2.food) + (float(p2["effects"].get("food", 0)) - float(j2.food_decay)) * dur2
		if food_after2 < 15.0:
			fail.append("food_filter: 选%s 但 food_after=%.1f<15" % [picked2, food_after2])

# Task 4：L1.5 配额层——未达配额 + 守卫满足 → 强制补；守卫紧 → ""；配额满 → ""
func _test_pick_quota(fail: Array) -> void:
	var C = preload("res://Character_Class.gd")
	# ① ent owe（done=0<3）+ 守卫满足 → 返回 ent 正 effect 活动
	var j = C.new(CFG)
	j.entertainment_quota_done = 0.0
	j.physical_quota_done = 3.0
	j.food = 80.0
	j.money = 80.0
	var picked = j._pick_quota_activity("afternoon")
	var ents = int(j.list_of_activities[picked]["effects"].get("entertainment", 0)) if picked != "" else 0
	if ents <= 0:
		fail.append("force_ent: 期望ent活动 得%s(ent=%d)" % [picked, ents])
	# ② 守卫紧（food<35）→ 返回 ""
	var j2 = C.new(CFG)
	j2.entertainment_quota_done = 0.0
	j2.food = 30.0
	j2.money = 80.0
	if j2._pick_quota_activity("afternoon") != "":
		fail.append("guard_food: 期望'' 得%s" % j2._pick_quota_activity("afternoon"))
	# ③ 配额全满 → 返回 ""
	var j3 = C.new(CFG)
	j3.entertainment_quota_done = 3.0
	j3.physical_quota_done = 3.0
	j3.food = 80.0
	j3.money = 80.0
	if j3._pick_quota_activity("afternoon") != "":
		fail.append("quota_full: 期望'' 得%s" % j3._pick_quota_activity("afternoon"))
