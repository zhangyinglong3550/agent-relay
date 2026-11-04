# Agent Relay

**中文** | [English](README.en.md)

把一句话需求，接力送到一个可验收的分支上。

Agent Relay 不是一个 Agent 框架，也不是一个服务。它是一组**文本资产 + 两个脚本**：一份声明式的交付流水线定义，让你的命令行 Agent（Claude Code、Codex、Kimi、ZCode、DeepSeek Harness……）按固定的角色分工接力干活，只在两个地方停下来等你。

- **不绑定 Agent**：角色和能力档是抽象槽位，谁上由你的配置决定
- **不绑定 Runner**：有 Orca 用 DAG 并行，没有就用纯 bash 顺序跑
- **不绑定模型**：每个角色的 agent、模型、思考等级都可配
- **会自己退化**：只有一个 Agent 时自动降级，并如实告诉你缺了哪一步

---

## 它解决什么问题

一个人用 Agent 写代码已经很顺了。难的是**一次需求要过四个环节**：定方案、写实现、验行为、看质量——而且每个环节最合适的模型可能不是同一个。

手工串联的真实成本不是"点四下"，而是：每次换手你都要**重新交代上下文**，而上一棒的心理活动（为什么这么设计）在交接时全部丢失。

Agent Relay 的做法很朴素：**交接物只走文件，不走对话。**

每一棒拿到的不是一个正在说话的同事，而是上一棒留下的文档和骨架。这逼出了两个好处：

1. 上下文不会串味——实现者不会去猜设计者的意图，只会照文档做
2. 出了问题能定位——每一棒的输入输出都是磁盘上的文件，可回放、可 diff

---

## 流水线长什么样

```
00a 澄清 ──▶ 00b 需求冻结 ⛩ ──┬─▶ 01 前端方案 ─┐
                              └─▶ 02 后端方案 ─┤
                                              ├─▶ 03 契约冻结 ⛩ ──┬─▶ 04 前端开发 ─┐
                                              │                   └─▶ 05 后端开发 ─┤
                                              │                                   ├─▶ 06 合并
                                              └─▶ 07 E2E 用例 ────────────────────┘
                                                                                  │
                                              09 正确性评审 ◀─ 08 复杂度审计 ◀── 06
                                                        │
                                                        └─▶ 10 E2E 执行 ──▶ 交付
```

⛩ = 人工闸门。**只有两个**，都是"十分钟能拍完、拍错要命"的点。

失败回路：E2E 红 → 证据回灌对应开发站（最多 2 轮）→ 同一类问题再红 → 回契约站，不回开发站。

---

## 快速开始

```bash
git clone https://github.com/<you>/agent-relay.git
cd agent-relay

# 1. 看看你机器上有什么
./scripts/doctor.sh

# 2. 生成你的本地配置
cp pipeline.local.example.json pipeline.local.json
$EDITOR pipeline.local.json          # 填 agent，并把 options.projectRoot 指向你的项目

# 3. 不调 Agent，先看一遍解析出来的执行计划
./scripts/render.sh                  # 第一行会显示「产物根」

# 4. 真跑
./scripts/run-plain.sh
```

澄清要一问一答，用多轮把它跑收敛：

```bash
./scripts/run-plain.sh --only-node 00a-clarify --rounds 3
# 第 1 轮出问题清单 → 你写进 handoff/00a-answers.md → 回车 → 第 2 轮收敛
```

`doctor.sh` 会告诉你三件事：检测到哪些 Agent、你的配置能跑哪一档、哪一步会被跳过。

---

## 作为 Skill 使用

仓库自带一份 Skill 入口（`skill/SKILL.md`），装上是符号链接，改仓库即生效：

```bash
./scripts/install-skill.sh            # → ~/.agents/skills/agent-relay
```

装完之后，任何 Agent 听到「用 relay 做这个需求」就会读到它，知道该调哪个脚本、哪两个闸门必须停、失败怎么回灌。

**Skill 是启动器，运行时是脚本。** 它不复制 `stages/`，只指向仓库——所以流程只有一份，不会分叉。

---

## 三档能力（自动判定）

| 档 | 手上有什么 | 会发生什么 |
|---|---|---|
| **A 完整** | ≥3 个不同 Agent | 全流程，含交叉评审 |
| **B 双档** | 2 个 | 用 `model` / `effort` 拉开强弱，评审交叉执行 |
| **C 单档** | 1 个 | 各角色冷启动分饰，**跳过交叉互审并如实标注** |

C 档有一条硬规矩：**每个角色都必须冷启动新会话，只喂文件。** 同一个模型连着上下文评审自己刚写的东西，只会得到确认。

---

## 配置三层

```
pipeline.json            流水线结构：有哪些节点、依赖谁、谁是人闸门   ← 团队共享，进 git
pipeline.local.json      你的机器：每个角色用哪个 agent / 模型 / 思考等级 ← 本地，不进 git
adapters.json            各家 CLI 怎么注入 prompt / model / effort      ← 团队共享
```

**一个工具，多个项目。** 工具装在 `~/tools/agent-relay` 一份就够，每个项目在自己的根目录放一个 `.agent-relay.json`：

```bash
./scripts/run-plain.sh --project ~/code/project-a   # 自动读 project-a/.agent-relay.json
./scripts/run-plain.sh --project ~/code/project-b
```

优先级：`--config` > `$RELAY_CONFIG` > `<project>/.agent-relay.json` > 仓库自带的 `pipeline.local.json`。没写 `projectRoot` 时，`--project` 会替你补上。

结构是共享的，**人和机器是私有的**。同事之间共享 `pipeline.json` 和 `adapters.json`，各自维护 `pipeline.local.json`。

```json
{
  "roles": {
    "plan":     { "agent": "claude", "model": "opus",   "effort": "high" },
    "dev":      { "agent": "kimi",   "model": "kimi-k3", "effort": "medium" },
    "verify":   { "agent": "dsh",    "effort": "low" },
    "review":   { "agent": "codex",  "effort": "high" }
  }
}
```

模型和思考等级能不能真的生效，取决于该 Agent 支持哪条注入通道——`adapters.json` 里写清楚了，`doctor.sh` 会校验并告警。详见 [配置说明](docs/configuration.md)。

---

## Runner

| Runner | 需要什么 | 得到什么 |
|---|---|---|
| `scripts/run-plain.sh` | 任意 Agent CLI + git | 顺序执行、人工闸门、断点续跑。**零额外依赖** |
| `scripts/run-orca.sh` | [Orca](https://github.com/orca-labs/orca) | 依赖图并行、完成唤醒、worktree 隔离 |
| 自定义 | — | 读 `pipeline.json` 自己实现，`render.sh` 会给你完整的执行计划 |

**spec 描述要什么，runner 决定怎么跑。** 这是本项目最重要的一条边界：否则你的团队会被某个 app 绑死。

---

## 为什么是这些设计

每一条都来自踩过的坑，写在 [docs/design-decisions.md](docs/design-decisions.md)：

- 为什么人闸门只有两个，且都在"会乘以四"的位置
- 为什么设计评审只出清单、没有否决权
- 为什么实现站必须拿到可编译的骨架，而不只是文档
- 为什么 E2E 用例要由强模型写、便宜模型执行
- 为什么测试执行者不许改用例
- 为什么"验证通过"不等于"代码正确"

---

## 目录

```
pipeline.json          流水线定义（DAG、闸门、产物）
adapters.json          各 Agent 的能力与注入方式
stages/                每一站的说明书——本项目的核心资产
references/            契约清单、正确性九项、复杂度审计协议
docs/                  概念、配置、runner、设计取舍
scripts/               doctor / render / run-plain / run-orca
examples/              单 Agent、双 Agent 的配置样例
tests/                 用 stub agent 跑的端到端冒烟（不需要 API key）
AGENTS.md              给「修改本仓库」的 Agent 的约定
```

---

## 状态

`0.1.0` — 结构稳定；`plain` runner 有端到端测试（`tests/smoke.sh`，不需要 API key）；`orca` runner 生成建图脚本，尚未在 CI 验证。欢迎 Issue / PR，见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 许可

MIT，见 [LICENSE](LICENSE)。

## 安全

默认以 `danger-full-access` 运行的 Agent 会读你的文件、跑你的命令。**先读 [SECURITY.md](SECURITY.md)**，尤其是第一次跑之前先 `render.sh` 看一眼计划。
