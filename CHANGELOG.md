# 变更记录

## 0.2.1

**新增**

- **多项目**：`--project <dir>` 读项目根的 `.agent-relay.json`，并自动把 `projectRoot` 补成该目录。
  `--config <file>` 和 `$RELAY_CONFIG` 可显式指定配置。优先级：
  `--config` > `$RELAY_CONFIG` > `<project>/.agent-relay.json` > 仓库的 `pipeline.local.json`。
- 相对路径的 `projectRoot` 改为按配置文件所在目录解析（之前按仓库目录）。
- `render.sh` / `doctor.sh` 会打印这次用的是哪份配置。

**测试**

- smoke 扩到 11 段：两个项目各跑各的、产物不串；`--config` 生效。

## 0.2.0

**新增**

- `options.projectRoot`：产物与 Agent 工作目录可以指向业务项目，不再只能跑在 relay 仓库里。
  `render.sh` / `doctor.sh` 会显示产物根，`doctor.sh` 会校验目录是否存在。
- `--only-node` + `--rounds N`：同一节点多轮收敛。第 1 轮出 `## 待确认` → 你写进
  `options.answersFile` → 回车 → 下一轮带着答复继续，直到「无」。
- `options.clarifyMode`：`auto` / `light` / `standard` / `deep`。**澄清按需求大小分诊**——
  单文件改动不问、单模块问一轮、跨前后端才走三轮。档位透传进 prompt。
- `stages/00a-clarify.md` 重写：分诊表、多轮规则（已确认的不许重问）、出口条件。

**变更**

- `--rounds` 必须配 `--only-node`，否则报错——整链多轮没有语义。
- 运行日志改为 `runs/<id>/<node>.r<N>.log`，多轮各自留档。
- `state.json` 节点记录新增 `rounds` 与 `workRoot`。

**测试**

- smoke 从 6 段扩到 9 段：多轮收敛、projectRoot、clarifyMode 透传。

## 0.1.0

首个可用版本。

**结构**

- 12 节点流水线：澄清 → 需求冻结 ⛩ → 前端/后端方案 → 契约冻结 ⛩ → 前端/后端开发 + E2E 用例 → 合并 → 复杂度审计 + 正确性评审 → E2E 执行
- 9 个角色槽位，按 `high` / `medium` / `low` 三档能力分层，**不含任何具体 Agent 名**
- 2 个人工闸门，判据是"错了会乘以几"

**Runner**

- `plain`：纯 bash + python3，顺序执行、人工闸门、`--start-from` 断点续跑、`--dry-run`
- `orca`：把 `pipeline.json` 生成 Orca 的 Run + 带 `--deps` 的 Task（生成建图脚本，未在 CI 验证）

**配置**

- 三层：`pipeline.json`（结构）/ `adapters.json`（注入方式）/ `pipeline.local.json`（你的人）
- 每个角色可配 `agent` + `model` + `effort`
- `doctor.sh` 校验并告警"配了但注入不进去"的字段
- 三档自动退化（A/B/C），单 Agent 时明确提示跳过交叉互审

**适配器**

- 已核对：claude、codex、kimi、zcode、dsh、stub
- 未核对：pi、cursor、opencode（`verified: null`，`doctor.sh` 会提示）

**测试**

- `tests/smoke.sh`：用 stub agent 跑完整条流水线，不需要 API key

**已知限制**

- zcode / dsh 的模型与思考等级无法通过命令行注入，只能改它们自己的配置
- E2E 用例的格式（yaml 示例）没有配套执行器，`10-e2e-run` 依赖你的测试框架
- 没有跨平台的原生 Windows 入口（用 WSL 或 Git Bash）
