---
name: agent-relay
description: 用固定的多 Agent 交付流水线，把一句话需求接力送到可验收的分支。角色化分工（澄清/设计/开发/评审/验证），每个角色可配 agent + 模型 + 思考等级，支持单侧需求裁剪（只做后端/只做前端），有 Orca 用 DAG 并行、没 Orca 顺序跑。触发场景：「跑流水线」「用 relay 做这个需求」「多个 agent 接力做 X」「按 specs 交付」「前后端分开做再联调」。
---

# Agent Relay

**这是一个启动器，不是运行时。** 调度逻辑在 `scripts/relay.py` 里，你负责决定跑什么、何时停、何时找人。

## 0. 先定位仓库

```bash
RELAY="${AGENT_RELAY_HOME:-$(dirname "$(dirname "$(readlink -f ~/.agents/skills/agent-relay/SKILL.md)")")}"
ls "$RELAY/pipeline.json" || echo "找不到仓库，问用户装在哪"
```

拿不到就问用户，**不要自己 clone 一份**——多份副本会让 `stages/` 分叉。

## 1. 五条铁律

1. **不许手搓调度。** 顺序、依赖、断点、闸门全走 `scripts/relay.py`。手工 `worker-start` 串联意味着你重建了一个更差的调度器。
2. **不许跳过人工闸门。** `00b-scope` 和 `03-contract` 就是等人。`--yes` 只用于测试。
3. **不许替用户拍契约。** 那是流程里唯一"错了会乘以四"的决策点。
4. **不许改用例凑绿。** 用例归 `e2e_author`，执行者只能改实现。
5. **不许把 agent 名写进 `stages/`。** 那里只写能力档。

## 2. 开跑前

```bash
"$RELAY/scripts/doctor.sh" --project <项目目录>
```

看三件事：**能力档**（A/B/C）、**被裁剪的节点**、**注入告警**（配了 model 但 CLI 不支持）。

- C 档：报告里必须写"未做交叉评审"。假装做了比承认更糟。
- 有注入告警：告诉用户"这个参数对它无效"，别当成生效。

## 3. 主循环

```bash
# 澄清（要收敛，不是一次调用）
"$RELAY/scripts/run-plain.sh" --project <dir> --only-node 00a-clarify --rounds 3

# 冻结范围：写 handoff/00b-scope.md，不做清单 ≥ 3 条
# 契约：写 contract/api.yaml，过 references/contract-checklist.md 八项
"$RELAY/scripts/run-plain.sh" --project <dir> --start-from 03-contract

# 或者一次跑到底，闸门处会停
"$RELAY/scripts/run-plain.sh" --project <dir>
```

每个节点结束后读它的产物（`handoff/*.md`），**不要读原始对话**。上一站的对话不是你的输入。

## 4. 三种模式

| 情况 | 怎么做 |
|---|---|
| 有 Orca | `scripts/run-orca.sh --apply` 建图，然后你当协调者：被唤醒 → `task-list --ready` → 起 ready 的 → 结束本轮。**不要轮询** |
| 没 Orca | `scripts/run-plain.sh`，就这一句 |
| CI | `RELAY_CONFIG=... run-plain.sh --only-node <id>`，按节点拆 job |

## 5. 单侧需求

只做后端或只做前端时，不要手工删节点——用配置裁剪，依赖会自动重连：

```json
{ "options": { "scope": "backend" } }   // 裁掉前端设计与前端开发、合并
```

`render.sh` 会打出"已裁剪: …"。跑完检查 `state.json` 的 `skipped` 是否符合预期。

## 6. 失败怎么处理

- **红了先读证据**：`runs/<id>/<node>.r*.log` 和 `state.json`。
- **修复回灌给原节点**，不要新起任务（省上下文）。
- **最多 2 轮**。第 3 轮停，找人。
- **同类问题第 2 次红 → 回 `03-contract`**，不是回开发站。那说明判据错了，不是实现马虎。

## 7. 什么时候不要用这个

- 单文件改动、改文案、调样式 → 直接做，别起流水线
- 探索性调研、方案还没定 → 这是 `00a` 的活，但别往后跑
- 用户想边做边聊、随时改主意 → 用交互式会话，这套是为"交付"设计的

## 8. 你要向用户汇报什么

每轮结束只报四件事：**跑到哪了 / 产物在哪 / 卡在什么 / 下一步要你做什么**。不要复述 Agent 的输出。
