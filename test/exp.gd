extends Node

# stage10 集成：72h（3 完整天，game_minutes 真实累加跨天），验证 L1.5 配额执行率 + ent/phys avg 较 stage9 基线提升 + 不回归
# stage9 基线: ent avg=7.4 | phys avg=5.3 | night sleeping 22/24 | kinds 2 | mz 0 food_zero 0

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
	var night_acts = {}
	var spend_acts = {}
	var spend_set = {"eating_out":1,"grocery_shopping":1,"going_to_the_gym":1,"socializing_at_cafe":1,"watching_movie":1,"going_to_doctor":1,"playing_sports":1,"going_to_a_concert":1,"online_shopping":1,"playing_video_games":1,"going_to_a_museum":1,"going_to_the_beach":1,"visiting_a_spa":1,"going_fishing":1,"going_to_a_party":1}
	var mz = 0
	var mz_cur = 0
	var food_zero = 0
	var fz_cur = 0
	# 配额执行率：每天结束时记录 done，3 天平均 / target(3.0)
	var ent_done_sum = 0.0
	var phys_done_sum = 0.0
	var prev_day = -1
	var days = 0
	TimeManager.game_minutes = 0.0    # 第0天 0:00 起步（3 完整天：day0/1/2）
	for tick in range(72):
		var h = int(floor(TimeManager.game_minutes / 60.0)) % 24
		var dp = day_part(h)
		var d = TimeManager.get_day()
		if d != prev_day:
			if prev_day != -1:
				ent_done_sum += jane.entertainment_quota_done
				phys_done_sum += jane.physical_quota_done
				days += 1
			prev_day = d
		jane.tick(60.0, dp)
		var e = float(jane.entertainment)
		var p = float(jane.physical)
		ent_sum += e
		phys_sum += p
		n += 1
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
		TimeManager.game_minutes += 60.0
	# 补最后一天（day2）的 done
	ent_done_sum += jane.entertainment_quota_done
	phys_done_sum += jane.physical_quota_done
	days += 1
	var ent_avg = ent_sum / n
	var phys_avg = phys_sum / n
	var night_sleeping = night_acts.get("sleeping", 0)
	var night_total = 0
	for k in night_acts:
		night_total += night_acts[k]
	var night_ratio = float(night_sleeping) / max(1, night_total)
	var ent_exec = (ent_done_sum / days) / 3.0
	var phys_exec = (phys_done_sum / days) / 3.0
	var fail = []
	if ent_exec < 0.8:
		fail.append("ent_exec=%.0f%%<80" % (ent_exec * 100))
	if phys_exec < 0.8:
		fail.append("phys_exec=%.0f%%<80" % (phys_exec * 100))
	if ent_avg < 7.4:
		fail.append("ent_avg=%.1f 未较stage9基线7.4提升" % ent_avg)
	if phys_avg < 5.3:
		fail.append("phys_avg=%.1f 未较stage9基线5.3提升" % phys_avg)
	if mz >= 6:
		fail.append("mz=%dh>=6" % mz)
	if food_zero >= 6:
		fail.append("food_zero=%dh>=6" % food_zero)
	if night_ratio < 0.8:
		fail.append("night=%.2f<0.8" % night_ratio)
	if spend_acts.size() < 2:
		fail.append("kinds=%d<2" % spend_acts.size())
	print("=== STAGE10 72h ===")
	print("ent[avg=%.1f exec=%.0f%%] phys[avg=%.1f exec=%.0f%%]" % [ent_avg, ent_exec * 100, phys_avg, phys_exec * 100])
	print("night sleeping=%d/%d ratio=%.2f kinds=%d" % [night_sleeping, night_total, night_ratio, spend_acts.size()])
	print("mz=%dh food_zero=%dh money_last=%.0f" % [mz, food_zero, jane.money])
	if fail.is_empty():
		print("STAGE10 PASS")
	else:
		print("STAGE10 FAIL " + str(fail))
	get_tree().quit()
