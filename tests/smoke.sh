#!/usr/bin/env bash
# 端到端冒烟：不调用任何真实模型，验证 runner / 配置 / 产物落盘是否正确。
#
#   ./tests/smoke.sh
#
# 用一个假 Agent（relay-stub）把所有角色都接管，跑完整条流水线。
# 适合放进 CI：不需要 API key，不花钱，几秒跑完。
set -euo pipefail

SRC="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "✗ $*" >&2; exit 1; }
ok()   { echo "✓ $*"; }

echo "== 准备 =="
mkdir -p "$TMP/bin" "$TMP/repo"
cp -R "$SRC"/. "$TMP/repo/"
rm -rf "$TMP/repo/runs" "$TMP/repo/handoff" "$TMP/repo/contract" "$TMP/repo/e2e" "$TMP/repo/specs"

cat > "$TMP/bin/relay-stub" <<'STUB'
#!/usr/bin/env bash
prompt="$1"
echo "# STUB 产出"
echo
echo "收到的说明长度: ${#prompt}"
echo "其余参数: ${*:2}"
STUB
chmod +x "$TMP/bin/relay-stub"
export PATH="$TMP/bin:$PATH"

cat > "$TMP/repo/pipeline.local.json" <<'JSON'
{
  "defaults": { "agent": "stub", "effort": "medium" },
  "roles": {},
  "options": { "stopAtGates": true }
}
JSON

cd "$TMP/repo"

echo "== 1. render =="
out=$(./scripts/render.sh 2>&1)
grep -q "12 个节点" <<<"$out" || fail "节点数不对"
ok "12 个节点"

echo "== 2. doctor =="
./scripts/doctor.sh >/dev/null 2>&1 || fail "doctor 非 0 退出"
ok "配置校验通过"

echo "== 3. 退化判定 =="
out=$(./scripts/doctor.sh --only-agent stub 2>&1)
grep -q "C 单档" <<<"$out" || fail "单 Agent 未判为 C 档"
grep -q "跳过交叉互审" <<<"$out" || fail "C 档未提示跳过交叉互审"
ok "C 档退化正确"

echo "== 4. 跨厂商模型不沿用 =="
cp "$SRC/pipeline.local.example.json" pipeline.local.json
python3 - <<'PY'
import json
d = json.load(open("pipeline.local.json"))
d["roles"] = {k: {"agent": "claude", "model": "xxx"} for k in d["roles"]}
json.dump(d, open("pipeline.local.json", "w"), ensure_ascii=False, indent=2)
PY
out=$(./scripts/render.sh --only-agent stub 2>&1)
grep -q "xxx" <<<"$out" && fail "模拟模式下不该沿用别的厂商的模型名"
ok "模型名已丢弃"

echo "== 5. 全流程 dry-run =="
out=$(./scripts/run-plain.sh --dry-run --yes --only-agent stub 2>&1)
grep -q "▶ 00a-clarify" <<<"$out" || fail "未从 00a 开始"
grep -q "▶ 10-e2e-run" <<<"$out" || fail "未走到 10"
ok "12 个节点按依赖顺序走完"

echo "== 6. 真跑（stub 接管全部角色）=="
rm -rf runs handoff contract e2e   # dry-run 也会留 run 目录，清掉免得比错
cat > pipeline.local.json <<'JSON'
{
  "defaults": { "agent": "stub", "effort": "medium" },
  "roles": {},
  "options": { "stopAtGates": true }
}
JSON
./scripts/run-plain.sh --yes >/dev/null 2>&1 || fail "run 失败"

for f in handoff/00a-assumptions.md handoff/01-fe-design.md handoff/04-fe-dev.md \
         handoff/09-correctness.md handoff/10-e2e-report.md; do
  [[ -s "$f" ]] || fail "缺少产物: $f"
done
ok "6 份关键产物已落盘"

[[ -d runs ]] || fail "没有 runs 目录"
state=$(ls -t runs/*/state.json | head -1)
python3 - "$state" <<'PY' || exit 1
import json, sys
d = json.load(open(sys.argv[1]))
nodes = d["nodes"]
assert len(nodes) == 12, f"状态里应记录 12 个节点，实际 {len(nodes)}"
gates = [k for k, v in nodes.items() if v["status"] == "gate-passed"]
assert set(gates) == {"00b-scope", "03-contract"}, f"闸门记录不对: {gates}"
ok = [k for k, v in nodes.items() if v["status"] == "ok"]
assert len(ok) == 10, f"应有 10 个 agent 节点成功，实际 {len(ok)}"
print(f"state ok: {len(ok)} agent 节点, {len(gates)} 个人工闸门")
PY
ok "state.json 记录正确"

echo
echo "全部通过。"
