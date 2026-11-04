# 贡献

## 最想收到的 PR

按价值排序：

1. **新的 adapter**（`adapters.json` 一条 + 实测记录）——每多一家，能用的人就多一批
2. **新的 stage 说明书**（`stages/*.md`）——本项目的核心资产就是这些文本
3. **新的 runner**（GitHub Actions、Temporal…）
4. 某条设计取舍的反例——你说服我，我就改

## 加一个 adapter

```json
"myagent": {
  "title": "My Agent",
  "bin": "myagent",
  "prompt": ["-p", "{prompt}"],
  "model":  ["--model", "{model}"],
  "effort": [],
  "verified": "2026-11",
  "notes": "为什么这么拼，有什么坑"
}
```

要求：

- 必须实测过**非交互**调用（不是 TUI 里敲一下）
- `verified` 填你核对的年月，没核对过就填 `null`
- `model` / `effort` 没有对应参数就写 `[]`，**不要猜**

## 加一个 stage

- 一个 stage 只干一件事。想要"顺便也检查下 X"，那是另一个 stage
- 必须写清**出口条件**，且条件是能被检查的（不是"质量达标"）
- 必须写**不要做什么**——这一节往往比"要做什么"更能省 token

## 改 pipeline.json

流水线结构是契约。改之前开 issue 说清楚：

- 现在漏了什么
- 为什么不能在现有 stage 里解决

**不要为了减少节点而合并 stage。** 合并省的是你的阅读成本，付的是 Agent 的隔离度。

## 提交前

```bash
./scripts/render.sh                                   # 结构没坏
./scripts/doctor.sh --only-agent claude               # 退化逻辑对
./scripts/run-plain.sh --dry-run --only-agent claude  # 命令拼得对
./tests/smoke.sh                                      # 端到端（用 stub，不花钱）
```

四个都过，PR 就能看。

## 风格

- 中文为主，英文目录和代码注释可以混用
- 说明书用祈使句，别用"建议""可以考虑"——那是给人留退路，Agent 会当成可选项
- 宁可短，不要全
