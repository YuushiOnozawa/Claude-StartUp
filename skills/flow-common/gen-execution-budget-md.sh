#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUDGET_JSON="$SCRIPT_DIR/execution-budget.json"
HELPER="$SCRIPT_DIR/execution-budget.sh"
OUTPUT="$SCRIPT_DIR/references/execution-budget.md"

usage() {
  echo "usage: gen-execution-budget-md.sh [--input <json>] [--output <md>]" >&2
  exit 2
}

while (($# > 0)); do
  case "$1" in
    --input) [[ "$#" -ge 2 ]] || usage; BUDGET_JSON="$2"; shift 2 ;;
    --output) [[ "$#" -ge 2 ]] || usage; OUTPUT="$2"; shift 2 ;;
    *) usage ;;
  esac
done

[[ -r "$BUDGET_JSON" ]] || { echo "input JSON を読み取れません: $BUDGET_JSON" >&2; exit 2; }
TMP_FILE="$(mktemp)"
trap 'rm -f -- "$TMP_FILE"' EXIT

format_value() {
  local phase="$1"
  local backend="$2"
  local value
  if value="$(EXECUTION_BUDGET_JSON="$BUDGET_JSON" "$HELPER" get "$phase" "$backend")"; then
    printf '%ss' "$value"
  elif [[ "$phase" == "generation_total" ]]; then
    jq -r --arg backend "$backend" '
      . as $root | .derived.generation_total[$backend] as $expr
      | if ($expr | has("phase")) then
          ($root.phases[$expr.phase][$backend] * ($expr.factors | to_entries | map(.value) | reduce .[] as $v (1; . * $v)))
        else ($expr.factors | to_entries | map(.value) | reduce .[] as $v (1; . * $v)) end
      | tostring + "s"
    ' "$BUDGET_JSON"
  else
    printf '%s' '—'
  fi
}

{
  echo '<!-- GENERATED FROM execution-budget.json — DO NOT EDIT -->'
  echo
  echo '# Flow/Review 実行時間バジェット'
  echo
  echo '| フェーズ | 分類 | magi | codex | 強制箇所 |'
  echo '|---|---|---:|---:|---|'
  while IFS=$'\t' read -r phase class _magi _codex; do
    forcing="$(jq -r --arg phase "$phase" '.phases[$phase].forcing_location' "$BUDGET_JSON")"
    printf '| `%s` | %s | %s | %s | %s |\n' "$phase" "$class" "$(format_value "$phase" magi)" "$(format_value "$phase" codex)" "$forcing"
  done < <(EXECUTION_BUDGET_JSON="$BUDGET_JSON" "$HELPER" list)
  echo
  echo '## 導出値'
  echo
  for backend in magi codex; do
    generation="$(jq -r --arg backend "$backend" '
      . as $root | .derived.generation_total[$backend] as $expr
      | if ($expr | has("phase")) then
          ($root.phases[$expr.phase][$backend] * ($expr.factors | to_entries | map(.value) | reduce .[] as $v (1; . * $v)))
        else ($expr.factors | to_entries | map(.value) | reduce .[] as $v (1; . * $v)) end
    ' "$BUDGET_JSON")"
    phases="$(jq -r --arg backend "$backend" '.derived.max_configured_allowance[$backend].phases | join(" + ")' "$BUDGET_JSON")"
    maximum="$(EXECUTION_BUDGET_JSON="$BUDGET_JSON" "$HELPER" max-allowance "$backend")"
    printf -- '- %s `generation_total`: %ss\n' "$backend" "$generation"
    printf -- '- %s `max_configured_allowance`: `%s` = %ss\n' "$backend" "$phases" "$maximum"
  done
  echo
  echo '## Policy'
  echo
  jq -r '"- `auto_takeover`: `" + (.policy.auto_takeover | tostring) + "`\n- `auto_takeover_allowed_when`: `" + .policy.auto_takeover_allowed_when + "`\n- " + .policy.notes' "$BUDGET_JSON"
} > "$TMP_FILE"

mv -- "$TMP_FILE" "$OUTPUT"
trap - EXIT
