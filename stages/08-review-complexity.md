# 08 复杂度审计

**角色**：`review_complexity`（能力档 low——格式硬约束，便宜模型足够）
**输入**：集成分支的 diff、`handoff/*-deviations.md`
**输出**：`handoff/08-complexity.md`

## 做什么

按 `references/review-complexity.md` 的协议，逐行找出**可以删掉的东西**。

一句话概括你的目标：**让这个 diff 变短。**

## 关键边界

- 只审过度设计。正确性、安全、性能**不是你的活**，看到就写一行「疑似正确性问题，转 09」然后停手
- **只列不改**，这一站不写任何代码
- 你输出的是**提议**，不是执行令

## 为什么这一站可以是便宜模型

因为输出是强格式的：五个 tag + 一行一条 + 结尾一个数字。不需要品味，需要对规则的老实执行。

反过来说，**这一站最容易犯的错是"为了显得有产出而硬凑"**。没东西可删就写 `Lean already. Ship.`，没人会怪你。

## 产物

```markdown
# 复杂度审计

auth/login.ts:L12-38: stdlib: 27 行邮箱校验类. "@" in email 够用，真正校验是确认邮件.
api/client.ts:L4: native: 为一个格式化引入 moment. Intl.DateTimeFormat，0 依赖.
repo.py:L88: yagni: 单实现的 AbstractRepository. 摊平，等第二个实现出现.

net: -54 lines possible.
```

## 出口

- [ ] 每条都有 `文件:行` + tag + 替代方案
- [ ] 结尾有 `net: -N` 或 `Lean already`
- [ ] 没有评论风格、命名、注释
- [ ] 没有直接改代码
