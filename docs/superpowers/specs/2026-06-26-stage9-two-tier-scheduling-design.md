# 阶段 9 设计：双层调度（survival 强制 + 品质 deficit 轮换 + utility 三层 select）

- 日期：2026-06-26
- 项目：Character-Life-Simulator-in-Godot（模拟人生复刻）
- 状态：已实现（事后归档 2026-06-28；探索性 TDD 实现，main `a282c5f`）
- 上游路径：`D:\GitHub\Character-Life-Simulator-in-Godot`
- 前置：阶段 8 need deficit 加成（已实现，`DEFICIT_WEIGHT=0.5`；spec §9.4 记 ent/phys avg 低，本阶段深挖根因）
- 调查方法：superpowers:systematic-debugging（根因实证 + 架构天花板判定 Phase 4.5）+ 探索性 TDD（v1/v2/双层迭代）

## 1. 目标

回应看板①：stage8 留的「ent/phys **avg 低**、deficit 弱效」。查明 deficit 为何弱效，给 jane 的单步贪心 select 加 **双层调度**，在不回归 stage1-8 任何硬指标前提下提升 ent/phys。

完成 = 4/5 硬指标达标（night sleeping ≥ 0.8、food_zero < 6h、money_zero < 6h、消费 kinds ≥ 2），且 ent/phys 较 stage8 改善。**注：ent/phys avg ≥ 30 健康线最终判定为单步贪心架构天花板，见 §9.4。**

## 2. 背景（根因实证 — 超 stage8 §9.4 认知）

stage8 §9.4 推测「deficit 弱效」。本阶段实证根因：

1. **deficit 不弱**：实测 jane 72h 累计 deficit 涨到 28~33，加成 14~16（`DEFICIT_WEIGHT=0.5`），机制正常工作。
2. **真根因 = max-choose「永远的第二名」**：单步贪心每步选 utility #1，而 #1 几乎总被 food 刚需（`eating_out`）占着。food 扫描实证：`playing_sports` utility 恒 36.2，`eating_out` 随 food 从 57 跌到 21，**仅当 food ≥ ~70 时 ent/phys 活动才反超**；但 food decay 5/h，jane 的 food 长期在 20~50 刚需区 → ent/phys 永远是 #2，#2 在 argmax 里永远上不了位。
3. **结论**：deficit 加成（stage8）只是把品质活动的 utility 抬高，但抬高后仍争不过 food 刚需 #1。要让品质活动上位，必须 **绕过 utility 比较**，在 select 里加一个「强制补给」层。

## 3. 已定决策（探索性 TDD 事后归纳）

| 抉择 | 决定 | 理由 |
|---|---|---|
| 机制 | 双层调度：L1 survival 强制 + L2 品质 deficit 轮换 + L3 utility 兜底 | 绕过 max-choose（强制层不看 argmax）；L1 守硬约束、L2 补品质、L3 保留 utility 净模型 |
| L1 触发线 | food<25→补 food / money<15→work / night+sleep<30→sleeping | survival 硬约束（治 v2 night 崩 + 强化 food/money/sleep） |
| L2 触发 | deficit > 15（`FORCE_DEFICIT_THRESHOLD`）的品质 need 强制补给 | 打破「永远的第二名」；阈值 15 经实测（deficit 累计 28~33 区间，15 为品质层介入点） |
| L2 轮换 | 最大 deficit need == `last_forced_need` 时换第二个超阈 need | 治 phys 永远轮不到（ent 常年 deficit 最高独占） |
| L2 守卫 | food ≥ 35 + money ≥ 20 + food 预算过滤（food_after ≥ 15） | v1 崩 food 教训：长活动锁定期间 food 照样 decay 跌穿 |
| 流程 | 探索 TDD 未走 spec/plan（项目惯例偏离），本文件事后归档补回 | 详见 §9.1 |

## 4. 架构

### 4.1 新增成员/const（`Character_Class.gd`）

```gdscript
var last_forced_need: String = ""   # stage9 v2 轮换：上次硬触发补的 need，本次优先换一个
const FORCE_DEFICIT_THRESHOLD: float = 15.0   # stage9：品质 need deficit 超此值强制补给，打破 max-choose「永远的第二名」
```

### 4.2 新增 helper

- `_commit_activity(act_name)`：统一 commit（`current_activity` / `activity_recency[act]=1.0` / `remaining_hours` 钳到 day_part 剩余 / `is_busy=true`）。把三层共有的尾部重构为一个函数。
- `_best_replenish(need_name, day_part)`：该 need 正 effect 活动里 `calculate_utility` 最高的（供 L1 survival 用）。

### 4.3 `select_best_activity` 三层结构

```gdscript
func select_best_activity(day_part: String) -> void:
	# L1 survival 强制：刚需优先于品质/utility（治 v2 night 崩 + 强化 food/money/sleep）
	var surv := _pick_survival_activity(day_part)
	if surv != "":
		_commit_activity(surv)
		return
	# L2 品质 deficit 轮换：找 deficit 最大且超阈的品质 need → last_forced_need 轮换
	#   → survival 守卫(food>=35 / money>=20) + food 预算过滤(food_after>=15) → 选该 need 正 effect 活动 → _commit_activity
	#   （绕过 argmax，强制补给打破「永远的第二名」）
	# ...（命中则 commit 并 return）
	# L3 utility 兜底：原 select（recency 罚 + stage8 deficit 加成，argmax）
	# ...
```

### 4.4 L1 `_pick_survival_activity`

```gdscript
func _pick_survival_activity(day_part: String) -> String:
	if food < 25.0:
		return _best_replenish("food", day_part)
	if money < 15.0:
		if get_activities(day_part, Name_of_character).has("working_overtime"):
			return "working_overtime"
	if day_part == "night" and sleep < 30.0:
		return "sleeping"
	return ""
```

### 4.5 不动

`calculate_utility`（瞬时净效用语义）、tick 的 decay/deficit 更新/effects/busy、活动表、TimeManager、stage8 的 5 个 deficit const（`DEFICIT_WEIGHT=0.5`）、stage7 money 处理、Main、node_2d.tscn。L3 兜底层保留 stage8 的 deficit 加成。

## 5. 影响范围

| 文件 | 动作 |
|---|---|
| `Character_Class.gd` | + `last_forced_need` + `FORCE_DEFICIT_THRESHOLD` + `_commit_activity` + `_best_replenish` + `_pick_survival_activity`；`select_best_activity` 改三层 |
| calculate_utility / 活动表 / TimeManager / Main / 场景 / stage7-8 处理 | 不动 |

## 6. 测试（run_and_verify + 入树脚本，非 execute_gdscript）

- **单元**（`test/stage9_test.tscn`，T1-T5）：L1 触发线、L2 阈值触发、L2 轮换、L2 守卫过滤、L3 兜底。
- **集成**（`test/exp.tscn`，72h）：night sleeping、food_zero、mz、kinds、ent/phys avg。
- **回归**：`run_and_verify` hasErrors=false。

> 测试改入树脚本的原因（execute_gdscript 非确定）见 §9.2。

## 7. 完成标准（Done）

1. L1/L2/L3 三层 + 2 helper + `last_forced_need` + `FORCE_DEFICIT_THRESHOLD` 实现
2. 集成 4/5 硬指标达标（night ≥ 0.8 / food_zero < 6h / mz < 6h / kinds ≥ 2）
3. ent/phys 较 stage8 改善（phys avg 5.3 → 6.9）
4. `run_and_verify` 零错误
5. 看板①推进 / 关闭

## 8. 已知限制（本阶段不处理）

- **ent/phys avg 仍低（7~8）**：单步贪心架构天花板，见 §9.4。
- `FORCE_DEFICIT_THRESHOLD=15` / L1 触发线 25/15/30 / L2 守卫 35/20 为 v1 实测值，行为漂移再调。
- L2 强制绕过 argmax，会偶尔选 utility 偏低但补品质对的活动（设计如此，trade-off：补品质优先于瞬时净效用）。

## 9. 实现记录（2026-06-26 实测 + 2026-06-28 归档）

### 9.1 流程偏离（事后归档说明）

stage9 走 **探索性 TDD**：先 systematic-debugging 查根因（§2 实证），再 v1→v2→双层迭代（§9.3），每版 `run_and_verify` 验证。**未走 spec/plan 事前流程**（项目惯例每 stage 一 spec/plan，本次偏离）。本文件为 2026-06-28 事后补档。

### 9.2 测试现实（execute_gdscript 非确定，沿用 stage8 §9.2）

Character_Class extends Node 不入树，execute_gdscript 属性/字典访问非确定（Godot 4.7 bug：同帧多次读同属性/字典 key 返回不同值）。改用 `run_and_verify` + **入树脚本**（`exp.tscn`/`exp.gd`、`stage9_test.tscn`/`stage9_test.gd` 挂 `extends Node`，项目正式上下文，autoload 注册、Character_Class 能编译、属性访问 deterministic），`get_tree().quit()` 正常退出。leaked-object 警告是 quit 提前退出所致，无害。

### 9.3 三版实证（systematic-debugging Phase 4.5 架构迭代）

| 版本 | 机制 | 结果 | 崩点 |
|---|---|---|---|
| v1 | 单维硬触发（food<25 补 food / 最大 deficit need 强制） | food_zero=9 崩 | survival 守卫只看决策点，长活动（party 3h）锁定期间 food 照 decay 跌穿；单维只补最大 deficit need，phys 永远轮不到 |
| v2 | +轮换（`last_forced_need`）+ food 预算过滤 | night sleeping 15/24 崩 | 轮换不区分时段，night 时 sleep 被「轮换」掉选了 gym/party，破坏 stage1-2 night 硬指标 |
| 双层 | L1 survival 强制（含 night sleep）+ L2 品质轮换（含守卫）+ L3 utility | night 22/24、food_zero=0、mz=2、kinds=3（4/5 达标）、phys avg 5.3→6.9 | — |

「治一处崩一处」（v1 food → v2 night）= systematic-debugging Phase 4.5「架构病信号」（each fix reveals new problem in different place）→ 停止堆 fix，转双层架构（L1 把 survival 提为显式硬约束层，优先于品质/utility）。

### 9.4 架构天花板（回应看板① — 本阶段最重要结论）

双层调度稳住全部硬指标且 phys 改善，**但 ent/phys avg 仍 7~8，远低于 stage8 §7 的 ≥30 健康线**。根因（§2 已钉死）：survival（food/money/sleep）占满时间预算 + 品质活动 effect 弱，**单步贪心（即使加双层强制层）在时间预算内补不到 ent/phys 健康线**。要真正健康需 **多步规划/全局优化**（如「今天预留 N h 给品质」配额），超 stage9 + 本学习 fork 范围。

**结论**：stage9 双层调度是稳定改进（4/5 硬指标达标 + phys 改善），建议保留；ent/phys avg ≥ 30 留作已知天花板，留待 stage10+ 候选（多步规划）。

### 9.5 附：UI 可视化（同会话附加工作，非双层调度核心）

stage9 会话顺带做了 UI 两档（commit 在 a282c5f 之后）：
- 档位1（`d8a4490`）：need Label → ProgressBar + 红黄绿（<30/<60/≥60）+ `NEEDS` 配置驱动 `update_gui` 循环。
- 档位2（`a8efa29`）：左右布局 + 右侧角色舞台（`CharacterStage` Panel：活动→颜色映射 sleep紫/eat绿/work蓝/运动橙/社交黄 + 任 need<30 疲惫变灰，`ColorRect` 占位可替换真 sprite）。

`run_and_verify` 零错，中文默认字体正常。本附记仅为完整性，不属双层调度机制。
