#!/usr/bin/env bash
# Orca 执行器：把 pipeline.json 变成 Orca 的 Run + 带依赖的 Task。
#
#   ./scripts/run-orca.sh            生成脚本并打印（不执行）
#   ./scripts/run-orca.sh --apply    真的建 Run 和 Task
#
# 建完之后由你或协调者 Agent 按需起 worker：
#   orca orchestration task-list --ready
#   orca orchestration worker-start --task <id> --agent <agent> --model <model> --effort <high>
#
# 本脚本只建图，不起 worker。起 worker 需要一个"协调者"在场，
# 那是 Agent 的活，不是脚本的活——见 docs/runners.md。
set -euo pipefail
cd "$(dirname "$0")/.."

command -v orca >/dev/null 2>&1 || {
  echo "没找到 orca。没有 Orca 请用 ./scripts/run-plain.sh" >&2
  exit 1
}
[[ -f pipeline.local.json ]] || {
  echo "缺少 pipeline.local.json：cp pipeline.local.example.json pipeline.local.json" >&2
  exit 1
}

APPLY=0
[[ "${1:-}" == "--apply" ]] && APPLY=1
OUT="runs/orca-plan-$(date +%Y%m%d-%H%M%S).sh"
mkdir -p runs

python3 - "$OUT" <<'PY'
import json, os, sys

out_path = sys.argv[1]
pipeline = json.load(open("pipeline.json", encoding="utf-8"))
local = json.load(open("pipeline.local.json", encoding="utf-8"))
roles = local.get("roles") or {}
defaults = local.get("defaults") or {}

sys.path.insert(0, "scripts")
import relay  # 复用 relay.py 的 prompt 组装，保证两种 runner 产出的 spec 完全一致

relay.PIPELINE = pipeline
os.makedirs("specs", exist_ok=True)

ID_HELPER = r'''
__ID__() {
  python3 -c 'import sys,json
d=json.load(sys.stdin)
def walk(o):
    if isinstance(o,dict):
        for k in ("taskId","task_id","runId","run_id","id"):
            if isinstance(o.get(k),str): return o[k]
        for v in o.values():
            r=walk(v)
            if r: return r
    if isinstance(o,list):
        for v in o:
            r=walk(v)
            if r: return r
    return None
print(walk(d) or "")'
}
'''.replace("__ID__", "_id")

lines = [
    "#!/usr/bin/env bash",
    "set -euo pipefail",
    ID_HELPER,
    'RUN=$(orca orchestration run-create --objective "relay:%s" --json | _id)' % pipeline.get("name", "default"),
    'echo "run: $RUN"',
    "",
]

ids = {}
for node in pipeline["nodes"]:
    role = node.get("role")
    var = "T_" + node["id"].replace("-", "_")
    cfg = dict(defaults)
    if role:
        cfg.update(roles.get(role) or {})

    # spec 落成文件，内容和 plain runner 喂给 Agent 的完全一致
    entry = {"tier": (pipeline.get("roles", {}).get(role) or {}).get("tier") if role else None}
    spec_path = os.path.join("specs", node["id"] + ".md")
    open(spec_path, "w", encoding="utf-8").write(relay.build_prompt(node, entry, os.getcwd()))

    deps_vars = [ids[d] for d in (node.get("deps") or []) if d in ids]
    if deps_vars:
        fmt = "[" + ",".join('"%s"' for _ in deps_vars) + "]"
        lines.append('D_%s=$(printf %s)' % (var, "'" + fmt + "'" + " " + " ".join('"$%s"' % v for v in deps_vars)))
        deps_arg = '--deps "$D_%s"' % var
    else:
        deps_arg = ""

    lines.append("# %s  role=%s  agent=%s" % (node["id"], role or "human", cfg.get("agent", "-")))
    lines.append(
        '%s=$(orca orchestration task-create --task-title "%s" --spec-file %s %s --run "$RUN" --json | _id)'
        % (var, node["id"], spec_path, deps_arg)
    )
    lines.append('echo "%s: ${%s}"' % (node["id"], var))
    ids[node["id"]] = var
    lines.append("")

lines += [
    "echo",
    'echo "建好了。下一步："',
    'echo "  orca orchestration task-list --ready --brief"',
    'echo "  orca orchestration worker-start --task <id> --agent <agent>"',
]

open(out_path, "w", encoding="utf-8").write("\n".join(lines) + "\n")
print(out_path)
PY

chmod +x "$OUT"
echo "生成: $OUT"
echo
sed -n '1,40p' "$OUT"

if [[ $APPLY -eq 1 ]]; then
  echo
  echo "== 开始建图 =="
  bash "$OUT"
else
  echo
  echo "未执行。确认无误后：bash $OUT    （或加 --apply）"
fi
