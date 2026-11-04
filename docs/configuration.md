# 配置

三层，职责不重叠。

| 文件 | 内容 | 进 git | 谁改 |
|---|---|---|---|
| `pipeline.json` | 有哪些节点、依赖谁、谁是闸门、产出什么 | ✅ | 团队（PR） |
| `adapters.json` | 每种 CLI 怎么注入 prompt / model / effort | ✅ | 团队（PR） |
| `pipeline.local.json` | 我的角色用哪个 agent、模型、思考等级 | ❌ | 每个人自己 |

---

## 1. pipeline.json：结构与角色

`roles` 里只声明**能力档**，不写 agent 名字：

```json
"roles": {
  "clarify": { "tier": "high", "title": "需求澄清" },
  "dev_be":  { "tier": "medium", "title": "后端开发" }
}
```

档位只有三档，含义是**推理能力**，不是价格：

- `high`：要做判断、归因、抽象（澄清、设计、正确性评审、写用例）
- `medium`：按骨架填空（开发、合并）
- `low`：格式强约束的机械活（复杂度审计、跑 E2E）

`nodes` 里每个节点声明：`id`、`role`、`stage`（说明书路径）、`deps`、`produces`、以及可选的：

- `kind: "human"` + `gate`：人工闸门
- `isolate: true`：需要独立 worktree
- `blind: true`：不许读实现（提示 runner 收紧上下文）
- `vars`：传给说明书模板的变量（如 `SIDE=frontend`）

**改流程只改这个文件**，不要改脚本。

---

## 2. adapters.json：模型和思考等级到底怎么注入

这是最容易踩坑的地方。同一个 `--model`，五种 CLI 有五种命运。

```json
"claude": {
  "bin": "claude",
  "prompt": ["-p", "{prompt}"],
  "model":  ["--model", "{model}"],
  "effort": ["--effort", "{effort}"]
}
```

占位符：`{prompt}` `{model}` `{effort}` `{cwd}`。

**`model` 或 `effort` 是空数组，就表示这家 CLI 没有这个参数。**

| 能不能注入 | 后果 |
|---|---|
| `model` 有模板 | 生效 |
| `model` 为空 | **静默使用该 Agent 自己的配置**，`doctor.sh` 会告警 |
| `effort` 有模板 | 生效 |
| `effort` 为空 | 同上 |

已知的现实约束（2026-11 核对）：

| Agent | model | effort | 说明 |
|---|---|---|---|
| claude | ✅ `--model` | ✅ `--effort` | 最完整 |
| codex | ✅ `-m` | ⚠️ 走 `-c model_reasoning_effort=` | 不是独立 flag |
| kimi | ✅ `-m` | ❌ | 思考等级由模型自身决定 |
| zcode | ❌ | ❌ | 模型写在它自己的配置里 |
| dsh | ❌ | ❌ | 模型在 profile 的 patch 层 |

所以**"配置了 model"不等于"模型真的换了"**。跑之前务必：

```bash
./scripts/doctor.sh
```

看到 `无法通过命令行注入 model，会用它自身配置` 就是没生效。

### 想强制生效怎么办

对 zcode / dsh 这类，用它们的配置机制，而不是命令行：

- **zcode**：改它自己的模型配置，或者按角色起不同 profile
- **dsh**：`dsh --profile <name> --patch overrides.yml` 里写模型，然后给这个角色配一个自定义 adapter

---

## 3. pipeline.local.json：你的一台机器

```json
{
  "defaults": { "effort": "medium" },
  "roles": {
    "clarify":   { "agent": "claude", "model": "opus", "effort": "high" },
    "dev_be":    { "agent": "zcode" },
    "e2e_run":   { "agent": "dsh", "effort": "low" }
  },
  "options": {
    "projectRoot": "/path/to/your/project",
    "clarifyMode": "auto",
    "answersFile": "handoff/00a-answers.md",
    "branchPrefix": "relay/",
    "runDir": "runs",
    "stopAtGates": true,
    "maxLoopRounds": 2,
    "wallClockMinutesPerNode": 45
  }
}
```

- 没写的字段继承 `defaults`
- `agent` 必须是 `adapters.json` 里存在的 key
- 缺角色 → `doctor.sh` 报问题，不让跑

### options 说明

| 键 | 作用 | 默认 |
|---|---|---|
| **`projectRoot`** | **产物和 Agent 工作目录的根**。指向你的业务项目，`handoff/`、`contract/`、`e2e/` 就落在项目里，而不是落在 agent-relay 仓库里 | `null`（= 仓库自己） |
| **`clarifyMode`** | 澄清强度：`auto` 按需求大小自动判档，或强制 `light` / `standard` / `deep` | `auto` |
| **`answersFile`** | 多轮澄清时，你写答复的文件 | `handoff/00a-answers.md` |
| `branchPrefix` | 集成分支前缀 | `relay/` |
| `runDir` | 运行记录目录（始终在仓库内，不进 git） | `runs` |
| `stopAtGates` | 到人工闸门是否暂停 | `true` |
| `maxLoopRounds` | 修复回路上限，超过就升级到人 | `2` |
| `wallClockMinutesPerNode` | 给人看的预期时长，不强制 | `45` |

`projectRoot` 是最容易搞错的一个。不设它，你会在 agent-relay 目录里看到 `handoff/`，而代码改动在另一个仓库——产物和代码分家，评审那站读 diff 会读错地方。

```bash
# 设对之后，render 第一行会显示
执行计划  (12 个节点)  产物根: /path/to/your/project
```

`clarifyMode` 的判档规则写在 `stages/00a-clarify.md`：**单文件改动不问、单模块问一轮、跨前后端才走三轮**。拿不准按 `standard`，不要默认 `deep`。


### 校验

```bash
./scripts/doctor.sh                          # 按你的配置
./scripts/doctor.sh --only-agent claude      # 模拟「只有 claude」会怎样
```

第二个命令是**给同事用的**：它会把退化后的档位、被跳过的步骤一次说清。

---

## 3.5 多项目

`projectRoot` 一个文件只能指一个项目。真正的做法是**每个项目带自己的配置**，工具只装一份。

在项目根放 `.agent-relay.json`（内容和 `pipeline.local.json` 一样，通常更短）：

```json
{
  "defaults": { "agent": "claude", "effort": "medium" },
  "roles": { "clarify": { "model": "opus", "effort": "high" } }
}
```

然后：

```bash
./scripts/run-plain.sh --project ~/code/project-a
```

`--project` 做两件事：

1. 读 `~/code/project-a/.agent-relay.json`（没有就退回仓库自带的配置）
2. 把 `projectRoot` 补成 `~/code/project-a`——产物和 Agent 工作目录都在这

**优先级**：

```
--config <file>  >  $RELAY_CONFIG  >  <project>/.agent-relay.json  >  仓库的 pipeline.local.json
```

相对路径的 `projectRoot` 按**配置文件所在目录**解析，不按仓库目录——所以 `.agent-relay.json` 里可以直接写 `"projectRoot": "."`。

CI 里用环境变量更省事：

```bash
RELAY_CONFIG=./ci/relay.json ./scripts/run-plain.sh --only-node 01-fe-design
```

---

## 4. 三档退化

| 档 | 判定 | 自动发生什么 |
|---|---|---|
| A | ≥3 个不同 agent | 交叉评审，全流程 |
| B | 2 个 | 用 model/effort 拉开强弱 |
| C | 1 个 | 每角色冷启动分饰；**跳过交叉互审**并在报告里标注 |

`doctor.sh` 自动判定，不需要你声明。

C 档的两条附加纪律（脚本无法强制执行，写在 SKILL 里靠人守）：

1. 每个角色**冷启动新会话**，只喂文件，不喂上一个角色的对话
2. 评审必须强制"至少列出 2 个问题"，否则会退化成自我确认
