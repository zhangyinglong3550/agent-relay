#!/usr/bin/env bash
# 把本仓库安装成一个 Agent Skill（符号链接，不复制，改仓库即生效）。
#
#   ./scripts/install-skill.sh                 # 装到 ~/.agents/skills/agent-relay
#   ./scripts/install-skill.sh ~/my/skills     # 装到指定目录
#
# 已存在时不会覆盖别人的安装：检测到同名目录会提示并退出。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_DIR="${1:-$HOME/.agents/skills}"
LINK="$TARGET_DIR/agent-relay"

if [[ ! -f "$ROOT/skill/SKILL.md" ]]; then
  echo "找不到 $ROOT/skill/SKILL.md" >&2
  exit 1
fi

mkdir -p "$TARGET_DIR"

if [[ -e "$LINK" && ! -L "$LINK" ]]; then
  echo "$LINK 已存在且不是符号链接，不覆盖。" >&2
  echo "确认要替换的话，先手动删掉它。" >&2
  exit 1
fi

ln -sfn "$ROOT/skill" "$LINK"
echo "已安装: $LINK -> $ROOT/skill"

# 顺手装到其它 Agent 的技能目录（存在才装）
for extra in "$HOME/.claude/skills" "$HOME/.codex/skills"; do
  if [[ -d "$extra" ]]; then
    ln -sfn "$ROOT/skill" "$extra/agent-relay"
    echo "同时安装: $extra/agent-relay"
  fi
done

echo
echo "验证："
echo "  ls -l $LINK"
echo "  \$RELAY/scripts/doctor.sh --project <项目>"
echo
echo "之后任何 Agent 说「用 relay 做这个需求」都会读到这份说明。"
