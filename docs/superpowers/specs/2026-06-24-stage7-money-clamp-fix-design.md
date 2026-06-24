# 阶段 7 设计：money 卡 0 根治（非单调 DEFECT + work 时机）

- 日期：2026-06-24
- 项目：Character-Life-Simulator-in-Godot（模拟人生复刻）
- 状态：已实现（implemented 2026-06-24；方案2 money 项不 clamp 下界 + money_decay 2→1.5；mz 6h→0h 达标，sleeping night 确定性排名 72.8≫31.2 不回归，kinds=3/food=3h/money[4,82] 流动；work=7 略超 stage3(6)；execute_gdscript 非确定→select 健壮性记看板）
- 上游路径：`D:\GitHub\Character-Life-Simulator-in-Godot`
- 前置：阶段 6 bedtime 时段边界（已实现，main `8938bde`）
- 调查方法：superpowers:systematic-debugging（根因已实测确认）

## 1. 目标

根治 money 卡 0：3 游戏天集成测试 `money_zero_run < 6h`（阶段 3 §7 硬指标，阶段 6 后实测临界 6h），且不回归阶段 1-6 任何指标。完成 = money 周期流动不卡 0、非单调消除、night sleeping / 消费多样 / food 节律全不回归。

## 2. 背景（双根因，systematic-debugging 实测确认）

集成诊断（3 游戏天，每游戏小时 tick）：`money_min=0.00`，money 周期性触 0，`money_zero_run` 临界 6h。两个独立根因：

### 根因 A：`calculate_utility` 对 money 下界 clamp 非单调（核心 DEFECT `money-utility-clamp-nonmonotonic`）

stage2 把 `net_change = clamp(current + (effect_ph - decay_ph)*duration, 0, mx) - current` 用于所有 need。对 money（资源型，消费 effect 为负），当 `current + delta < 0` 时下界 clamp 把负变化截断 → money=0 时消费 `net_change = 0-0 = 0`，**惩罚归零**。

控制变量矩阵（其他 need=50，原 v1）：
```
activity          m=0    m=20   m=40   m=60   m=80
eating_out        28.0   16.8   19.6   22.4   25.2   ← U 形！m=0 最高（非单调）
going_to_a_party  19.5    3.5   -0.3    6.3   12.9   ← U 形！
working_overtime  28.0   13.6   -8.0  -28.0  -40.0   ← 单调（正常）
eating_at_home    26.5   26.5   26.5   26.5   26.5   ← 免费不随 money 变
```
分项实锤（eating_out）：m=0 时 `money(net0.0 * u1.0 = 0.0)`，m=60 时 `money(net-14 * u0.4 = -5.6)`。

**后果**：money=0 时 eating_out=28.0 反超免费 eating_at_home=26.5、与 work 持平 28.0 → 身无分文仍优先消费，且 work 仅持平、被 recency/need 波动压制就不选。溯源：stage2 clamp 净模型对满足度 need 合理；stage3 把 money 当第 8 need 复用同模型，当时"只赚不花"（§9）未暴露；stage4 加消费扣 money 后盲点显现。

### 根因 B：work 时机 + 时段限制

- `working_overtime` 的 `allowed_during = ["morning", "afternoon"]`，night/evening 无法 work 回血
- jane D0 开局先消费（playing_sports/party 等）把 money 跌低，work 触发阈值 ~money=35，等到 money 极低才 work
- money 在 evening 跌到 0 后，要等次日 morning 才能 work → night 段（22:00–06:00 约 8h）money 维持 0

两根因叠加 → money_zero_run 临界 6h。方案 2 修 A 不动 B，实测 money_zero_run 12h→6h（临界）。

## 3. 已定决策

| 抉择 | 决定 | 理由 |
|---|---|---|
| 根因 A 修法 | 方案 2：money 项 net_change 只 clamp 上界（`min`）不 clamp 下界 | 实测非单调消除、money 充足时行为不变（本就没触下界）→ 不破坏 stage2-6 标定；vs per_hour 重写（影响大）/ floor 惩罚（加魔法常数） |
| 根因 B 修法 | 标定优先（money_decay / work effect 微调），机制兜底（缺钱 work 加成） | 最小改动；标定试错在 plan TDD 环节迭代到 money_zero_run<6h；若标定不足再加机制 |
| money 区分 | 资源型 need（与满足度 need 不同构） | money 是购买力资源，消费是机会成本，触底不应抹惩罚信号 |
| 范围 | 一次修双根因 | 用户定；money_zero_run<6h 需 A+B 配合 |
| work_count=8 偏高 | 顺带观察，标定迭代中若自然回落到 1-6 则收，否则记看板 | stage3 目标 1-6，当前 8 是 stage4-6 累积；非本次硬目标 |

## 4. 架构

### 4.1 `Character_Class.calculate_utility` 改动（方案 2）

```gdscript
func calculate_utility(activity: Dictionary) -> float:
	var total_utility: float = 0.0
	var duration: float = activity.get("duration_hours", DEFAULT_DURATION_HOURS)
	for need in activity["effects"].keys():
		var effect_ph: float = activity["effects"][need]
		var decay_ph: float = get(str(need) + "_decay")
		var current: float = get(need)
		var mx: float = get(str(need) + "_max")
		# money 是资源型 need：消费负 effect 不被下界 clamp 抹掉（消除非单调），其余 need 维持 clamp 净模型
		var raw_change: float = current + (effect_ph - decay_ph) * duration
		var net_change: float = (min(raw_change, mx) if need == "money" else clamp(raw_change, 0.0, mx)) - current
		var urgency: float = float(mx - current) / float(mx)
		total_utility += net_change * urgency
	return total_utility
```

唯一改动：`net_change` 行——money 用 `min(raw, mx)`（只 clamp 上界防溢出），其余 need 维持 `clamp(raw, 0, mx)`。

### 4.2 work 时机（根因 B）—— 标定优先

候选（plan TDD 迭代选定，按改动从小到大）：
1. **`money_decay` 微调**（2 → 1.5 或 1）：money 跌慢，night 不易归零。影响：money 更充裕，可能 work_count 降
2. **`working_overtime` money effect 微调**（20 → 22-24）：单次赚更多，回血快。影响：work 频次可能降
3. **机制兜底**：`select_best_activity` 里 money < 阈值 T 时给 money-effect>0 活动 utility 加成（缺钱驱动 work）。仅当 1/2 达不到 money_zero_run<6h 时启用

验收驱动：money_zero_run<6h 且不破坏其他指标。具体参数 TDD 实测定。

### 4.3 不动

`tick` / `_apply_effects_hourly` / `_decay_need` / `select_best_activity` 主体（除非启用机制兜底）/ 活动表 effects（除非标定微调）/ 活动表结构 / TimeManager / Main / node_2d.tscn 不动。

## 5. 影响范围

| 文件 | 动作 |
|---|---|
| `Character_Class.gd` | 改 `calculate_utility`（net_change 行，方案 2）；若启用机制兜底则改 `select_best_activity` |
| `Main.gd` | （仅当选 decay/effect 标定）改 `jane_config_dict` 的 `money_initial_decay` |
| `Character_Class.gd` 活动表 | （仅当选 effect 标定）改 `working_overtime` money 值 |
| TimeManager / node_2d.tscn / 其他活动 / tick / effects / decay 机制 | 不动 |

## 6. 测试（execute_gdscript + run_and_verify）

**单元**（方案 2 非单调消除）：
- 控制变量矩阵：eating_out / party 的 utility **单调递增**随 money（m=0 最低，不再 U 形）；work / eating_at_home 不变
- money=0 时 eating_out utility < eating_at_home（免费压制花钱）；work utility ≥ eating_out
- 满足度 need（sleeping/eating_at_home）utility 与原 v1 完全一致（方案 2 只动 money，回归守护）

**集成**（3 游戏天，沿用 stage5/6 集成框架）：
- **money_zero_run < 6h**（硬指标，本次核心）
- money_max_full_run < 6h（不卡 100）、money 流动（min<50 且 max>50 出现）
- night sleeping ≥ 0.8（不回归 stage1/2/6；stage6 实测 0.92）
- 消费 kinds ≥ 2（不回归 stage5；stage6 实测 3）
- food_zero_run < 6h（不回归 stage1）
- work_count 1-8（观察，stage3 目标 1-6，当前 8）

**回归**：run_and_verify hasErrors=false。

## 7. 完成标准（Done）

1. `calculate_utility` money 项不 clamp 下界（方案 2），单元测试非单调消除 + 满足度 need 不变
2. work 时机标定（或机制）选定，money_zero_run < 6h
3. 集成全指标达标（money 流动、night sleeping、消费多样、food 不回归）
4. run_and_verify 零错误
5. DEFECT `money-utility-clamp-nonmonotonic` 关闭；看板待办②③推进

## 8. 已知限制（本阶段不处理）

- **work_count=8 偏高**：stage3 目标 1-6，当前 8。标定迭代中观察，若顺带回落则收，否则记看板（economy 调标定子项）
- **方案 2 只改 money 下界**：满足度 need 触底（如 food=0 时 eating 仍合理）维持原行为——满足度触底=完全不满足，clamp 语义正确，不需改
- **night 无法 work 是设计**：work 限制在 morning/afternoon 符合现实作息；靠白天攒钱保证 night 储备，不放宽时段
- **标定为 v1**：decay/effect 微调值经集成验证定，后续行为漂移再调
