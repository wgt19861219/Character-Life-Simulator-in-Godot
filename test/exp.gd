extends Node

# stage9 集成验证：72h 统计，对比 stage8 baseline。
# baseline(stage8): ent avg=7.4 last=18 | phys avg=5.3 last=0 | night 22/24 | kinds 2 | mz 0 food_zero 0

func day_part(h):
	if h >= 22 or h < 6:
		return "night"
	if h < 12:
		return "morning"
	if h < 18:
		return "afternoon"
	return "evening"

func _ready():
	var cfg = {
		"character_name":"Jane","sleep_initial_max":100,"food_initial_max":100,
		"entertainment_initial_max":100,"social_initial_max":100,"health_initial_max":100,
		"physical_initial_max":100,"mental_initial_max":100,"money_initial_max":100,
		"sleep_initial_decay":6,"food_initial_decay":5,"entertainment_initial_decay":4,
		"social_initial_decay":3,"health_initial_decay":1,"physical_initial_decay":3,
		"mental_initial_decay":2,"money_initial_decay":1.5
	}
	var jane = Character_Class.new(cfg)
	var ent_sum = 0.0
	var phys_sum = 0.0
	var n = 0
	var ent_last = 0.0
	var phys_last = 0.0
	var night_acts = {}
	var spend_acts = {}
	var spend_set = {"eating_out":1,"grocery_shopping":1,"going_to_the_gym":1,"socializing_at_cafe":1,"watching_movie":1,"going_to_doctor":1,"playing_sports":1,"going_to_a_concert":1,"online_shopping":1,"playing_video_games":1,"going_to_a_museum":1,"going_to_the_beach":1,"visiting_a_spa":1,"going_fishing":1,"going_to_a_party":1}
	var mz = 0
	var mz_cur = 0
	var food_zero = 0
	var fz_cur = 0
	for tick in range(72):
		var h = tick % 24
		TimeManager.game_minutes = float(h * 60)
		var dp = day_part(h)
		jane.tick(60.0, dp)
		var e = float(jane.entertainment)
		var p = float(jane.physical)
		ent_sum += e
		phys_sum += p
		n += 1
		ent_last = e
		phys_last = p
		var ca = str(jane.current_activity)
		if dp == "night":
			night_acts[ca] = night_acts.get(ca, 0) + 1
		if spend_set.has(ca):
			spend_acts[ca] = spend_acts.get(ca, 0) + 1
		if jane.money <= 0.0:
			mz_cur += 1
		else:
			mz_cur = 0
		mz = max(mz, mz_cur)
		if jane.food <= 0.0:
			fz_cur += 1
		else:
			fz_cur = 0
		food_zero = max(food_zero, fz_cur)
	print("=== STAGE9 72h ===")
	print("ent_avg=%.1f ent_last=%.1f" % [ent_sum / n, ent_last])
	print("phys_avg=%.1f phys_last=%.1f" % [phys_sum / n, phys_last])
	print("night_acts=", night_acts)
	print("spend_kinds=", spend_acts.keys(), "count=", spend_acts.size())
	print("mz_longest=", mz, "food_zero_longest=", food_zero, "money_last=", jane.money)
	get_tree().quit()
