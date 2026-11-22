#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "未找到 xcodegen。请先运行: brew install xcodegen"
  exit 1
fi

xcodegen generate
echo "已生成 ios/CyIME.xcodeproj"
