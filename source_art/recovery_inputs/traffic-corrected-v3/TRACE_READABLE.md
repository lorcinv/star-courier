# 有限事件轨迹：逐阶段精确状态差异

原始来源：Godot 4.6.3 native attempt `20261011T055248457939Z`。
这是集成参考；外部碰撞提交是明确的测试输入。资源数值是预留，不是实际求解的功。

| 阶段 | tick | revision | HP | 剩余 mJ | 已预留 mJ | 状态 |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| 00 authored | -1 | 0 | 25 | 60000 | 0 | none |
| 01 warning begins | 0 | 0 | 25 | 60000 | 0 | warning |
| 02 final warning interval | 179 | 0 | 25 | 60000 | 0 | warning |
| 03 first finite force intent | 180 | 0 | 25 | 59000 | 1000 | active |
| 04 supplied contact A | 180 | 1 | 14 | 59000 | 1000 | active |
| 05 second intent uses contact A | 181 | 1 | 14 | 55991 | 4009 | active |
| 06 supplied lethal contact B | 181 | 2 | 0 | 55991 | 4009 | cancelled / actor_destroyed |
| 07 retained wreck glides | 181 | 2 | 0 | 55991 | 4009 | cancelled / actor_destroyed |
| 08 legal later same-tick wreck rebase | 181 | 3 | 0 | 55991 | 4009 | cancelled / actor_destroyed |
| 09 wreck survives next tick | 182 | 3 | 0 | 55991 | 4009 | cancelled / actor_destroyed |
| 10 snapshot restored | 182 | 3 | 0 | 55991 | 4009 | cancelled / actor_destroyed |
| 11 restored continuation | 183 | 3 | 0 | 55991 | 4009 | cancelled / actor_destroyed |
| B0 supplied high-speed source | 179 | 1 | 25 | 60000 | 0 | warning |
| B1 unaffordable intent refused | 180 | 1 | 25 | 60000 | 0 | cancelled / resource_exhausted |

B0/B1 从阶段 02 的保存状态分支，不接续阶段 11。float64 的 bits_le 是权威精确值，可读小数仅辅助检查。未列字段未变化。

## 00 authored

来源：

```json
{
  "kind": "author",
  "seed": 42
}
```

```text
$: empty [Dictionary] -> <absent>
$.actors[0].anchor_fraction: <absent> -> 0.0 [float64 bits_le=0000000000000000]
$.actors[0].anchor_tick: <absent> -> 0 [int]
$.actors[0].fuel_mj: <absent> -> 0 [int]
$.actors[0].hp: <absent> -> 30 [int]
$.actors[0].id: <absent> -> ground-traffic-foundation-v1/42/traffic_0 [String]
$.actors[0].last_commit: <absent> -> None [Nil]
$.actors[0].mass_kg: <absent> -> 80.0 [float64 bits_le=0000000000005440]
$.actors[0].radius_m: <absent> -> 1.5 [float64 bits_le=000000000000f83f]
$.actors[0].revision: <absent> -> 0 [int]
$.actors[0].role: <absent> -> traffic_0 [String]
$.actors[0].source_id: <absent> -> ground-traffic-foundation-v1/42/traffic_0 [String]
$.actors[0].spent_mj: <absent> -> 0 [int]
$.actors[0].vx: <absent> -> 0.0 [float64 bits_le=0000000000000000]
$.actors[0].vy: <absent> -> 0.0 [float64 bits_le=0000000000000000]
$.actors[0].x: <absent> -> 126.675 [float64 bits_le=3333333333ab5f40]
$.actors[0].y: <absent> -> -8.0 [float64 bits_le=00000000000020c0]
$.actors[1].anchor_fraction: <absent> -> 0.0 [float64 bits_le=0000000000000000]
$.actors[1].anchor_tick: <absent> -> 0 [int]
$.actors[1].fuel_mj: <absent> -> 0 [int]
$.actors[1].hp: <absent> -> 40 [int]
$.actors[1].id: <absent> -> ground-traffic-foundation-v1/42/traffic_1 [String]
$.actors[1].last_commit: <absent> -> None [Nil]
$.actors[1].mass_kg: <absent> -> 100.0 [float64 bits_le=0000000000005940]
$.actors[1].radius_m: <absent> -> 1.75 [float64 bits_le=000000000000fc3f]
$.actors[1].revision: <absent> -> 0 [int]
$.actors[1].role: <absent> -> traffic_1 [String]
$.actors[1].source_id: <absent> -> ground-traffic-foundation-v1/42/traffic_1 [String]
$.actors[1].spent_mj: <absent> -> 0 [int]
$.actors[1].vx: <absent> -> 0.0 [float64 bits_le=0000000000000000]
$.actors[1].vy: <absent> -> 0.0 [float64 bits_le=0000000000000000]
$.actors[1].x: <absent> -> 134.944 [float64 bits_le=91ed7c3f35de6040]
$.actors[1].y: <absent> -> -6.5 [float64 bits_le=0000000000001ac0]
$.actors[2].anchor_fraction: <absent> -> 0.0 [float64 bits_le=0000000000000000]
$.actors[2].anchor_tick: <absent> -> 0 [int]
$.actors[2].fuel_mj: <absent> -> 60000 [int]
$.actors[2].hp: <absent> -> 25 [int]
$.actors[2].id: <absent> -> ground-traffic-foundation-v1/42/patrol [String]
$.actors[2].last_commit: <absent> -> None [Nil]
$.actors[2].mass_kg: <absent> -> 60.0 [float64 bits_le=0000000000004e40]
$.actors[2].radius_m: <absent> -> 1.25 [float64 bits_le=000000000000f43f]
$.actors[2].revision: <absent> -> 0 [int]
$.actors[2].role: <absent> -> patrol [String]
$.actors[2].source_id: <absent> -> ground-traffic-foundation-v1/42/patrol [String]
$.actors[2].spent_mj: <absent> -> 0 [int]
$.actors[2].vx: <absent> -> 0.0 [float64 bits_le=0000000000000000]
$.actors[2].vy: <absent> -> 0.0 [float64 bits_le=0000000000000000]
$.actors[2].x: <absent> -> 107.779 [float64 bits_le=60e5d022dbf15a40]
$.actors[2].y: <absent> -> -14.0 [float64 bits_le=0000000000002cc0]
$.bundle.active_ticks: <absent> -> 120 [int]
$.bundle.actors[0].fuel_mj: <absent> -> 0 [int]
$.bundle.actors[0].hp: <absent> -> 30 [int]
$.bundle.actors[0].id: <absent> -> ground-traffic-foundation-v1/42/traffic_0 [String]
$.bundle.actors[0].mass_kg: <absent> -> 80.0 [float64 bits_le=0000000000005440]
$.bundle.actors[0].radius_m: <absent> -> 1.5 [float64 bits_le=000000000000f83f]
$.bundle.actors[0].role: <absent> -> traffic_0 [String]
$.bundle.actors[0].source_id: <absent> -> ground-traffic-foundation-v1/42/traffic_0 [String]
$.bundle.actors[0].vx: <absent> -> 0.0 [float64 bits_le=0000000000000000]
$.bundle.actors[0].vy: <absent> -> 0.0 [float64 bits_le=0000000000000000]
$.bundle.actors[0].x: <absent> -> 126.675 [float64 bits_le=3333333333ab5f40]
$.bundle.actors[0].y: <absent> -> -8.0 [float64 bits_le=00000000000020c0]
$.bundle.actors[1].fuel_mj: <absent> -> 0 [int]
$.bundle.actors[1].hp: <absent> -> 40 [int]
$.bundle.actors[1].id: <absent> -> ground-traffic-foundation-v1/42/traffic_1 [String]
$.bundle.actors[1].mass_kg: <absent> -> 100.0 [float64 bits_le=0000000000005940]
$.bundle.actors[1].radius_m: <absent> -> 1.75 [float64 bits_le=000000000000fc3f]
$.bundle.actors[1].role: <absent> -> traffic_1 [String]
$.bundle.actors[1].source_id: <absent> -> ground-traffic-foundation-v1/42/traffic_1 [String]
$.bundle.actors[1].vx: <absent> -> 0.0 [float64 bits_le=0000000000000000]
$.bundle.actors[1].vy: <absent> -> 0.0 [float64 bits_le=0000000000000000]
$.bundle.actors[1].x: <absent> -> 134.944 [float64 bits_le=91ed7c3f35de6040]
$.bundle.actors[1].y: <absent> -> -6.5 [float64 bits_le=0000000000001ac0]
$.bundle.actors[2].fuel_mj: <absent> -> 60000 [int]
$.bundle.actors[2].hp: <absent> -> 25 [int]
$.bundle.actors[2].id: <absent> -> ground-traffic-foundation-v1/42/patrol [String]
$.bundle.actors[2].mass_kg: <absent> -> 60.0 [float64 bits_le=0000000000004e40]
$.bundle.actors[2].radius_m: <absent> -> 1.25 [float64 bits_le=000000000000f43f]
$.bundle.actors[2].role: <absent> -> patrol [String]
$.bundle.actors[2].source_id: <absent> -> ground-traffic-foundation-v1/42/patrol [String]
$.bundle.actors[2].vx: <absent> -> 0.0 [float64 bits_le=0000000000000000]
$.bundle.actors[2].vy: <absent> -> 0.0 [float64 bits_le=0000000000000000]
$.bundle.actors[2].x: <absent> -> 107.779 [float64 bits_le=60e5d022dbf15a40]
$.bundle.actors[2].y: <absent> -> -14.0 [float64 bits_le=0000000000002cc0]
$.bundle.helper: <absent> -> ground-traffic-foundation-v1 [String]
$.bundle.max_force_n: <absent> -> 120.0 [float64 bits_le=0000000000005e40]
$.bundle.minimum_cost_mj: <absent> -> 1000 [int]
$.bundle.patrol_enabled: <absent> -> True [bool]
$.bundle.scenario: <absent> -> city-360-between-gates-85-185 [String]
$.bundle.seed: <absent> -> 42 [int]
$.bundle.traffic_count: <absent> -> 2 [int]
$.bundle.warning_ticks: <absent> -> 180 [int]
$.charges: <absent> -> empty [Array]
$.helper: <absent> -> ground-traffic-foundation-v1 [String]
$.last_tick: <absent> -> -1 [int]
$.snapshot_version: <absent> -> ground-traffic-candidate-v3-snapshot-1 [String]
$.warning: <absent> -> None [Nil]
```

状态哈希：`200a0d7dac99175e5cb48ef292bacb3f8069df454ff23f22056f83cd41c44e6e`。

因果来源映射：

```json
{
  "actor_input": "author_seed_42",
  "actor_revision": 0,
  "paid": []
}
```

## 01 warning begins

来源：

```json
{
  "command": {
    "cancel_warning": false,
    "warning_request": {
      "request_id": "reference_0",
      "target_x": 132.0,
      "target_y": -8.0
    }
  },
  "kind": "input_command"
}
```

```text
$.last_tick: -1 [int] -> 0 [int]
$.warning: None [Nil] -> <absent>
$.warning.active_left: <absent> -> 120 [int]
$.warning.closed_fraction: <absent> -> 0.0 [float64 bits_le=0000000000000000]
$.warning.closed_tick: <absent> -> -1 [int]
$.warning.denied_cost_mj: <absent> -> 0 [int]
$.warning.denied_vx: <absent> -> 0.0 [float64 bits_le=0000000000000000]
$.warning.denied_vy: <absent> -> 0.0 [float64 bits_le=0000000000000000]
$.warning.dir_x: <absent> -> 0.9706612394797595 [float64 bits_le=b9eee128a80fef3f]
$.warning.dir_y: <absent> -> 0.2404511554798958 [float64 bits_le=ff28897c1ac7ce3f]
$.warning.emitted: <absent> -> 0 [int]
$.warning.event_id: <absent> -> ground-traffic-foundation-v1/42/patrol/warning_0 [String]
$.warning.locked_tick: <absent> -> 0 [int]
$.warning.origin_motion.commit: <absent> -> None [Nil]
$.warning.origin_motion.revision: <absent> -> 0 [int]
$.warning.origin_x: <absent> -> 107.779 [float64 bits_le=60e5d022dbf15a40]
$.warning.origin_y: <absent> -> -14.0 [float64 bits_le=0000000000002cc0]
$.warning.phase: <absent> -> warning [String]
$.warning.reason: <absent> ->  [String]
$.warning.request_id: <absent> -> reference_0 [String]
$.warning.source_id: <absent> -> ground-traffic-foundation-v1/42/patrol [String]
$.warning.target_x: <absent> -> 132.0 [float64 bits_le=0000000000806040]
$.warning.target_y: <absent> -> -8.0 [float64 bits_le=00000000000020c0]
$.warning.terminal_motion: <absent> -> None [Nil]
$.warning.warning_left: <absent> -> 180 [int]
```

状态哈希：`474d5edae5c8843b7594d4fd32380f4abe7c76015e6884782b52f75e8f541727`。

因果来源映射：

```json
{
  "actor_input": "author_seed_42",
  "actor_revision": 0,
  "paid": [],
  "warning_origin": "author_seed_42"
}
```

## 02 final warning interval

来源：

```json
{
  "first": 1,
  "kind": "sequential_ticks",
  "last": 179
}
```

```text
$.last_tick: 0 [int] -> 179 [int]
$.warning.warning_left: 180 [int] -> 1 [int]
```

状态哈希：`a85ceafee2dcadef73bd3b002926b418ed5938726784b80ba25cee44445ce501`。

因果来源映射：

```json
{
  "actor_input": "author_seed_42",
  "actor_revision": 0,
  "paid": [],
  "warning_origin": "author_seed_42"
}
```

## 03 first finite force intent

来源：

```json
{
  "kind": "tick",
  "tick": 180
}
```

```text
$.actors[2].fuel_mj: 60000 [int] -> 59000 [int]
$.actors[2].spent_mj: 0 [int] -> 1000 [int]
$.charges: empty [Array] -> <absent>
$.charges[0].cost_mj: <absent> -> 1000 [int]
$.charges[0].motion.commit: <absent> -> None [Nil]
$.charges[0].motion.revision: <absent> -> 0 [int]
$.charges[0].tick: <absent> -> 180 [int]
$.charges[0].vx: <absent> -> 0.0 [float64 bits_le=0000000000000000]
$.charges[0].vy: <absent> -> 0.0 [float64 bits_le=0000000000000000]
$.last_tick: 179 [int] -> 180 [int]
$.warning.active_left: 120 [int] -> 119 [int]
$.warning.emitted: 0 [int] -> 1 [int]
$.warning.phase: warning [String] -> active [String]
$.warning.warning_left: 1 [int] -> 0 [int]
```

状态哈希：`323c3240b93aca2bfc0bf0616d08c68630b9c5f7bee87a67a07447abd390f4b7`。

因果来源映射：

```json
{
  "actor_input": "author_seed_42",
  "actor_revision": 0,
  "paid": [
    {
      "cost_mj": 1000,
      "input": "author_seed_42",
      "tick": 180
    }
  ],
  "warning_origin": "author_seed_42"
}
```

## 04 supplied contact A

来源：

```json
{
  "commit": {
    "actor_id": "ground-traffic-foundation-v1/42/patrol",
    "fraction": 0.5,
    "hp": 14,
    "revision": 1,
    "tick": 180,
    "vx": 3.0,
    "vy": 0.0,
    "x": 107.779,
    "y": -14.0
  },
  "id": "external/contact_A",
  "kind": "external_collision_fixture",
  "solver_implemented": false
}
```

```text
$.actors[2].anchor_fraction: 0.0 [float64 bits_le=0000000000000000] -> 0.5 [float64 bits_le=000000000000e03f]
$.actors[2].anchor_tick: 0 [int] -> 180 [int]
$.actors[2].hp: 25 [int] -> 14 [int]
$.actors[2].last_commit: None [Nil] -> <absent>
$.actors[2].last_commit.actor_id: <absent> -> ground-traffic-foundation-v1/42/patrol [String]
$.actors[2].last_commit.fraction: <absent> -> 0.5 [float64 bits_le=000000000000e03f]
$.actors[2].last_commit.hp: <absent> -> 14 [int]
$.actors[2].last_commit.revision: <absent> -> 1 [int]
$.actors[2].last_commit.tick: <absent> -> 180 [int]
$.actors[2].last_commit.vx: <absent> -> 3.0 [float64 bits_le=0000000000000840]
$.actors[2].last_commit.vy: <absent> -> 0.0 [float64 bits_le=0000000000000000]
$.actors[2].last_commit.x: <absent> -> 107.779 [float64 bits_le=60e5d022dbf15a40]
$.actors[2].last_commit.y: <absent> -> -14.0 [float64 bits_le=0000000000002cc0]
$.actors[2].revision: 0 [int] -> 1 [int]
$.actors[2].vx: 0.0 [float64 bits_le=0000000000000000] -> 3.0 [float64 bits_le=0000000000000840]
```

状态哈希：`0731384627765895b17f48513fcaeb810aed321c7ee4ebe7e6e1d3f8559383ec`。

因果来源映射：

```json
{
  "actor_input": "external/contact_A",
  "actor_revision": 1,
  "paid": [
    {
      "cost_mj": 1000,
      "input": "author_seed_42",
      "tick": 180
    }
  ],
  "warning_origin": "author_seed_42"
}
```

## 05 second intent uses contact A

来源：

```json
{
  "kind": "tick",
  "tick": 181,
  "velocity_source": "external/contact_A"
}
```

```text
$.actors[2].fuel_mj: 59000 [int] -> 55991 [int]
$.actors[2].spent_mj: 1000 [int] -> 4009 [int]
$.charges[1].cost_mj: <absent> -> 3009 [int]
$.charges[1].motion.commit.actor_id: <absent> -> ground-traffic-foundation-v1/42/patrol [String]
$.charges[1].motion.commit.fraction: <absent> -> 0.5 [float64 bits_le=000000000000e03f]
$.charges[1].motion.commit.hp: <absent> -> 14 [int]
$.charges[1].motion.commit.revision: <absent> -> 1 [int]
$.charges[1].motion.commit.tick: <absent> -> 180 [int]
$.charges[1].motion.commit.vx: <absent> -> 3.0 [float64 bits_le=0000000000000840]
$.charges[1].motion.commit.vy: <absent> -> 0.0 [float64 bits_le=0000000000000000]
$.charges[1].motion.commit.x: <absent> -> 107.779 [float64 bits_le=60e5d022dbf15a40]
$.charges[1].motion.commit.y: <absent> -> -14.0 [float64 bits_le=0000000000002cc0]
$.charges[1].motion.revision: <absent> -> 1 [int]
$.charges[1].tick: <absent> -> 181 [int]
$.charges[1].vx: <absent> -> 3.0 [float64 bits_le=0000000000000840]
$.charges[1].vy: <absent> -> 0.0 [float64 bits_le=0000000000000000]
$.last_tick: 180 [int] -> 181 [int]
$.warning.active_left: 119 [int] -> 118 [int]
$.warning.emitted: 1 [int] -> 2 [int]
```

状态哈希：`dc33936d45dd02e86cdabfceeb4f82347307741ed9541dd7c90fadcb4085f4d0`。

因果来源映射：

```json
{
  "actor_input": "external/contact_A",
  "actor_revision": 1,
  "paid": [
    {
      "cost_mj": 1000,
      "input": "author_seed_42",
      "tick": 180
    },
    {
      "cost_mj": 3009,
      "input": "external/contact_A",
      "tick": 181
    }
  ],
  "warning_origin": "author_seed_42"
}
```

## 06 supplied lethal contact B

来源：

```json
{
  "commit": {
    "actor_id": "ground-traffic-foundation-v1/42/patrol",
    "fraction": 0.75,
    "hp": 0,
    "revision": 2,
    "tick": 181,
    "vx": -1.5,
    "vy": 0.25,
    "x": 107.81025,
    "y": -14.0
  },
  "id": "external/contact_B",
  "kind": "external_collision_fixture",
  "solver_implemented": false
}
```

```text
$.actors[2].anchor_fraction: 0.5 [float64 bits_le=000000000000e03f] -> 0.75 [float64 bits_le=000000000000e83f]
$.actors[2].anchor_tick: 180 [int] -> 181 [int]
$.actors[2].hp: 14 [int] -> 0 [int]
$.actors[2].last_commit.fraction: 0.5 [float64 bits_le=000000000000e03f] -> 0.75 [float64 bits_le=000000000000e83f]
$.actors[2].last_commit.hp: 14 [int] -> 0 [int]
$.actors[2].last_commit.revision: 1 [int] -> 2 [int]
$.actors[2].last_commit.tick: 180 [int] -> 181 [int]
$.actors[2].last_commit.vx: 3.0 [float64 bits_le=0000000000000840] -> -1.5 [float64 bits_le=000000000000f8bf]
$.actors[2].last_commit.vy: 0.0 [float64 bits_le=0000000000000000] -> 0.25 [float64 bits_le=000000000000d03f]
$.actors[2].last_commit.x: 107.779 [float64 bits_le=60e5d022dbf15a40] -> 107.81025 [float64 bits_le=60e5d022dbf35a40]
$.actors[2].revision: 1 [int] -> 2 [int]
$.actors[2].vx: 3.0 [float64 bits_le=0000000000000840] -> -1.5 [float64 bits_le=000000000000f8bf]
$.actors[2].vy: 0.0 [float64 bits_le=0000000000000000] -> 0.25 [float64 bits_le=000000000000d03f]
$.actors[2].x: 107.779 [float64 bits_le=60e5d022dbf15a40] -> 107.81025 [float64 bits_le=60e5d022dbf35a40]
$.warning.closed_fraction: 0.0 [float64 bits_le=0000000000000000] -> 0.75 [float64 bits_le=000000000000e83f]
$.warning.closed_tick: -1 [int] -> 181 [int]
$.warning.phase: active [String] -> cancelled [String]
$.warning.reason:  [String] -> actor_destroyed [String]
$.warning.terminal_motion: None [Nil] -> <absent>
$.warning.terminal_motion.commit.actor_id: <absent> -> ground-traffic-foundation-v1/42/patrol [String]
$.warning.terminal_motion.commit.fraction: <absent> -> 0.75 [float64 bits_le=000000000000e83f]
$.warning.terminal_motion.commit.hp: <absent> -> 0 [int]
$.warning.terminal_motion.commit.revision: <absent> -> 2 [int]
$.warning.terminal_motion.commit.tick: <absent> -> 181 [int]
$.warning.terminal_motion.commit.vx: <absent> -> -1.5 [float64 bits_le=000000000000f8bf]
$.warning.terminal_motion.commit.vy: <absent> -> 0.25 [float64 bits_le=000000000000d03f]
$.warning.terminal_motion.commit.x: <absent> -> 107.81025 [float64 bits_le=60e5d022dbf35a40]
$.warning.terminal_motion.commit.y: <absent> -> -14.0 [float64 bits_le=0000000000002cc0]
$.warning.terminal_motion.revision: <absent> -> 2 [int]
```

状态哈希：`1ba17ba44c13c30bcc65a89391c55976853da166f527c830b863a41bcfcd4e3f`。

因果来源映射：

```json
{
  "actor_input": "external/contact_B",
  "actor_revision": 2,
  "paid": [
    {
      "cost_mj": 1000,
      "input": "author_seed_42",
      "tick": 180
    },
    {
      "cost_mj": 3009,
      "input": "external/contact_A",
      "tick": 181
    }
  ],
  "terminal": "external/contact_B",
  "warning_origin": "author_seed_42"
}
```

## 07 retained wreck glides

来源：

```json
{
  "kind": "existing_linear_segment_query",
  "segment": {
    "actor_id": "ground-traffic-foundation-v1/42/patrol",
    "end": {
      "ok": true,
      "vx": -1.5,
      "vy": 0.25,
      "x": 107.807125,
      "y": -13.999479166666667
    },
    "from_fraction": 0.75,
    "hp": 0,
    "mass_kg": 60.0,
    "model": "saved_linear_segment_only",
    "ok": true,
    "radius_m": 1.25,
    "source_id": "ground-traffic-foundation-v1/42/patrol",
    "start": {
      "ok": true,
      "vx": -1.5,
      "vy": 0.25,
      "x": 107.81025,
      "y": -14.0
    },
    "tick": 181,
    "to_fraction": 1.0
  },
  "source": "external/contact_B"
}
```

```text
No state fields changed.
```

状态哈希：`1ba17ba44c13c30bcc65a89391c55976853da166f527c830b863a41bcfcd4e3f`。

因果来源映射：

```json
{
  "actor_input": "external/contact_B",
  "actor_revision": 2,
  "paid": [
    {
      "cost_mj": 1000,
      "input": "author_seed_42",
      "tick": 180
    },
    {
      "cost_mj": 3009,
      "input": "external/contact_A",
      "tick": 181
    }
  ],
  "terminal": "external/contact_B",
  "warning_origin": "author_seed_42"
}
```

## 08 legal later same-tick wreck rebase

来源：

```json
{
  "commit": {
    "actor_id": "ground-traffic-foundation-v1/42/patrol",
    "fraction": 0.875,
    "hp": 0,
    "revision": 3,
    "tick": 181,
    "vx": -1.5,
    "vy": 0.25,
    "x": 107.80868749999999,
    "y": -13.999739583333334
  },
  "kind": "external_owner_checkpoint"
}
```

```text
$.actors[2].anchor_fraction: 0.75 [float64 bits_le=000000000000e83f] -> 0.875 [float64 bits_le=000000000000ec3f]
$.actors[2].last_commit.fraction: 0.75 [float64 bits_le=000000000000e83f] -> 0.875 [float64 bits_le=000000000000ec3f]
$.actors[2].last_commit.revision: 2 [int] -> 3 [int]
$.actors[2].last_commit.x: 107.81025 [float64 bits_le=60e5d022dbf35a40] -> 107.80868749999999 [float64 bits_le=c64b3789c1f35a40]
$.actors[2].last_commit.y: -14.0 [float64 bits_le=0000000000002cc0] -> -13.999739583333334 [float64 bits_le=deddddddddff2bc0]
$.actors[2].revision: 2 [int] -> 3 [int]
$.actors[2].x: 107.81025 [float64 bits_le=60e5d022dbf35a40] -> 107.80868749999999 [float64 bits_le=c64b3789c1f35a40]
$.actors[2].y: -14.0 [float64 bits_le=0000000000002cc0] -> -13.999739583333334 [float64 bits_le=deddddddddff2bc0]
```

状态哈希：`f86e8793dedc2b02ec3f5fc71511cdc770de5301bcfc98c2079857fdd181149a`。

因果来源映射：

```json
{
  "actor_input": "external/same_tick_owner_checkpoint",
  "actor_revision": 3,
  "paid": [
    {
      "cost_mj": 1000,
      "input": "author_seed_42",
      "tick": 180
    },
    {
      "cost_mj": 3009,
      "input": "external/contact_A",
      "tick": 181
    }
  ],
  "terminal": "external/contact_B",
  "warning_origin": "author_seed_42"
}
```

## 09 wreck survives next tick

来源：

```json
{
  "kind": "tick",
  "tick": 182
}
```

```text
$.last_tick: 181 [int] -> 182 [int]
```

状态哈希：`1df13acdd7a6b237096953bdf5733c8a102a7c18a3e567808df7b990743a2497`。

因果来源映射：

```json
{
  "actor_input": "external/same_tick_owner_checkpoint",
  "actor_revision": 3,
  "paid": [
    {
      "cost_mj": 1000,
      "input": "author_seed_42",
      "tick": 180
    },
    {
      "cost_mj": 3009,
      "input": "external/contact_A",
      "tick": 181
    }
  ],
  "terminal": "external/contact_B",
  "warning_origin": "author_seed_42"
}
```

## 10 snapshot restored

来源：

```json
{
  "bytes": 6266,
  "kind": "typed_snapshot_round_trip"
}
```

```text
No state fields changed.
```

状态哈希：`1df13acdd7a6b237096953bdf5733c8a102a7c18a3e567808df7b990743a2497`。

因果来源映射：

```json
{
  "actor_input": "external/same_tick_owner_checkpoint",
  "actor_revision": 3,
  "paid": [
    {
      "cost_mj": 1000,
      "input": "author_seed_42",
      "tick": 180
    },
    {
      "cost_mj": 3009,
      "input": "external/contact_A",
      "tick": 181
    }
  ],
  "terminal": "external/contact_B",
  "warning_origin": "author_seed_42"
}
```

## 11 restored continuation

来源：

```json
{
  "comparison": "uninterrupted twin",
  "kind": "tick",
  "tick": 183
}
```

```text
$.last_tick: 182 [int] -> 183 [int]
```

状态哈希：`516ccb5f32bcecd557ea5a5af83386e6e76e8e0d136b612edb1f41fd19c5fe44`。

因果来源映射：

```json
{
  "actor_input": "external/same_tick_owner_checkpoint",
  "actor_revision": 3,
  "paid": [
    {
      "cost_mj": 1000,
      "input": "author_seed_42",
      "tick": 180
    },
    {
      "cost_mj": 3009,
      "input": "external/contact_A",
      "tick": 181
    }
  ],
  "terminal": "external/contact_B",
  "warning_origin": "author_seed_42"
}
```

## B0 supplied high-speed source

来源：

```json
{
  "external_commit": {
    "actor_id": "ground-traffic-foundation-v1/42/patrol",
    "fraction": 1.0,
    "hp": 25,
    "revision": 1,
    "tick": 179,
    "vx": 60.0,
    "vy": 0.0,
    "x": 107.779,
    "y": -14.0
  },
  "kind": "branch_from_stage_02",
  "solver_implemented": false
}
```

```text
$.actors[2].anchor_tick: 0 [int] -> 180 [int]
$.actors[2].last_commit: None [Nil] -> <absent>
$.actors[2].last_commit.actor_id: <absent> -> ground-traffic-foundation-v1/42/patrol [String]
$.actors[2].last_commit.fraction: <absent> -> 1.0 [float64 bits_le=000000000000f03f]
$.actors[2].last_commit.hp: <absent> -> 25 [int]
$.actors[2].last_commit.revision: <absent> -> 1 [int]
$.actors[2].last_commit.tick: <absent> -> 179 [int]
$.actors[2].last_commit.vx: <absent> -> 60.0 [float64 bits_le=0000000000004e40]
$.actors[2].last_commit.vy: <absent> -> 0.0 [float64 bits_le=0000000000000000]
$.actors[2].last_commit.x: <absent> -> 107.779 [float64 bits_le=60e5d022dbf15a40]
$.actors[2].last_commit.y: <absent> -> -14.0 [float64 bits_le=0000000000002cc0]
$.actors[2].revision: 0 [int] -> 1 [int]
$.actors[2].vx: 0.0 [float64 bits_le=0000000000000000] -> 60.0 [float64 bits_le=0000000000004e40]
```

状态哈希：`05fa2be5a0737d3a18b794e00355bde4879ce10e252e965f4f520b987202cc47`。

因果来源映射：

```json
{
  "actor_input": "external/denial_branch_contact",
  "actor_revision": 1,
  "paid": [],
  "warning_origin": "author_seed_42"
}
```

## B1 unaffordable intent refused

来源：

```json
{
  "kind": "tick",
  "tick": 180,
  "velocity_source": "external/denial_branch_contact"
}
```

```text
$.last_tick: 179 [int] -> 180 [int]
$.warning.closed_tick: -1 [int] -> 180 [int]
$.warning.denied_cost_mj: 0 [int] -> 60009 [int]
$.warning.denied_vx: 0.0 [float64 bits_le=0000000000000000] -> 60.0 [float64 bits_le=0000000000004e40]
$.warning.phase: warning [String] -> cancelled [String]
$.warning.reason:  [String] -> resource_exhausted [String]
$.warning.terminal_motion: None [Nil] -> <absent>
$.warning.terminal_motion.commit.actor_id: <absent> -> ground-traffic-foundation-v1/42/patrol [String]
$.warning.terminal_motion.commit.fraction: <absent> -> 1.0 [float64 bits_le=000000000000f03f]
$.warning.terminal_motion.commit.hp: <absent> -> 25 [int]
$.warning.terminal_motion.commit.revision: <absent> -> 1 [int]
$.warning.terminal_motion.commit.tick: <absent> -> 179 [int]
$.warning.terminal_motion.commit.vx: <absent> -> 60.0 [float64 bits_le=0000000000004e40]
$.warning.terminal_motion.commit.vy: <absent> -> 0.0 [float64 bits_le=0000000000000000]
$.warning.terminal_motion.commit.x: <absent> -> 107.779 [float64 bits_le=60e5d022dbf15a40]
$.warning.terminal_motion.commit.y: <absent> -> -14.0 [float64 bits_le=0000000000002cc0]
$.warning.terminal_motion.revision: <absent> -> 1 [int]
$.warning.warning_left: 1 [int] -> 0 [int]
```

状态哈希：`20cfaa2f3793798d2777aab821f16402ac4bb82d74d33852e964a9b764283587`。

因果来源映射：

```json
{
  "actor_input": "external/denial_branch_contact",
  "actor_revision": 1,
  "paid": [],
  "terminal": "external/denial_branch_contact",
  "warning_origin": "author_seed_42"
}
```

