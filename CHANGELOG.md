# 变更记录

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
