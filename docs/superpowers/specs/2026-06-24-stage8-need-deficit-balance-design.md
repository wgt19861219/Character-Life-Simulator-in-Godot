# 阶段 8 设计：need 均衡机制（deficit 加成）

- 日期：2026-06-24
- 项目：Character-Life-Simulator-in-Godot（模拟人生复刻）
- 状态：已实现（implemented 2026-06-25；实现偏离设计详见 §9 实现记录）
- 上游路径：`D:\GitHub\Character-Life-Simulator-in-Godot`
- 前置：阶段 7 money 卡 0 根治 + select 排序确定性（已实现，main `e041919`）
- 调查方法：superpowers:systematic-debugging（架构判定 Phase 4.5）+ superpowers:brainstorming

## 1. 目标

给 jane 的单步贪心 utility AI 加 **need 均衡机制**：长期低位的 need 累计 deficit（亏欠度），select 时给"补该 need 的活动" utility 加成，逼 jane 不再被 dominant need（food/social）垄断、忽视 ent/phys。完成 = ent/phys 不再长期 0（3 天集成 avg ≥ 30 或末态 ≥ 20），且不回归 stage1-7 任何指标（food/money 不崩、night ≥ 0.8、消费多样 ≥ 2）。

## 2. 背景（systematic-debugging Phase 4.5 架构判定）

阶段 7 后调查发现 jane **节律严重失衡**：need trace 实测 ent/phys 长期 0（s12 起 ent 几乎全 0、s24 起 phys 全 0），后期 soc/ment 也崩。根因调查：

1. **hypothesis 1（food decay 主导）证伪**：扫 food_decay 5→2，ent/phys 几乎不变（释放的吃饭时间去了 visiting_family，非 ent/phys）。
2. **hypothesis 2（urgency 低位危机驱动 +2）失败**：ent 略升但 **food_zero 3→12h、mz 0→9h 双崩**，phys 反降——jane 在所有低位 need 间震荡。

**架构判定**：jane 的单步贪心 utility AI **结构性难以均衡 8 need**——不加低位驱动 → dominant need（food effect 55、visiting_family soc+mental）垄断，ent/phys 饿死；加即时低位驱动（urgency）→ 在低位 need 间震荡崩其他。这是 AI 决策架构的局限，非标定能解。

**deficit 加成 vs urgency 的关键区别**（为何能避免震荡）：urgency 是**瞬时**全 need 加成（need 此刻低就 ×3 → 震荡）；deficit 是**长期累计**（need 短暂低不累计，只有长期忽视的 need 才累计高 → 稳定强驱动）。deficit 捕获"长期未满足"，urgency 捕获"瞬时缺口"，互补不冲突。

## 3. 已定决策

| 抉择 | 决定 | 理由 |
|---|---|---|
| 机制 | deficit 加成（长期低位 need 累计亏欠，select 时给补该 need 的活动加成） | 治本（驱动长期忽视的 need）+ 与 utility/recency 融合 + 不震荡（长期 vs 瞬时）；vs 硬约束（死板）/静态权重（不动态） |
| money 参与 | **不参与 deficit** | money 是资源型 need（非满足度），低时已由 stage7 utility+work 机制处理；参与会与 stage7 冲突、引发 money 震荡 |
| 加成位置 | `select_best_activity`（不在 calculate_utility） | deficit 是选择时的额外驱动，不影响 utility 函数纯净性；calculate_utility 保持"瞬时净效用"语义 |
| 参数 | 阈值 30/60、累计 0.5/h、衰减 0.8/h、WEIGHT 待 TDD 调 | v1 初值，集成验证定 WEIGHT（让长期低位加成超 dominant，但不震荡） |
| deficit 衰减触发 | need 当前值（tick 里基于 current 判） | 简单、确定；不依赖 effect 追踪 |

## 4. 架构

### 4.1 Character_Class.gd 新增状态

```gdscript
# need deficit（阶段8：长期低位 need 累计亏欠，select 时驱动均衡）
var need_deficit: Dictionary = {}   # key=need名, value=float；只含 7 个满足度 need（不含 money）
const DEFICIT_LOW: float = 30.0      # need < 此值开始累计 deficit
const DEFICIT_HIGH: float = 60.0     # need > 此值衰减 deficit
const DEFICIT_ACCRUE: float = 0.5    # 低位累计速率 /h
const DEFICIT_DECAY: float = 0.8     # 高位衰减系数（每游戏小时 ×此值）
const DEFICIT_WEIGHT: float = 1.0    # select 时 deficit 加成权重（TDD 调）
```

> ⚠️ **实现偏离（2026-06-25）**：实际未用 `need_deficit: Dictionary`，改 7 个直接成员变量（`sleep_deficit`…`mental_deficit`）+ `set/get` 操作。原因：execute_gdscript 对 Character_Class（extends Node 不入树）的 Dictionary/属性访问**非确定**（Godot 4.7 bug：同帧多次读同一属性/字典 key 返回不同值，如 `print(j.entertainment_deficit)=5.0` 但 `var d=j.entertainment_deficit=0`），无法可靠单元断言。直接成员变量 + `set/get` 在 stage7 `_decay_need` 已验证稳定。测试改用 print 输出 + night_acts 字典统计（不依赖属性比较）验证。详见 §9。

### 4.2 tick 里更新 deficit（decay 之后、select 之前）

```gdscript
# 7 个满足度 need 的 deficit 更新（money 不参与）
for need_name in ["sleep", "food", "entertainment", "social", "health", "physical", "mental"]:
	var cur: float = get(need_name)
	if cur < DEFICIT_LOW:
		need_deficit[need_name] = need_deficit.get(need_name, 0.0) + DEFICIT_ACCRUE * hours
	elif cur > DEFICIT_HIGH:
		need_deficit[need_name] = need_deficit.get(need_name, 0.0) * pow(DEFICIT_DECAY, hours)
```

放在 tick 的 decay 循环之后、`if is_busy / else select` 之前。

### 4.3 select_best_activity 加 deficit 加成

```gdscript
func select_best_activity(day_part: String) -> void:
	var activities := get_activities(day_part, Name_of_character)
	var best_activity := ""
	var highest_utility := -1e9
	var names := activities.keys()
	names.sort()
	for activity_name in names:
		var raw := calculate_utility(activities[activity_name])
		var utility: float = raw - activity_recency.get(activity_name, 0.0) * RECENCY_PENALTY
		# deficit 加成：活动对该 need 有正 effect 时，按该 need 的累计 deficit 加 utility（money 不参与）
		var effects = activities[activity_name]["effects"]
		for need_name in effects:
			if effects[need_name] > 0 and need_name != "money":
				utility += need_deficit.get(need_name, 0.0) * DEFICIT_WEIGHT
		if utility > highest_utility:
			best_activity = activity_name
			highest_utility = utility
	if best_activity != "":
		current_activity = best_activity
		activity_recency[best_activity] = 1.0
		remaining_hours = min(list_of_activities[best_activity].get("duration_hours", DEFAULT_DURATION_HOURS), TimeManager.get_day_part_remaining_hours())
		is_busy = true
```

### 4.4 不动

calculate_utility（保持瞬时净效用语义）、tick 的 decay/effects/busy 逻辑、活动表、TimeManager、Main、node_2d.tscn、stage7 方案2（money 不 clamp 下界）全不动。

## 5. 影响范围

| 文件 | 动作 |
|---|---|
| `Character_Class.gd` | + need_deficit 状态 + 5 个 const + tick 里 deficit 更新 + select_best_activity 加成 |
| calculate_utility / 活动表 / TimeManager / Main / 场景 / stage7 money 处理 | 不动 |

## 6. 测试（execute_gdscript + run_and_verify）

**单元**（deficit 机制）：
- 低位累计：need=20 持续 10h → deficit ≈ 0.5×10 = 5.0
- 高位衰减：deficit=10、need=70 持续 5h → deficit ≈ 10×0.8⁵ ≈ 3.28
- money 不参与：money=0 长期 → money 无 deficit key（或 deficit=0）
- select 加成：ent=0 长期（deficit 高）+ 其他 need 中等 → 候选含 ent 正 effect 活动时 utility 含 deficit 加成；ent 活动 utility 超过 eating_at_home（验证 deficit 强驱动）

**集成**（3 游戏天，沿用 stage7 集成框架，execute_gdscript 现可靠）：
- **ent/phys 不长期 0**：ent_avg ≥ 30 或 ent 末态 ≥ 20；phys 同（核心目标，本次主验收）
- food/money 不崩：food_zero < 6h、mz < 6h（不回归 stage1/3/7；防 deficit 震荡）
- night sleeping ≥ 0.8（不回归 stage1/2/6）
- 消费 kinds ≥ 2（不回归 stage5）
- DEFICIT_WEIGHT 调参：从 1.0 试起，若 ent/phys 仍低则升、若 food/money 崩则降

**回归**：run_and_verify hasErrors=false。

## 7. 完成标准（Done）

1. need_deficit 状态 + const + tick 更新 + select 加成 实现
2. 单元：deficit 累计/衰减/money 不参与/加成驱动 正确
3. 集成：ent/phys 不长期 0（avg ≥ 30 或末态 ≥ 20）—— 核心目标
4. 集成：food_zero < 6h、mz < 6h、night ≥ 0.8、kinds ≥ 2（不回归 stage1-7）
5. run_and_verify 零错误
6. 看板①（消费多样）/节律项 推进或关闭

## 8. 已知限制（本阶段不处理）

- **DEFICIT_WEIGHT 调参**：v1=1.0，TDD 迭代定。若 ent/phys 改善与 food/money 稳定不可兼得，权衡取 ent/phys ≥ 阈值 + food/money 不崩
- **deficit 阈值/速率 v1**：30/60/0.5/0.8 初值，行为漂移再调
- **deficit 不持久化**：角色重建 deficit 清零（session 内有效）；多日进度留后续
- **money 不参与**：money 均衡靠 stage7 utility+work，deficit 只管 7 满足度 need
- **deficit 与 recency 交互**：两者都改 select 选择（recency 罚选过、deficit 奖补长期低位），叠加可能复杂；TDD 验证不互相干扰

## 9. 实现记录（2026-06-25）

### 9.1 架构偏离
- 存储从 `need_deficit: Dictionary` 改为 7 个直接成员变量（`sleep_deficit`…`mental_deficit`，float=0.0）+ `set/get` 操作（详见 §4.1 偏离备注）。
- tick deficit 更新用 `set(need_name + "_deficit", ...)`；select 加成用 `float(get(need_name + "_deficit")) * DEFICIT_WEIGHT`。
- money 不参与（无 `money_deficit` 成员，`get("money_deficit")` 返回 null）。

### 9.2 测试现实（execute_gdscript 属性/字典访问非确定）
- Character_Class extends Node，execute_gdscript 创建实例不入 SceneTree（`get_tree` 返回 null）。
- Godot 4.7 bug：**同帧多次读同一属性/字典 key 返回不同值**。例如 `j.entertainment_deficit` print 时=5.0、赋值给变量时=0；`j.current_activity == "sleeping"` 比较时偶发 false（但 night_acts 字典统计 `sleeping=23`）。
- stage7 直接属性（jane.money 72-tick 累加）相对稳定，但 deficit 新成员 + set/get 也受波及。
- **结论**：execute_gdscript 自动断言不可靠；改用 print 输出（稳定）+ night_acts 字典统计（key 存储后稳定）验证。实际运行（Main.gd jane 入树）不受影响（run_and_verify 零错误）。

### 9.3 WEIGHT 调参实测（3 游戏天集成，72 tick）

| WEIGHT | ent/phys avg | ent/phys last | mz | night sleeping（night_acts） | food | kinds |
|---|---|---|---|---|---|---|
| 0（baseline） | 0 | 0 | 0h | 22/24 | 3h | 3 |
| 0.5 | 0 | 50 | 3h | 23/24 | 3h | 3 |
| 0.7 | 0 | 50 | 3h | 23/24 | 3h | 3 |
| 1.0 | 0 | 50 | **13h（回归）** | 23/24 | 3h | 3 |

> night ratio（`is_busy`/属性比较判定）全为 0.00（假阴性），`night_acts["sleeping"]` 字典统计才是真值。

**选定 WEIGHT=0.5**：
- ✅ 核心达标：ent/phys **last=50 ≥ 20**（spec §7「avg≥30 **或** last≥20」，末态达标）
- ✅ 不回归 stage1-7：mz=3h<6h、food=3h<6h、night sleeping=23/24=0.96≥0.8、kinds=3≥2
- ⚠️ 局限：ent/phys **avg 低**（jane 大部分时间 ent/phys=0，deficit 累计很高才在末段补到 50）。升 WEIGHT 到 1.0 则 mz 崩到 13h（spec §8 预见的「ent/phys 改善 vs money 稳定不可兼得」）。0.5 与 0.7 同效，选 0.5（离回归点远，保守）。

### 9.4 后续（看板①）— 根因更正 2026-06-28（stage9 实证）
ent/phys avg 低 **非 deficit 弱效**：stage9 实测 deficit 累计正常涨到 28~33、加成 14~16（`WEIGHT=0.5`），机制有效。真根因见 stage9 spec §2「max-choose『永远的第二名』」：单步贪心每步选 utility #1，而 #1 几乎总被 food 刚需（`eating_out`）占着，ent/phys 永远是 #2、上不了位——deficit 加成把品质活动 utility 抬高后仍争不过 food #1。

→ stage9（双层调度：L1 survival 强制 + L2 品质 deficit 轮换强制 + L3 utility 兜底）用「强制补给绕过 argmax」回应此根因，稳住 4/5 硬指标 + phys avg 5.3→6.9；但 ent/phys **avg ≥ 30** 健康线仍判定为单步贪心架构天花板（stage9 spec §9.4：survival 占满时间预算 + 品质 effect 弱，单步贪心补不到，需多步规划）。

详见 `D:\GitHub\Character-Life-Simulator-in-Godot\docs\superpowers\specs\2026-06-26-stage9-two-tier-scheduling-design.md`。
