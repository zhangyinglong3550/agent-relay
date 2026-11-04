#!/usr/bin/env bash
# 顺序执行器：不需要 Orca，只要有 git 和任意一个 Agent CLI。
#
#   ./scripts/run-plain.sh --dry-run          只看会跑什么
#   ./scripts/run-plain.sh                    跑，到人工闸门停下
#   ./scripts/run-plain.sh --start-from 04-fe-dev
#   ./scripts/run-plain.sh --only-agent claude    强制单 Agent（验证退化）
set -euo pipefail
cd "$(dirname "$0")/.."
exec python3 scripts/relay.py run "$@"
