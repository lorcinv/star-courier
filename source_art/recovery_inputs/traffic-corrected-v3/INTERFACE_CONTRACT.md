# 地面事件修正候选：窄接口契约

这是独立 helper 的集成参考。公共游戏求解器、主场景、航线、经济、输入时间线和渲染文件均未修改。碰撞结果在夹具中明确作为外部权威输入，helper 不求解碰撞，也不修改快递体。

## 版本与来源

本候选从原 v3 复制，只合入“死亡后同 tick 的新 revision 不得回到更早 fraction”修复。四个运行模块与此前补充修复的原生 PASS 源码逐字节相同；原 v2/v3 均保留。

私有快照标记仍为 `ground-traffic-candidate-v3-snapshot-1`。修复不改字段形状，合法 v3 快照保持可读；旧 v2 helper 形状和未知版本被拒绝。v2 helper 未出货，按当前约定不实现迁移。本标记未注册为游戏航线或重放协议。

原 v3 Library：`libfile_b990a85e246881918cbaa40afdde1e02`。补充修复 Library：`libfile_b4957b6398ec819191b3a3a2e2ce925d`。

## 唯一调用顺序

1. 新事件以明确 seed 调用 `Bundle.author(seed, Bundle.fresh_definition())`；存档路径使用 `Bundle.restore`，不能重新 author 或掷种子。
2. `Actor.configure(bundle)` 创建状态。120 Hz 的整数 tick 从 0 开始；`last_tick` 初值为 -1。时钟由调用方提供。
3. 每个启用 tick 先调用 `Actor.advance(state, tick, true, command)`。它使用之前已提交的运动决定预警、意图和资源预留。
4. 公共时间推进器负责实际力、碰撞与伤害。外部权威结果在当前 tick 中按 fraction 顺序交给 `Actor.rebase`。不要在 `advance` 之前偷用本 tick 将来的碰撞结果。
5. 分段查询、保存和恢复只使用下述接口。调用方接收返回的新 state；所有接口应保持传入 state 不变。

## 调用面

| 接口 | 输入 | 关键返回 |
| --- | --- | --- |
| `Bundle.author(seed, fresh)` | seed 为 0..2147483646；fresh 来自当前定义 | `ok, bundle` |
| `Bundle.restore(bundle)` | 已保存的真实生成结果 | `ok, bundle`；不重新生成位置 |
| `Actor.configure(bundle)` | 通过 bundle 校验的结果 | `ok, state` |
| `Actor.advance(state, tick, enabled, command)` | 连续整数 tick；严格 bool；命令见下文 | `ok, state, intents, inert` |
| `Actor.rebase(state, commit)` | 当前 tick 内的外部权威提交 | `ok, state, intents, inert` |
| `Actor.segment(state, actor_id, tick, from_fraction, to_fraction)` | 起止 fraction 为 binary64，0..1，且不早于保存 anchor | 当前保存线性段的 start/end、质量、半径和 HP；不求解接触 |
| `Actor.save_json(state)` / `load_json(text)` | 当前私有格式 | 带类型与 binary64 位模式的 JSON / 新 state |
| `Actor.restore_snapshot(value)` | 原生已保存状态 | `ok, state` 或具体 error |

`ok=false` 时不能使用不存在的 state/bundle 字段。物理标量要求有限 binary64；本地原生传参不要用 Vector2、StringName 或 typed Dictionary/Array。整数元数据允许合法整数值并规范化为整数；bool 不作整数使用。

合法重复 tick 或 `enabled=false` 不前进、不检查命令、不重复发出意图。tick 本身仍需合法；缺失/倒退的启用 tick 会失败。暂停后提交恰好下一个 tick。

命令精确为：

```text
{"warning_request": null 或 {"request_id": String, "target_x": float64, "target_y": float64},
 "cancel_warning": bool}
```

预警与取消不能同时请求。一次预警锁定起点、目标及方向，完整持续 180 个 tick 间隔（1.5 秒），不支持后续重定向。当前小切片只有一次预警，预算至多支持 60 次最低价意图；不是无限追逐。

## 外部提交与来源

commit 精确字段为 `actor_id, tick, fraction, revision, x, y, vx, vy, hp`。tick/revision/hp 是整数元数据，其余运动标量为 binary64。

- tick 必须等于当前 `last_tick`，revision 恰好增加 1，HP 不能回升。
- fraction 为 0..1，按保存 anchor 单调前进。fraction=1 的 anchor 规范到下一 tick 的 fraction=0；保存的原 commit 仍保留原 tick/fraction。
- 同一当前 tick 内，完全相同的重复 revision/commit 是惰性操作；相同 revision 的不同内容被拒绝。
- 外部提交只改变该演员的权威运动与 HP，不能顺便改写质量、半径、燃料或既有付款记录。
- 预警起点、每笔资源记录和结束决定保留当时使用的 revision/commit。死亡需对应 HP=0 的提交。死亡后的更高 revision 不得在同 tick 回到更早 fraction。
- 残骸和预算耗尽的演员继续存在。`segment` 仍可查询其保存线性运动；跨过终点、反向运动或死亡不触发隐式删除。

测试日志中的 `external/contact_A` 等名字属于夹具来源映射，不新增游戏存档字段。该校验拒绝内部矛盾的保存历史，不是对整份被重写存档的认证。

## 意图与资源交接

`actor_force_intent` 指向演员自身，带 actor_id/source_id/event_id/intent_id、tick、fraction 范围、fx_n/fy_n、`reserved_energy_mj` 及 `impulse_limit_ns`。当前最大力为 120 N、每 tick 冲量上限为 1 N·s。

资源数值是预留，不是实际施加功的回执。公共推进器仍需按接触时间切分、处理伤害/取消，在预留能量和冲量上限内执行。helper 没有第二套碰撞求解器、伤害求解器或快递体速度乘数。

最低预留为 1000 mJ；非零速度可能提高成本。超过剩余预算会发出取消通知，不扣费、不发力。死亡取消以后不再发新意图；保存体继续滑行。

## 有限夹具与验证边界

`reference_trace.gd` 是可读的完整驱动，直接调用真实 helper。主线含两次有限意图、两次外部接触提交、残骸查询、合法的同 tick 后续重基、快照恢复及下一步对照；另有独立拒付分支。

`fixtures/REFERENCE_INPUTS_TYPED.json` 是从已通过轨迹的精确已保存提交导出的输入表。`replay_reference_fixture.gd` 独立读取它，并与每阶段原生 golden 状态哈希比较。输入表及说明不是新游戏协议。

`TRACE_READABLE.md` 汇总阶段、资源与来源，并逐字段列出差异。float64 同时列出可读数值和 little-endian 位模式；`.qa/.../STAGE_*.json` 保留完整类型化快照，原始 stdout 也打印全部差异。

合法快照对照包含死亡 fraction=0、最小正 subnormal、0.75、紧邻 1 的较小浮点及 1，同刻较高 revision、后续 endpoint、下一 tick fraction=0，以及主动取消后的伤害。修正前后均应接受这些由 API 正常生成的快照；已知非法倒退仍应仅被修正版拒绝。

360m 几何示例仅检查初始圆形演员和半径 1m 的参考快递体：绕行线 `(20,-8)→(98,-20)→(150,-20)→(170,-8)→(340,-8)` 的最小额外间距为 3.75m。最后一段已位于所有初始圆形演员之后。图仅为技术示意，不是最终美术或游戏演示。未加载最新世界碰撞器，未证明运动过程中或真实组装飞船的可绕行性，未假设地板。

## 云端独立复核（用户转发）

云端反馈补充修正版在 Godot 4.6.3 通过来源 85、基础 149、压力 202，以及三个新进程各 9 项回放，合计六进程 463 项，无诊断；回放与 Windows golden 一致。转发的八文件树摘要为 `c9e1a5047fe5610674a15e6c16b51c8990181fbb9d6d60cbf9cfabbcf7ae3e7b`。此段是云端反馈，不冒充本次本机执行或完整游戏基准；本次本机原始结果另存于 `.qa`。
