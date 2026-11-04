#!/usr/bin/env python3
"""Agent Relay — 把角色、Agent、模型解析成可执行计划，并可按顺序跑起来。

子命令:
    render   打印解析后的执行计划（不执行任何命令）
    doctor   检查本机环境、配置完整度、退化档位、注入通道告警
    run      按依赖顺序执行；人工闸门处停下等你确认

只依赖 Python 3.8+ 标准库。
"""

import argparse
import json
import os
import shlex
import shutil
import subprocess
import sys
import unicodedata
from datetime import datetime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

HUMAN = "human"
C = {
    "dim": "\033[2m", "b": "\033[1m", "r": "\033[0m",
    "ok": "\033[32m", "warn": "\033[33m", "err": "\033[31m", "cyan": "\033[36m",
}


def pad(text, width):
    """按终端显示宽度左对齐补齐（CJK 字符占两列）。"""
    text = str(text)
    shown = sum(2 if unicodedata.east_asian_width(ch) in "WF" else 1 for ch in text)
    return text + " " * max(0, width - shown)


def load_adapters():
    """读 adapters.json，丢掉 $comment 这类元字段。"""
    raw = load("adapters.json")
    return {k: v for k, v in raw.items() if not k.startswith("$")}


def load(name, optional=False):
    path = os.path.join(ROOT, name)
    if not os.path.exists(path):
        if optional:
            return None
        sys.exit(f"{C['err']}缺少 {name}{C['r']}")
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


# ---------------------------------------------------------------- resolve

def resolve(pipeline, local, adapters, force_agent=None):
    """把 DAG 节点 + 本地配置 + 适配器 解析成执行计划。"""
    defaults = local.get("defaults") or {}
    role_cfg = local.get("roles") or {}
    plan = []

    for node in pipeline["nodes"]:
        role = node.get("role")
        entry = {"node": node, "role": role, "kind": "agent"}

        if not role:
            entry.update(kind=HUMAN, agent=None, model=None, effort=None, adapter=None)
            plan.append(entry)
            continue

        cfg = dict(defaults)
        cfg.update(role_cfg.get(role) or {})
        agent = force_agent or cfg.get("agent")

        # --only-agent 是「模拟我这台机器只装了 A」，跨厂商的模型名不能沿用
        model = cfg.get("model")
        if force_agent and cfg.get("agent") and cfg["agent"] != force_agent:
            model = None
        adapter = adapters.get(agent) if agent else None
        entry.update(
            agent=agent,
            model=model,
            effort=cfg.get("effort"),
            adapter=adapter,
            tier=(pipeline.get("roles", {}).get(role) or {}).get("tier"),
        )
        plan.append(entry)

    return plan


def build_cmd(entry, prompt, cwd):
    """按适配器的 argv 模板拼命令。返回 (argv, 被忽略的字段)。"""
    adapter = entry["adapter"]
    model, effort = entry.get("model"), entry.get("effort")
    ignored = []

    def expand(tpl):
        out = []
        for token in tpl or []:
            out.append(
                token.replace("{prompt}", prompt)
                .replace("{model}", model or "")
                .replace("{effort}", effort or "")
                .replace("{cwd}", cwd)
            )
        return out

    argv = [adapter["bin"]]
    argv += expand(adapter.get("extra"))
    argv += expand(adapter.get("prompt"))

    if model:
        if adapter.get("model"):
            argv += expand(adapter["model"])
        else:
            ignored.append("model")
    if effort:
        if adapter.get("effort"):
            argv += expand(adapter["effort"])
        else:
            ignored.append("effort")

    return argv, ignored


# ---------------------------------------------------------------- prompt

def build_prompt(node, entry, cwd):
    stage = os.path.join(ROOT, node["stage"])
    body = open(stage, encoding="utf-8").read() if os.path.exists(stage) else ""

    lines = [body.strip(), "", "---", "## 本次执行上下文", ""]
    lines.append(f"- 节点: {node['id']}")
    if node.get("role"):
        lines.append(f"- 角色: {node['role']}（能力档 {entry.get('tier')}）")
    for key, value in (node.get("vars") or {}).items():
        lines.append(f"- {key}: {value}")
    lines.append(f"- 工作目录: {cwd}")

    deps = node.get("deps") or []
    if deps:
        lines += ["", "### 上游交接物（只读，必须全部读一遍）", ""]
        for dep in deps:
            dep_node = next((n for n in PIPELINE["nodes"] if n["id"] == dep), None)
            for produced in (dep_node or {}).get("produces", []):
                lines.append(f"- {produced}")

    produces = node.get("produces") or []
    if produces:
        lines += ["", "### 交付要求", ""]
        lines.append("把结果作为**本次回复的正文**输出，不要写到别处；运行器会把它落盘到：")
        for produced in produces:
            lines.append(f"- {produced}")
        lines.append("")
        lines.append("如果需要人拍板，在正文最后单列一节 `## 待确认`，逐条列出问题与你的建议。")

    return "\n".join(lines)


# ---------------------------------------------------------------- commands

def cmd_render(args):
    pipeline = load("pipeline.json")
    local = load("pipeline.local.json", optional=True) or {}
    adapters = load_adapters()
    plan = resolve(pipeline, local, adapters, args.only_agent)

    print(f"{C['b']}执行计划{C['r']}  ({len(plan)} 个节点)\n")
    head = "".join([
        pad("ID", 22), pad("ROLE", 26), pad("AGENT", 10),
        pad("MODEL", 18), pad("EFFORT", 8), "DEPS",
    ])
    print(C["b"] + head + C["r"])
    print(C["dim"] + "-" * 90 + C["r"])

    for entry in plan:
        node = entry["node"]
        gate = " ⛩" if entry["kind"] == HUMAN else ""
        role = (entry.get("role") or "human") + gate
        agent = entry.get("agent") or "-"
        model = entry.get("model") or "-"
        effort = entry.get("effort") or "-"
        deps = ",".join(node.get("deps") or []) or "-"
        print(pad(node["id"], 22) + pad(role, 26) + pad(agent, 10)
              + pad(model, 18) + pad(effort, 8) + deps)

    print()
    for entry in plan:
        if entry["kind"] != "agent" or not entry["adapter"]:
            continue
        _, ignored = build_cmd(entry, "<prompt>", os.getcwd())
        for field in ignored:
            print(f"{C['warn']}! {entry['node']['id']}: {entry['agent']} 不支持 {field}，"
                  f"将使用它自身配置{C['r']}")
    return 0


def cmd_doctor(args):
    pipeline = load("pipeline.json")
    adapters = load_adapters()
    local = load("pipeline.local.json", optional=True)

    problems, warnings, notes = [], [], []

    print(f"{C['b']}1) 本机已检测到的 Agent{C['r']}")
    detected = {}
    for key, adapter in adapters.items():
        path = shutil.which(adapter["bin"])
        detected[key] = path
        mark = f"{C['ok']}✓{C['r']}" if path else f"{C['dim']}·{C['r']}"
        print(f"   {mark} {key:<12} {adapter['bin']:<12} {path or '未安装'}")
    if not any(detected.values()):
        problems.append("一个 Agent 都没检测到")

    print(f"\n{C['b']}2) 配置{C['r']}")
    if not local:
        problems.append("缺少 pipeline.local.json（从 pipeline.local.example.json 复制）")
        print(f"   {C['err']}未找到 pipeline.local.json{C['r']}")
        plan = []
    else:
        plan = resolve(pipeline, local, adapters, args.only_agent)
        used = sorted({e["agent"] for e in plan if e["kind"] == "agent" and e.get("agent")})
        print(f"   角色数: {len(pipeline.get('roles', {}))}   使用中的 Agent: {', '.join(used) or '无'}")

        for entry in plan:
            node, role = entry["node"], entry.get("role")
            if entry["kind"] == HUMAN:
                continue
            if not entry.get("agent"):
                problems.append(f"{node['id']}: 角色 {role} 没有配置 agent")
                continue
            if entry["agent"] not in adapters:
                problems.append(f"{node['id']}: {entry['agent']} 不在 adapters.json 里")
                continue
            if not detected.get(entry["agent"]):
                problems.append(f"{node['id']}: {entry['agent']} 未安装（{adapters[entry['agent']]['bin']}）")
            _, ignored = build_cmd(entry, "<prompt>", os.getcwd())
            if ignored:
                label = "/".join(ignored)
                warnings.append(f"{node['id']}: {entry['agent']} 无法通过命令行注入 {label}，会用它自身配置")

    print(f"\n{C['b']}3) 能力档{C['r']}")
    if plan:
        used = {e["agent"] for e in plan if e["kind"] == "agent" and e.get("agent")}
        tier = "A 完整" if len(used) >= 3 else ("B 双档" if len(used) == 2 else "C 单档")
        print(f"   {tier}（{len(used)} 个不同 Agent）")
        if len(used) <= 1:
            notes.append("C 档：跳过交叉互审；每个角色必须冷启动新会话，只喂文件")
            notes.append("C 档：评审必须强制「至少列出 2 个问题」，否则会退化成自我确认")
    else:
        print("   无法判定")

    print(f"\n{C['b']}4) 风险{C['r']}")
    if plan:
        dev = {e["agent"] for e in plan if e.get("role", "") and str(e.get("role")).startswith("dev")}
        rev = {e["agent"] for e in plan if e.get("role") == "review_correctness"}
        if rev and dev and rev & dev:
            warnings.append(f"正确性评审与开发使用同一个 Agent（{', '.join(rev & dev)}），"
                            f"评审会退化为确认")
        for key, adapter in adapters.items():
            if detected.get(key) and adapter.get("verified") is None:
                notes.append(f"{key} 的调用方式未核对（verified=null），首次使用先跑一次最小任务")
        for entry in plan:
            if entry["kind"] != "agent" or not entry.get("agent"):
                continue
            if entry["node"]["id"].startswith(("08", "09", "10")) and entry.get("model"):
                pass

    def dump(title, items, color):
        if not items:
            return
        print(f"\n{C['b']}{title}{C['r']}")
        for item in items:
            print(f"   {color}•{C['r']} {item}")

    dump("问题（必须修）", problems, C["err"])
    dump("告警（建议看一眼）", warnings, C["warn"])
    dump("提示", notes, C["cyan"])

    if not problems and not warnings:
        print(f"\n{C['ok']}看起来可以跑。{C['r']}")
    return 1 if problems else 0


def topo(nodes):
    done, order, pending = set(), [], list(nodes)
    while pending:
        progressed = False
        for node in list(pending):
            if all(dep in done for dep in node.get("deps") or []):
                order.append(node)
                done.add(node["id"])
                pending.remove(node)
                progressed = True
        if not progressed:
            sys.exit(f"{C['err']}依赖成环: {[n['id'] for n in pending]}{C['r']}")
    return order


def cmd_run(args):
    pipeline = load("pipeline.json")
    local = load("pipeline.local.json")
    adapters = load_adapters()
    plan = {e["node"]["id"]: e for e in resolve(pipeline, local, adapters, args.only_agent)}
    options = local.get("options") or {}

    run_id = datetime.now().strftime("%Y%m%d-%H%M%S")
    run_dir = os.path.join(ROOT, options.get("runDir", "runs"), run_id)
    os.makedirs(run_dir, exist_ok=True)
    state_path = os.path.join(run_dir, "state.json")
    state = {"run": run_id, "nodes": {}, "startedAt": run_id}

    def save():
        with open(state_path, "w", encoding="utf-8") as fh:
            json.dump(state, fh, ensure_ascii=False, indent=2)

    save()
    started = False
    for node in topo(pipeline["nodes"]):
        if args.start_from and not started:
            started = node["id"] == args.start_from
            if not started:
                continue
        entry = plan[node["id"]]
        print(f"\n{C['b']}▶ {node['id']}{C['r']} {C['dim']}({entry.get('role') or 'human'}){C['r']}")

        # ---- 人工闸门
        if entry["kind"] == HUMAN:
            gate = node.get("gate") or {}
            print(f"   {C['cyan']}{gate.get('prompt', '请确认后继续')}{C['r']}")
            if gate.get("check"):
                target = gate["check"]
                exists = os.path.exists(os.path.join(ROOT, target))
                mark = f"{C['ok']}存在{C['r']}" if exists else f"{C['err']}不存在{C['r']}"
                print(f"   检查产物: {target} → {mark}")
            if args.yes:
                print(f"   {C['dim']}--yes：跳过等待{C['r']}")
            else:
                try:
                    input(f"   {C['b']}回车继续，Ctrl-C 中止…{C['r']} ")
                except (EOFError, KeyboardInterrupt):
                    print(f"\n{C['warn']}已停在 {node['id']}{C['r']}")
                    save()
                    return 2
            state["nodes"][node["id"]] = {"status": "gate-passed", "at": datetime.now().isoformat()}
            save()
            continue

        # ---- Agent 节点
        adapter = entry.get("adapter")
        if not adapter:
            print(f"   {C['err']}没有可用的 agent，跳过{C['r']}")
            state["nodes"][node["id"]] = {"status": "skipped", "reason": "no agent"}
            save()
            continue

        cwd = os.path.abspath(os.path.join(ROOT, args.cwd or "."))
        prompt = build_prompt(node, entry, cwd)
        argv, ignored = build_cmd(entry, prompt, cwd)

        print(f"   {entry['agent']} {C['dim']}({entry.get('model') or 'default'}"
              f" / effort={entry.get('effort') or 'default'}){C['r']}")
        for field in ignored:
            print(f"   {C['warn']}·{C['r']} {field} 无法注入，使用该 Agent 自身配置")

        if args.dry_run:
            print(f"   {C['dim']}{shlex.join(argv)[:200]}…{C['r']}")
            state["nodes"][node["id"]] = {"status": "dry-run"}
            save()
            continue

        log_path = os.path.join(run_dir, f"{node['id']}.log")
        print(f"   {C['dim']}→ {os.path.relpath(log_path, ROOT)}{C['r']}")
        try:
            proc = subprocess.run(argv, cwd=cwd, capture_output=True, text=True, timeout=args.timeout)
        except subprocess.TimeoutExpired:
            print(f"   {C['err']}超时（{args.timeout}s），停在这里{C['r']}")
            state["nodes"][node["id"]] = {"status": "timeout"}
            save()
            return 3

        with open(log_path, "w", encoding="utf-8") as fh:
            fh.write(f"# argv\n{shlex.join(argv)}\n\n# stdout\n{proc.stdout}\n\n# stderr\n{proc.stderr}\n")

        produces = node.get("produces") or []
        if produces:
            rel = produces[0]
            if rel.endswith("/"):          # 目录型产物：落成 <dir>/<node>.md
                rel = rel + node["id"] + ".md"
            target = os.path.join(ROOT, rel)
            os.makedirs(os.path.dirname(target), exist_ok=True)
            with open(target, "w", encoding="utf-8") as fh:
                fh.write(proc.stdout.strip() + "\n")
            print(f"   {C['ok']}✓{C['r']} 写入 {rel}")

        ok = proc.returncode == 0 and proc.stdout.strip()
        state["nodes"][node["id"]] = {
            "status": "ok" if ok else "failed",
            "exit": proc.returncode,
            "agent": entry["agent"],
            "model": entry.get("model"),
            "effort": entry.get("effort"),
            "at": datetime.now().isoformat(),
        }
        save()

        if not ok:
            print(f"   {C['err']}退出码 {proc.returncode}，见 {os.path.relpath(log_path, ROOT)}{C['r']}")
            if not args.keep_going:
                print(f"   {C['dim']}修好之后：./scripts/run-plain.sh --start-from {node['id']}{C['r']}")
                return 1

    print(f"\n{C['ok']}跑完了。产物见 handoff/ ，运行记录见 {os.path.relpath(run_dir, ROOT)}/{C['r']}")
    return 0


# ---------------------------------------------------------------- main

def main():
    parser = argparse.ArgumentParser(prog="relay", description="Agent Relay")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("render", help="打印执行计划")
    p.add_argument("--only-agent", help="强制所有角色使用同一个 agent（用于验证退化）")
    p.set_defaults(func=cmd_render)

    p = sub.add_parser("doctor", help="检查环境与配置")
    p.add_argument("--only-agent", help="按「只有一个 agent」模拟")
    p.set_defaults(func=cmd_doctor)

    p = sub.add_parser("run", help="顺序执行")
    p.add_argument("--dry-run", action="store_true", help="只打印命令，不执行")
    p.add_argument("--yes", action="store_true", help="自动通过人工闸门（危险）")
    p.add_argument("--start-from", help="从某个节点开始（断点续跑）")
    p.add_argument("--only-agent", help="强制所有角色使用同一个 agent")
    p.add_argument("--keep-going", action="store_true", help="某节点失败也继续")
    p.add_argument("--cwd", help="Agent 的工作目录，默认仓库根")
    p.add_argument("--timeout", type=int, default=45 * 60, help="单节点超时秒数")
    p.set_defaults(func=cmd_run)

    args = parser.parse_args()
    global PIPELINE
    PIPELINE = load("pipeline.json")
    return args.func(args)


PIPELINE = None

if __name__ == "__main__":
    sys.exit(main())
