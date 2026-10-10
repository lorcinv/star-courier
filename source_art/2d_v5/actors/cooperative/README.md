# 店员行走与平板动作原稿

本目录保留内置 imagegen 生成的原始 PNG；运行时图片放在
`assets/2d_v5/actors/cooperative/`。角色原图没有通过 SVG 或程序重画。

## 当前使用

- `clerk-walk-v2-original.png`、`clerk-walk-support-original.png`、
  `clerk-walk-opposite-original.png`：选择八张画格组成交替步态。
- `clerk-tablet-original.png`：查看运单、点击平板、看向货舱三张姿势。
- `motion-manifest.json`：运行时清单；标明原稿、SHA-256、尺寸、脚底、
  髋部、方向、抽取区域及每个画格的路径。

原 `clerk-walk-original.png` 只有三组主要步态；原
`clerk-help-original.png` 的空手示意姿势已经被平板替换。
这些旧稿留作追溯，不能当作当前运行时动作的证明。

## 重建当前图片

从项目根目录执行以下顺序：

1. `python3 source_art/2d_v5/actors/cooperative/prepare_clerk_motion.py`
2. `python3 source_art/2d_v5/actors/cooperative/prepare_clerk_tablet.py`
3. `python3 source_art/2d_v5/actors/cooperative/prepare_clerk_walk_v2.py`
4. `python3 tools/test_actor_motion_assets.py`

第一步重建历史基底；后两步只替换各自的姿势 / 行走字段，保留另一部分。
单独重跑第一步会恢复旧稿，不能作为完整重建。处理仅包括透明裁切、
统一身体采样比例、最近邻缩放、批准的 96 色调色板、透明度清理和画布注册。
不插画新肢体，不按手臂宽度缩放身体，也不对角色交叉淡化。

运行时节奏由实际行走距离决定，暂停不会继续摆腿。脚部和髋部注册能
减少漂移；这些仍是整幅精灵画格，并非连续骨骼动画或 Spine 导出。
美术接触表仅供检查，动作观感须以实际游戏中的正常速度录像为准。
