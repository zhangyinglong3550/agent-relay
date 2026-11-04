# Agent Relay

[中文](README.md) | **English**

**Hand a one-line requirement down a relay of coding agents, and get an integration branch that's ready to accept.**

Agent Relay is not a framework and not a service. It's a small set of **text assets plus two scripts**: a declarative delivery pipeline that lets your command-line agents (Claude Code, Codex, Kimi, ZCode, DeepSeek Harness, …) work in fixed roles, pausing in exactly two places for a human.

- **Not tied to an agent** — roles are abstract slots; which CLI fills them is your config
- **Not tied to a runner** — Orca for parallel DAGs, plain bash if you don't have it
- **Not tied to a model** — agent, model and reasoning effort are configurable per role
- **Degrades honestly** — with one agent it drops to single-agent mode and tells you what it skipped

---

## The problem

Working with one agent is easy. A requirement that needs **four different things** — design, implement, verify behaviour, review quality — is not, and the best model for each is often different.

Hand-chaining costs more than four clicks: every handoff means re-explaining context, and the previous step's reasoning is lost.

Agent Relay makes one decision: **artifacts travel as files, never as conversation.**

Each step receives documents and a compilable skeleton, not a colleague mid-sentence. Two consequences: no context bleed, and every step is replayable and diffable.

---

## The pipeline

```
00a clarify ─▶ 00b scope ⛩ ─┬─▶ 01 frontend design ─┐
                            └─▶ 02 backend design  ─┤
                                                   ├─▶ 03 contract ⛩ ─┬─▶ 04 frontend dev ─┐
                                                   │                   └─▶ 05 backend dev  ─┤
                                                   │                                      ├─▶ 06 merge
                                                   └─▶ 07 e2e author ──────────────────────┘
                                                                                          │
                                            09 correctness review ◀─ 08 complexity audit ◀┘
                                                     │
                                                     └─▶ 10 e2e run ──▶ deliver
```

⛩ = human gate. **Only two**, both at points where a mistake multiplies.

Failure loop: E2E red → evidence goes back to the dev node (max 2 rounds) → same class of failure twice → back to the contract gate, not the dev node.

---

## Quick start

```bash
git clone https://github.com/<you>/agent-relay.git
cd agent-relay

./scripts/doctor.sh                              # what do I have?
cp pipeline.local.example.json pipeline.local.json
$EDITOR pipeline.local.json

./scripts/render.sh                              # what will actually run?
./scripts/run-plain.sh
```

---

## Capability tiers (auto-detected)

| Tier | You have | What happens |
|---|---|---|
| **A** | ≥3 different agents | Full pipeline, cross-review |
| **B** | 2 | Use model/effort to create the gap |
| **C** | 1 | Cold-start each role, **cross-review skipped and reported** |

Tier C rule: every role starts a **fresh session** and only receives files. Same model reviewing its own work in the same context is just self-confirmation.

---

## Configuration: three layers

```
pipeline.json          structure: nodes, deps, gates        ← shared, in git
pipeline.local.json    your agents, models, efforts         ← local, ignored
adapters.json          how each CLI takes prompt/model/effort ← shared, in git
```

```json
{
  "roles": {
    "plan":   { "agent": "claude", "model": "opus",   "effort": "high" },
    "dev":    { "agent": "kimi",   "model": "kimi-k3" },
    "verify": { "agent": "dsh",    "effort": "low" }
  }
}
```

Not every CLI accepts a model on the command line. `adapters.json` records what each one supports, and `doctor.sh` warns when a configured value cannot be injected — see [configuration](docs/configuration.md).

---

## Runners

| Runner | Needs | Gives you |
|---|---|---|
| `scripts/run-plain.sh` | any agent CLI + git | sequential, gates, resume. **Zero extra deps** |
| `scripts/run-orca.sh` | Orca | dependency-graph parallel, wake-on-complete, worktree isolation |

**Specs say what; runners decide how.** Otherwise your team gets locked into an app.

---

## Why these decisions

Every rule exists because something broke. See [docs/design-decisions.md](docs/design-decisions.md) — why only two gates, why design review has no veto, why design ships a compilable skeleton, why cheap models run tests but never author them, and why "E2E green" is not evidence of correctness.

---

## Status

`0.1.0` — structure is stable; `plain` runner is tested end-to-end (`tests/smoke.sh`, no API key needed); `orca` runner generates the graph but is not yet verified in CI.

MIT licensed. See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).
