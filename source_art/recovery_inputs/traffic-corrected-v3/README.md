# Corrected v3 ground-event integration reference

独立候选，已合入同 tick 死亡后残骸时间倒退校验修复。原 v2/v3 未修改，
本包未改公共游戏文件、未集成完整游戏，也未实现碰撞求解器。

先读 `INTERFACE_CONTRACT.md`，再读 `TRACE_READABLE.md` 的阶段表。
`GEOMETRY_REFERENCE.png` 是原生静态几何结果的技术示意，不是游戏美术。

## 内容

- 根目录四个 ground_*.gd 是修正运行模块，逐字节来自已通过的补充修复。
- `baseline_v3/` 是仅供合法快照对照的原 v3 模块，保留原缺口；不要用它集成。
- `reference_trace.gd` 是可读驱动：预警、两次有限意图、外部接触提交、残骸
  滑行、合法后续重基、保存恢复与独立拒付分支；逐字段打印 binary64 精确差异。
- `fixtures/REFERENCE_INPUTS_TYPED.json` 保存精确可重放输入；旁边 READABLE
  文件供阅读。`replay_reference_fixture.gd` 独立消费输入并核对原生 golden。
- `.qa/attempt-20261011T055248457939Z/` 保存主轨迹全部原始日志、精确快照、
  几何数据、合法恢复对照，以及准确源码快照。
- `.qa/fixture-20261011T060336103532Z/` 保存独立夹具入口的原始日志及准确源码。
- `CORRECTION_FROM_UPLOADED_V3.diff` 是已在本候选合入的唯一运行模块修复。

## 本次本机结果

官方原生 Godot `4.6.3.stable.official.7d41c59c4`，两次新进程均退出 0，stderr
为空。主轨迹 14 个阶段；正常 API 生成状态的 237 次恢复对照未见误拒绝，
包含边界矩阵。独立夹具 14 个操作逐项复现原状态哈希。

第一笔预留 1000mJ，外部提交 3m/s 后第二笔预留 3009mJ；致死后余额 55991mJ
保留且不再发新力。拒付分支的 60009mJ 成本超过 60000mJ 余额，不扣费。
残骸位移来自现有线性段查询。外部接触结果是明确提供的夹具输入，不是求解结果。

最终主线状态 SHA-256：
`516ccb5f32bcecd557ea5a5af83386e6e76e8e0d136b612edb1f41fd19c5fe44`。

360m 初始几何中，1m 参考半径的绕行路线至少有 3.75m 额外间距；未经真实
世界碰撞器或运动接触验证。不能据此声称真实游戏已可玩或通过完整基准。

## 复跑

从包根目录指定 Godot 4.6.3 完整路径。先创建独立可写 QA 目录，并将
`SC_GROUND_QA_DIR` 设为该目录绝对路径；同时隔离用户数据目录。

```text
GODOT --headless --path . --script res://reference_trace.gd
GODOT --headless --path . --script res://replay_reference_fixture.gd
```

保留 stdout、stderr 及引擎日志；退出 0、最终报告 passed=true 且无诊断才算通过。
`DELIVERY_MANIFEST.json` 覆盖除自身以外的全部包内文件。候选仅等待集成审查，
不覆盖任何现有部署。云端已转发的独立验证记录在接口契约中，明确与本次
Windows 执行分开列出。
