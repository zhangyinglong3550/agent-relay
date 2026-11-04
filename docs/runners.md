# Runner

**spec 描述要什么，runner 决定怎么跑。**

这条边界必须守住，否则你的团队会被某个 app 绑死。`pipeline.json` 是资产，runner 是可替换的执行器。

---

## plain（默认，零额外依赖）

```bash
./scripts/run-plain.sh --dry-run       # 只看会跑什么
./scripts/run-plain.sh                 # 跑，到人工闸门停下
./scripts/run-plain.sh --start-from 04-fe-dev
./scripts/run-plain.sh --only-agent claude
```

需要：`python3` + 任意一个 Agent CLI + `git`。

行为：

1. 按 `deps` 拓扑排序
2. 每个 agent 节点：组装 prompt → 起子进程 → **stdout 落到 `produces[0]`**
3. 人工闸门：打印提示，等回车（`--yes` 跳过，危险）
4. 每节点一份日志 + 一份 `runs/<id>/state.json`，失败可 `--start-from` 续跑
5. 失败默认停住，`--keep-going` 继续

**没有并行。** 这是有意的：顺序执行在单机上更可预测，而这条流水线本来大部分阶段就是串行的。并行只发生在 orca runner。

### 关键实现选择

**Agent 的输出就是交接物。** 不解析格式、不提取 JSON、不要求 Agent 调 API。说明书里已经要求它"把结果作为回复正文输出"。

这让任何 CLI 都能接入——这是本项目能兼容五个厂商、而大部分工具只能兼容两家的根本原因。

### 多轮：让澄清收敛

澄清要一问一答，但 runner 是单次调用。`--rounds` 把这两件事接上：

```bash
./scripts/run-plain.sh --only-node 00a-clarify --rounds 3
```

过程：

1. 第 1 轮：Agent 输出问题清单，末尾是 `## 待确认`
2. runner 解析出待确认项，**暂停**，告诉你写进 `options.answersFile`（默认 `handoff/00a-answers.md`）
3. 你写完回车 → 第 2 轮：上次输出 + 你的答复一起喂回去
4. 当 `## 待确认` 下写「无」时，自动停

`--yes` 会跳过暂停（用于测试），但**真实使用别用**——跳过暂停等于让 Agent 自己回答自己的问题。

多轮只对一个节点生效，必须配 `--only-node`。理由：整条链跑多轮没有语义，每一站该跑几次是不一样的。

---

## orca

```bash
./scripts/run-orca.sh            # 生成建图脚本并打印
./scripts/run-orca.sh --apply    # 真的建 Run + Task
```

需要：Orca 已安装并在运行。

它做三件事：

1. 用 `pipeline.json` 建一个 Run
2. 每个节点建一个带 `--deps` 的 Task，并把 spec 落成 `specs/<id>.md`
3. 打印下一步命令

**它不起 worker。** 起 worker 需要一个"协调者"在场按 `task-list --ready` 派活——那是 Agent 的活，不是脚本的活。

协调者可以用任意 Agent，配上本仓库的说明书即可。协调循环只有一条规则：

```
被唤醒 → task-list --ready → 起 ready 的 → 结束本轮
```

（Orca 明令禁止轮询，所以不要写 watch 脚本。）

### orca 相对 plain 多出什么

| 能力 | plain | orca |
|---|---|---|
| 并行节点 | ❌ | ✅ |
| 完成唤醒 | ❌（顺序等待） | ✅ |
| worktree 隔离 | 手动 | ✅ `--worktree new-child` |
| 断点续跑 | `--start-from` | Task 状态天然保留 |
| 前置依赖 | 文件 | 装 app |

**plain 是完整可用的降级，不是玩具。**

---

## 没有 Orca 的同事怎么办

**正常用 `run-plain.sh`，其它什么都不用装。** Orca 只是并行和唤醒的加速器，不是前置条件。

完整步骤：

```bash
# 1. 拿到仓库
git clone https://github.com/<you>/agent-relay.git ~/tools/agent-relay

# 2. 看自己有什么
cd ~/tools/agent-relay
./scripts/doctor.sh
#   → 检测到哪些 CLI、能跑哪一档、哪一步会被跳过

# 3. 生成本地配置
cp pipeline.local.example.json pipeline.local.json
$EDITOR pipeline.local.json
#   至少把 9 个角色的 agent 填上（只有 claude 就全填 claude，见 examples/single-agent.json）

# 4. 指向自己的项目，产物才会落在项目里
#    "options": { "projectRoot": "/path/to/your/project" }

# 5. 看一眼计划
./scripts/render.sh
./scripts/run-plain.sh --dry-run

# 6. 开跑
./scripts/run-plain.sh
```

### 单 Agent（C 档）要多守两条

`doctor.sh` 会明确告诉你跳过了什么。除此之外，两条脚本管不了的纪律：

1. **每个角色冷启动新会话**，只喂文件，不喂上一个角色的对话
2. **评审强制"至少列出 2 个问题"**，否则会退化成自我确认

### 他们少了什么

| 少了 | 影响 | 缓解 |
|---|---|---|
| 并行 | 前后端开发串行，墙钟时间约翻倍 | 接受，或分批跑 |
| 完成唤醒 | 你得等着，或者手动 `--start-from` | 长任务用 `--only-node` 拆开跑 |
| worktree 隔离 | 两个并行 worker 会抢同一个工作区 | plain 默认串行，本来就不并行 |
| 一人一档 | 没有交叉评审（C 档） | 如实标注"未做交叉评审" |

**不要为了对齐 Orca 的体验去装 Orca。** 这套东西的价值在 `stages/` 和 `pipeline.json`，不在并行。

### 一句话版本

同事拿到仓库后真正要改的只有一个文件：`pipeline.local.json`。其余都是 `./scripts/*.sh`。

---

## 自定义 runner

最简实现只需要 20 行：读 `pipeline.json`，拓扑排序，按 `adapters.json` 拼命令，把 stdout 写成文件。

`./scripts/render.sh` 已经把"节点 → agent → model → effort → 命令"解析好了，你可以直接对着它的输出实现。

如果你写了新 runner，欢迎 PR——尤其欢迎：

- GitHub Actions runner（把每个节点做成 job，`needs` 表达依赖，人工闸门用 issue 审批）
- Temporal / Airflow runner（长流程、多机、审计）
- 带 UI 的 runner（看进度、点闸门）

---

## 跨平台

- macOS / Linux：直接跑
- Windows：WSL 或 Git Bash。原生 cmd 不支持，脚本里有 bash 语法

如果需要原生 Windows 支持，把 `relay.py` 当主体、.sh 当薄封装替换掉即可——逻辑都在 Python 里。
