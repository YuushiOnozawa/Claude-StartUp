#!/usr/bin/env bash
# codex-companion task をプロセス単位で直列化する前景専用 wrapper。
set -euo pipefail

usage() {
  echo "usage: codex-broker-run.sh --check | task --prompt-file <path> [codex-companion arguments...]" >&2
  exit 2
}

[[ "$#" -gt 0 ]] || usage

for arg in "$@"; do
  if [[ "$arg" == -* && "$arg" == *background* ]]; then
    echo "broker 経由の codex task は前景のみです（background variant は使用できません）。background が必要な plangen GENERATE は wrapper を使わず codex-companion を直接呼びます" >&2
    exit 2
  fi
done

if [[ "$1" == "task" ]]; then
  PROMPT_FILE_SEEN=false
  for arg in "${@:2}"; do
    if [[ "$arg" == "--prompt-file" || "$arg" == --prompt-file=* ]]; then
      PROMPT_FILE_SEEN=true
    fi
  done
  if [[ "$PROMPT_FILE_SEEN" != true ]]; then
    echo "broker 経由の codex task は raw positional prompt を受け付けません。--prompt-file を使ってください" >&2
    exit 2
  fi
fi

CODEX_COMPANION=""
if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" \
  && -f "${CLAUDE_PLUGIN_ROOT}/scripts/codex-companion.mjs" ]]; then
  CODEX_COMPANION="${CLAUDE_PLUGIN_ROOT}/scripts/codex-companion.mjs"
fi
if [[ -z "$CODEX_COMPANION" ]]; then
  CODEX_COMPANION="$(ls -d "${HOME}/.claude/plugins/cache/openai-codex/codex/"*/scripts/codex-companion.mjs 2>/dev/null \
    | sort -V | tail -1 || true)"
fi
if [[ -z "$CODEX_COMPANION" || ! -f "$CODEX_COMPANION" ]]; then
  echo "Codex companion が見つかりません" >&2
  exit 1
fi

if [[ "$1" == "--check" ]]; then
  [[ "$#" -eq 1 ]] || usage
  exec node "$CODEX_COMPANION" status
fi
[[ "$1" == "task" ]] || usage

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUDGET_HELPER="$SCRIPT_DIR/../skills/flow-common/execution-budget.sh"
[[ -r "$BUDGET_HELPER" ]] || BUDGET_HELPER="$HOME/.claude/skills/flow-common/execution-budget.sh"
RESOURCE_WAIT="$(bash "$BUDGET_HELPER" get resource_wait codex 2>/dev/null || true)"
[[ "$RESOURCE_WAIT" =~ ^[1-9][0-9]*$ ]] || RESOURCE_WAIT=900

# pathname は unlink/rename せず、全参加者が同じ inode を flock する。
LOCK="${XDG_RUNTIME_DIR:-/tmp}/claude-codex-broker.lock"
mkdir -p "$(dirname "$LOCK")"
exec 9>"$LOCK"
LOCK_WAIT_STARTED_AT="$(date +%s)"
if ! flock -w "$RESOURCE_WAIT" -E 9 9; then
  echo "Codex broker 排他ロックを${RESOURCE_WAIT}秒以内に取得できませんでした" >&2
  exit 9
fi
LOCKED_AT="$(date +%s)"
echo "Codex broker lock wait: $((LOCKED_AT - LOCK_WAIT_STARTED_AT))s" >&2

# fd 9 を前景 worker へ継承し、wrapper が SIGKILL されても worker 終了まで lock を保つ。
set +e
node "$CODEX_COMPANION" "$@"
STATUS=$?
set -e
exit "$STATUS"
