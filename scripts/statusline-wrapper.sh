#!/bin/bash
# statusline wrapper: 表示は ccstatusline にパススルー。warn marker 判定は warn-marker-check.sh に委譲。
# いかなる失敗も表示を壊してはならない（fail-open）。
set -uo pipefail
INPUT=$(cat)

# warn marker 判定（責務分離: warn-marker-check.sh に委譲）
printf '%s' "$INPUT" | bash "$(dirname -- "${BASH_SOURCE[0]}")/warn-marker-check.sh" 2>/dev/null || true

# 表示: ccstatusline へパススルー
# PATH → mise → 既知フォールバックパスの順で探索
CCSTATUSLINE=$(command -v ccstatusline 2>/dev/null \
  || { command -v mise &>/dev/null && mise which ccstatusline 2>/dev/null; } \
  || echo "/home/ylocal/.local/share/mise/installs/node/24/bin/ccstatusline")
printf '%s' "$INPUT" | "$CCSTATUSLINE"
