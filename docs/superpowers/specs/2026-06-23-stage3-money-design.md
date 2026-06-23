# 阶段 3 设计：money 需求 + working_overtime 触发

- 日期：2026-06-23
- 项目：Character-Life-Simulator-in-Godot（模拟人生复刻）
- 状态：已实现（implemented 2026-06-23；标定微调 D=2+E=20，集成 work 2 次/3 天）
- 上游路径：`D:\GitHub\Character-Life-Simulator-in-Godot`
- 前置：阶段 1 时间系统 + 阶段 2 utility per_hour 净模型（已实现，commit c8a2d33）

## 1. 目标

引入 money 第 8 个 need，给 working_overtime 加 money 正 effect，让其 net utility 在 jane 缺钱时转正、被自主 AI 选中。完成 = working_overtime 在 3 游戏天内至少被选 1 次（money 赚-耗循环成立），且阶段 1/2 节律不回归。

## 2. 背景（阶段 2 暴露的遗留）

阶段 2 utility 改 per_hour 净模型后，working_overtime utility = **−44**（mental −10 + physical −14 + food −20，各 need=50），全负 effect → net 恒负 → 自主 AI 永不选（spec §9 已知限制）。要触发需引入正需求抵消——money 是最直接的"工作回报"。

## 3. 已定决策

| 抉择 | 决定 | 理由 |
|---|---|---|
| 范围 | 最小：money need + working_overtime 给钱 | 消费/经济体系留后续（YAGNI），先达成核心（working_overtime 被选） |
| money 建模 | 第 8 个 need（max/decay/initial） | 复用现有 need 机制（utility/decay/clamp），无需新框架 |
| money 用途 | decay=日常开销，working_overtime 补 | 不改其他活动（消费扣钱留后续） |
| money GUI | 加 MoneyLabel | money 不可见无法观察循环 |
| 标定 | decay 2/h、effect 20/h（v1 微调：D=3 卡 0/100，D=2+E=20 满足 E≈10D 平衡律） | 集成验证 work 2 次/3 天、money 2-100 流动 |

## 4. 架构

### 4.1 Character_Class.gd

新增状态（与现有 7 need 同构）：
- `var money_max` / `var money_decay` / `var money`
- `_init` 从 config 读 `money_initial_max` / `money_initial_decay`，`money = round(money_max / 2)`
- `tick` 加 `_decay_need("money", hours)`
- `working_overtime` effects 加 `"money": 20`

utility 计算自动覆盖 money（`calculate_utility` 遍历 `effects.keys()`，money 作为 need 有 `_max`/`_decay`）。

### 4.2 Main.gd

- `jane_config_dict` 加 `"money_initial_max": 100, "money_initial_decay": 2`
- `_ready` 加 `money_label = get_node("MoneyLabel")`
- `update_gui` 加 `money_label.text = "Money: " + str(int(jane.money))`

### 4.3 node_2d.tscn

加 MoneyLabel（type=Label，排在现有 Label 下方，offset_top 接 MentalLabel/ActivityLabel 区域）。

## 5. 标定 + 复算

**money need**：`money_max=100`、`money_initial=50`、`money_decay=2/h`（~25h 从 50 耗尽）。

**working_overtime 加 money +20/h**（per_hour 毛值）：

```gdscript
"working_overtime": {"effects": {"mental": -3, "physical": -4, "food": -5, "money": 20}, "duration_hours": 4, "allowed_during": ["morning", "afternoon"]}
```

**net utility 复算**（per_hour 净模型，money=m，其他 need=50）：
- mental: `clamp(50+(−3−2)×4,0,100)−50 = −20` × urgency 0.5 = **−10**
- physical: `clamp(50+(−4−3)×4,0,100)−50 = −28` × 0.5 = **−14**
- food: `clamp(50+(−5−5)×4,0,100)−50 = −40` × 0.5 = **−20**
- money: `clamp(m+(20−2)×4,0,100)−m` × `(100−m)/100`
  - m=20: 72 × 0.8 = **57.6** → total = −44+57.6 = **+13.6**（缺钱工作）
  - m=50: 50 × 0.5 = 25 → total = **−19**（钱够不工作）
  - 阈值 ~m=35

**被选条件**：working_overtime 在 jane 其他基本需求较高（sleep/food/... 的 utility 低）+ money 低时，成为最高 utility 活动。例：food=80、money=20 时 working +22.4 > eating +5.5（food=80 时 eating utility 因 food 高而低）。

**自调节循环**：money decay（2/h）→ 缺钱 → working_overtime（4h 赚 net 72）→ 钱回升 + mental/physical/food 跌 → 转补 sleep/food/exercise → 基本需求满 → money 又低 → 再工作。jane 约 1–2 天工作一次。

## 6. 影响范围

| 文件 | 动作 |
|---|---|
| `Character_Class.gd` | 加 money 变量 + _init + tick decay + working_overtime effect |
| `Main.gd` | config + GUI money_label |
| `node_2d.tscn` | 加 MoneyLabel |
| TimeManager / project.godot / 其他 30 个活动 / decay 值 | 不动 |
| `calculate_utility` / `select_best_activity` / `tick` 逻辑 | 不动（自动覆盖 money） |

## 7. 测试（execute_gdscript + run_and_verify）

**单元**：
- money need 机制：money=50, tick 推 1h → money=50−2×1=48（decay）；working_overtime effect money +20/h × actual
- working_overtime utility：money=20 时 net ≈ **+13.6**（±0.1，锁标定）、money=50 时 net = **−19**（数值断言；"不被选"由集成 n≥1 覆盖）
- money clamp：money=95 + working 4h effect → 不超 100

**集成**（3 游戏天）：
- working_overtime 被选次数 **1 ≤ n ≤ 6**（下限验 money 循环成立，上限验节律不退化——§9 economy 不平衡风险量化）
- night sleeping ≥ 80%（阶段 1/2 不回归）
- food 不连续 ≥ 6h 跌零（不回归）
- money 不卡 0 也不卡 100（循环流动）：money_zero_run < 6h 且 money_full_run < 6h（连续边界 <6h；瞬时触顶 100 是 work clamp，非"卡"）

**回归**：run_and_verify hasErrors=false。

## 8. 完成标准（Done）

1. money 第 8 need 加入（max/decay/initial + tick decay）
2. working_overtime effects 含 money +20/h
3. working_overtime 在 money 低时 net utility 正（单元断言）
4. 3 游戏天 working_overtime 被选 1-6 次（集成，与 §7 一致）
5. night sleeping ≥ 80%、food 跌零不回归
6. GUI MoneyLabel 显示 money
7. run_and_verify 零错误

## 9. 已知限制（阶段 3 不处理）

- **money 只赚（working_overtime）不主动花**：decay=2/h 代表日常开销，但无消费活动扣钱（eating_out/shopping 不扣 money）。留后续阶段加消费 effect。**注**：money decay 全天候（sleeping 8h 也掉 16），已在每日 48 预算内，非 bug
- **标定 v1 微调记录**：原 proposal decay 3 / effect 20，集成测试 D=3 卡 0/100（work 单次赚 (20−3)×4=68 超 money 余量、decay 太快），调为 decay 2 / effect 20（E≈10D 平衡律，work 单次赚 72、money 在 2-100 流动、full_run=1h）。后续若 jane 行为漂移再调
- **无收入分级/职业**：working_overtime 是唯一赚钱活动（固定 +20/h）。多种工作/收入分级留后续
- **money economy 不平衡风险**：若 decay/effect 标定不当，jane 可能陷入"只工作"或"从不工作"。集成测试 working_overtime 次数（1–6 次/3 天为合理区间）兜底
