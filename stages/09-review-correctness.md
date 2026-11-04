# 09 正确性评审

**角色**：`review_correctness`（能力档 high）
**输入**：集成分支的 diff、`contract/api.yaml`、`handoff/*-deviations.md`
**输出**：`handoff/09-correctness.md`

## 做什么

按 `references/review-correctness.md` 的九项，逐项给 `文件:行 | 级别 | 问题 | 理由`。

## 先读偏离记录

`handoff/04-fe-deviations.md` / `05-be-deviations.md` 是你最重要的输入。

- 偏离**已登记**：判断这个偏离是否可接受，写结论
- 偏离**未登记**却出现在 diff 里：这是 blocker。契约已经失效，后面所有判断都不可靠

## 三条禁止

1. **禁止审自己设计的部分。** 如果你是这份设计的作者，只做记录，把裁决交给另一个人或另一个 agent
2. **禁止用"整体不错"当结论。** 结论只有 `blocked: N 个问题` 或 `clean（附未覆盖项）`
3. **禁止顺手改代码**

## 九项按路径分级

重档（九项全过）：数据模型、迁移、事务、鉴权、并发、支付、上传
轻档：纯 UI、样式、文案、配置

分级规则见 reference。

## 产物

```markdown
# 正确性评审

| 位置 | 级别 | 问题 | 理由 |
|---|---|---|---|
| api/export.py:L44 | blocker | 未校验订单归属 | 传任意 id 可导出他人订单 |
| api/export.py:L71 | major | 导出失败后临时文件不清理 | 异常路径未 finally |
| web/Export.tsx:L12 | ok | — | 入口权限判断正确 |
| db/migrations/ | 未覆盖 | 未看索引设计 | 本次 diff 无迁移 |

结论：blocked: 1 个 blocker，1 个 major
```

## 出口

- [ ] 九项都有结论，含 `未覆盖`
- [ ] 每条 blocker 都能指出具体的越权/丢数据/崩路径
- [ ] 偏离记录逐条有判读
- [ ] 没有改代码
