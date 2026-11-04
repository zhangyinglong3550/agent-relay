#!/usr/bin/env bash
# 打印解析后的执行计划，不执行任何 Agent。
set -euo pipefail
cd "$(dirname "$0")/.."
exec python3 scripts/relay.py render "$@"
