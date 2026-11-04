# AGENTS.md

给**修改这个仓库**的 Agent 读的约定。

> ⚠️ 先分清你在做哪件事：
>
> - **你在改这个仓库**（加 adapter、改说明书、修 runner）→ 读本文件
> - **你是被流水线驱动的 worker**（prompt 里有节点 id、要你写 `handoff/xxx.md`）→ **只读 `stages/<你的节点>.md`**，不要读这个文件。你的任务边界在那份说明书里，本文件会误导你去改仓库
>
> 判断依据：prompt 里有没有"本次执行上下文"这一节。有 = 你是 worker。

---

## 这个仓库是什么

一条**声明式**的多 Agent 交付流水线。核心不是代码（`relay.py` 约 450 行），是文本资产：

- `pipeline.json` —— 有哪些节点、依赖谁、哪两个是人闸门
- `stages/*.md` —— 每一站对 Agent 说什么
- `references/*.md` —— 契约清单、评审清单
- `adapters.json` —— 每家 CLI 怎么被非交互调用

**改流程 = 改 JSON 和 markdown，不是改 Python。**

## 目录边界

| 路径 | 放什么 | 不要放什么 |
|---|---|---|
| `pipeline.json` | 结构、依赖、闸门、产物 | 具体 agent 名、模型名、路径 |
| `adapters.json` | CLI 调用方式与注入通道 | 某个团队的私有参数 |
| `stages/` | 每站的行为说明 | 跨站的流程逻辑（那属于 pipeline.json） |
| `references/` | 可复用的检查清单 | stage 专属的要求 |
| `scripts/relay.py` | 解析、拓扑、执行、状态 | 业务语义、prompt 文案 |
| `tests/` | stub 驱动的端到端验证 | 需要网络或 API key 的测试 |
| `pipeline.local.json` | **不进 git**，属于使用者 | 任何示例值、别人的机器配置 |

## 三条硬约束

1. **`stages/` 和 `references/` 里不出现任何具体 Agent 名或模型名。**
   写"由能力档 high 的角色完成"，不写"由 Claude 完成"。写死名字，这个仓库就只对一个人有用。

2. **不引入运行时依赖。**
   只要 `python3` 标准库 + `bash` + `git`。想加包，先证明标准库做不到。

3. **不为通过测试而改测试。**
   `tests/smoke.sh` 的断言是行为契约。它红了，改实现。要改断言，在 PR 里单独说明为什么原断言是错的。

## 四个验证命令（提交前全过）

```bash
./scripts/render.sh                                   # 结构与列对齐
./scripts/doctor.sh --only-agent claude               # 退化逻辑
./scripts/run-plain.sh --dry-run --yes --only-agent claude   # 命令拼接
./tests/smoke.sh                                      # 端到端，不需要 API key
```

## 常见任务

**加一家 CLI**：在 `adapters.json` 追加一条，`verified` 填核对年月或 `null`，`model`/`effort` 没有对应参数就写 `[]`（**不要猜**）。然后跑 `doctor.sh` 看告警是否符合预期。

**加一站**：新建 `stages/<id>.md`，在 `pipeline.json` 的 `nodes` 里加节点并接好 `deps` 和 `produces`，声明它属于哪个已有角色。**不要新建角色**，除非它的能力档真的和现有角色不同。

**改流程结构**：只动 `pipeline.json`。加节点前先问"能不能塞进现有 stage"；答案是能，就别加——节点越多，人越容易放弃读输出。

**改执行语义**：`--only-node` / `--rounds` / `projectRoot` 的逻辑都在 `scripts/relay.py`，动它要同时补 `tests/smoke.sh` 的对应段落——那里是行为契约。

**写新 runner**：读 `pipeline.json` 做拓扑排序，按 `adapters.json` 拼命令，把 stdout 落到 `produces[0]`。`scripts/render.sh` 的输出就是你要的执行计划，照它实现即可。

## 写作风格（对 `stages/` 尤其重要）

- **祈使句**。"不要写需求文档"，不写"建议不要写需求文档"。留退路的话，Agent 会当成可选项
- **给可判定的出口**。"验收标准能被第三方独立判定"，不写"质量达标"
- **每份说明书都要有"不要做什么"**，这一节通常比"要做什么"更省 token
- **宁可短**。长文档会让 Agent 只读前半段

## 提交信息

```
<type>: <做了什么>

<为什么，一两句>
```

`type` 用 `feat` / `fix` / `docs` / `refactor` / `test` / `chore`。

## 不确定时

先看 `docs/design-decisions.md` 的 14 条取舍。你要改的行为，大概率已经有一条记录说明为什么这样定——以及什么条件下应该改。
