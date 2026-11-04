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
mkdir -p "$TMP/bin" "$TMP/repo" "$TMP/proj"
cp -R "$SRC"/. "$TMP/repo/"
rm -rf "$TMP/repo/runs" "$TMP/repo/handoff" "$TMP/repo/contract" "$TMP/repo/e2e" "$TMP/repo/specs"

# 假 Agent：第二轮（prompt 里带上一轮输出）收敛成「无待确认」
cat > "$TMP/bin/relay-stub" <<'STUB'
#!/usr/bin/env bash
prompt="$1"
echo "# STUB 产出"
echo
echo "收到的说明长度: ${#prompt}"
echo
echo "## 待确认"
if [[ "$prompt" == *"### 上一轮你的输出"* ]]; then
  echo "无"
else
  echo "- Q1: 要不要支持导出 PDF？（高影响，建议：不支持）"
fi
STUB
chmod +x "$TMP/bin/relay-stub"
export PATH="$TMP/bin:$PATH"

# $1 是塞进 options 的额外键值对（不带引号转义），留空则用默认
write_local() {
  if [[ -n "${1:-}" ]]; then
    printf '{\n  "defaults": { "agent": "stub", "effort": "medium" },\n  "roles": {},\n  "options": { "stopAtGates": true, %s }\n}\n' "$1" \
      > "$TMP/repo/pipeline.local.json"
  else
    printf '{\n  "defaults": { "agent": "stub", "effort": "medium" },\n  "roles": {},\n  "options": { "stopAtGates": true }\n}\n' \
      > "$TMP/repo/pipeline.local.json"
  fi
}
write_local
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
write_local
out=$(./scripts/run-plain.sh --dry-run --yes --only-agent stub 2>&1)
grep -q "▶ 00a-clarify" <<<"$out" || fail "未从 00a 开始"
grep -q "▶ 10-e2e-run" <<<"$out" || fail "未走到 10"
ok "12 个节点按依赖顺序走完"

echo "== 6. 真跑（stub 接管全部角色）=="
rm -rf runs handoff contract e2e
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

echo "== 7. 多轮收敛（--rounds）=="
rm -rf runs handoff
out=$(./scripts/run-plain.sh --only-node 00a-clarify --rounds 3 --yes 2>&1)
grep -q "第 1 轮" <<<"$out" || fail "没有进入多轮模式"
grep -q "收敛于第 2 轮" <<<"$out" || fail "第二轮未收敛"
grep -q "Q1" <<<"$out" || fail "未把待确认项报出来"
state=$(ls -t runs/*/state.json | head -1)
python3 - "$state" <<'PY' || exit 1
import json, sys
d = json.load(open(sys.argv[1]))
n = d["nodes"]["00a-clarify"]
assert n["rounds"] == 2, f"应停在第 2 轮，实际 {n.get('rounds')}"
assert n["status"] == "ok", n
print("rounds ok: 2")
PY
ok "两轮后收敛"

echo "== 8. projectRoot：产物跟着项目走 =="
rm -rf runs handoff
write_local "\"projectRoot\": \"$TMP/proj\""
./scripts/run-plain.sh --only-node 01-fe-design --yes >/dev/null 2>&1 || fail "projectRoot 模式跑失败"
[[ -s "$TMP/proj/handoff/01-fe-design.md" ]] || fail "产物没有落到 projectRoot"
if [[ -e "handoff/01-fe-design.md" ]]; then fail "产物不该落在 relay 仓库里"; fi
ok "产物落在 $TMP/proj"

out=$(./scripts/render.sh 2>&1)
grep -q "产物根: $TMP/proj" <<<"$out" || fail "render 未显示产物根"
ok "render 显示了产物根"

echo "== 9. 分诊档位透传 =="
write_local "\"clarifyMode\": \"light\""
./scripts/run-plain.sh --only-node 00a-clarify --yes >/dev/null 2>&1 || fail "light 档跑失败"
log=$(ls -t runs/*/00a-clarify.r1.log | head -1)
grep -q "CLARIFY_MODE: light" "$log" || fail "CLARIFY_MODE 没有透传进 prompt"
ok "clarifyMode 已注入 prompt"


echo "== 10. 多项目：同一个工具，两个项目各自的配置 =="
rm -rf runs handoff
mkdir -p "$TMP/p1" "$TMP/p2"
for proj in "$TMP/p1" "$TMP/p2"; do
  printf '{\n  "defaults": { "agent": "stub", "effort": "medium" },\n  "roles": {}\n}\n' \
    > "$proj/.agent-relay.json"
done
./scripts/run-plain.sh --project "$TMP/p1" --only-node 01-fe-design --yes >/dev/null 2>&1 || fail "p1 跑失败"
./scripts/run-plain.sh --project "$TMP/p2" --only-node 02-be-design --yes >/dev/null 2>&1 || fail "p2 跑失败"
[[ -s "$TMP/p1/handoff/01-fe-design.md" ]] || fail "p1 没产物"
[[ -s "$TMP/p2/handoff/02-be-design.md" ]] || fail "p2 没产物"
[[ -e "$TMP/p2/handoff/01-fe-design.md" ]] && fail "p1 的产物串到 p2 了"
[[ -e "handoff/01-fe-design.md" ]] && fail "产物不该落在 relay 仓库里"
ok "两个项目各跑各的，产物不串"

out=$(./scripts/render.sh --project "$TMP/p1" 2>&1)
grep -q "$TMP/p1/.agent-relay.json" <<<"$out" || fail "--project 没有用上 .agent-relay.json"
ok "--project 读到了项目内配置"

echo "== 11. 显式 --config =="
rm -rf runs handoff
printf '{\n  "defaults": { "agent": "stub" },\n  "roles": {},\n  "options": { "projectRoot": "%s" }\n}\n' "$TMP/proj" \
  > "$TMP/ci-config.json"
./scripts/run-plain.sh --config "$TMP/ci-config.json" --only-node 01-fe-design --yes >/dev/null 2>&1 || fail "--config 跑失败"
[[ -s "$TMP/proj/handoff/01-fe-design.md" ]] || fail "--config 的 projectRoot 没生效"
ok "--config 生效"


echo "== 12. 只做后端（scope=backend）=="
rm -rf runs handoff
write_local '"scope": "backend"'
out=$(./scripts/render.sh 2>&1)
grep -q "9 个节点" <<<"$out" || fail "后端单栈应是 9 个节点"
grep -q "design_fe" <<<"$out" && fail "前端设计没被裁掉"
grep -q "已裁剪" <<<"$out" || fail "没提示裁剪了什么"
ok "裁剪 3 个前端节点，剩 9 个"

./scripts/run-plain.sh --yes >/dev/null 2>&1 || fail "后端单栈跑失败"
[[ -s handoff/05-be-dev.md ]] || fail "缺后端开发产物"
[[ -e handoff/04-fe-dev.md ]] && fail "前端开发不该有产物"
[[ -e handoff/06-merge.md ]] && fail "单栈不该有合并产物"
state=$(ls -t runs/*/state.json | head -1)
python3 - "$state" <<'CHECK' || exit 1
import json, sys
d = json.load(open(sys.argv[1]))
assert len(d["nodes"]) == 9, len(d["nodes"])
assert set(d["skipped"]) == {"01-fe-design", "04-fe-dev", "06-merge"}, d["skipped"]
gates = [k for k, v in d["nodes"].items() if v["status"] == "gate-passed"]
assert set(gates) == {"00b-scope", "03-contract"}, gates
print("backend scope ok: 9 节点, 2 闸门")
CHECK
ok "后端单栈跑通，依赖已重连"

echo
echo "全部通过。"
