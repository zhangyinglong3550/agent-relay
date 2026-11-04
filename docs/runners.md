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

这让任何 CLIT 都能接入——这是本项目能兼容五个厂商、而大部分工具只能兼容两家的根本原因。

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

## 自定义 runner

最简实现只需要 20 行：读 `pipeline.json`，拓扑排序，按 `adapters.json` 拼命令，把 stdout 写成文件。

`./scripts/render.sh` 已经把"节点 → agent → model → effort → 命令"解析好了，你可以直接对着它的输出实现。

如果你写了新 runner，欢迎 PR——尤其欢迎：

- GitHub Actions runner（把每个节点做成 job，`needs` 表达依赖，人工闸门用 issue 审批）
- Temporal / Airflow runner（长流程、多机、审计）
- 带 UI 的 runner（看进度、点闸门）

---

## 没有 Orca 的同事怎么用

1. `./scripts/doctor.sh` —— 看自己有什么
2. `cp pipeline.local.example.json pipeline.local.json` —— 按实际填
3. `./scripts/run-plain.sh --dry-run` —— 确认命令合理
4. `./scripts/run-plain.sh` —— 跑

C 档（只有一个 Agent）时记得守两条：**冷启动、强制找问题**。

---

## 跨平台

- macOS / Linux：直接跑
- Windows：WSL 或 Git Bash。原生 cmd 不支持，脚本里有 bash 语法

如果需要原生 Windows 支持，把 `relay.py` 当主体、.sh 当薄封装替换掉即可——逻辑都在 Python 里。
