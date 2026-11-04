#!/usr/bin/env bash
# 检查本机环境、配置完整度、退化档位、模型/思考等级注入通道。
set -euo pipefail
cd "$(dirname "$0")/.."
exec python3 scripts/relay.py doctor "$@"
