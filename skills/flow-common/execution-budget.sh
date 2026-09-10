#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUDGET_JSON="${EXECUTION_BUDGET_JSON:-$SCRIPT_DIR/execution-budget.json}"

usage() {
  echo "usage: execution-budget.sh get <phase> <backend> | diff-cap <field> | review-post <field> | generation-factor <field> <backend> | max-allowance <backend> | assert-no-takeover | list" >&2
  exit 2
}

[[ -r "$BUDGET_JSON" ]] || { echo "execution budget JSON を読み取れません: $BUDGET_JSON" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq が必要です" >&2; exit 2; }

backend_filter='if $backend == "magi" or $backend == "codex" then . else error("invalid backend") end'

get_value() {
  local phase="$1"
  local backend="$2"
  local value
  if ! jq -e --arg phase "$phase" --arg backend "$backend" "
    $backend_filter
    | if (.phases | has(\$phase) | not) then error(\"unknown phase\") else . end
  " "$BUDGET_JSON" >/dev/null; then
    return 2
  fi
  value="$(jq -r --arg phase "$phase" --arg backend "$backend" '.phases[$phase][$backend] // "__NULL__"' "$BUDGET_JSON")"
  if [[ "$value" == "__NULL__" ]]; then
    return 3
  fi
  printf '%s\n' "$value"
}

derived_value() {
  local name="$1"
  local backend="$2"
  jq -er --arg name "$name" --arg backend "$backend" "
    $backend_filter
    | . as \$root
    | \$root.derived[\$name][\$backend] as \$expr
    | if \$expr.operation == \"multiply\" and (\$expr | has(\"phase\")) then
        (\$root.phases[\$expr.phase][\$backend] * (\$expr.factors | to_entries | map(.value) | reduce .[] as \$v (1; . * \$v)))
      elif \$expr.operation == \"multiply\" then
        (\$expr.factors | to_entries | map(.value) | reduce .[] as \$v (1; . * \$v))
      else error(\"unsupported derived expression\") end
  " "$BUDGET_JSON"
}

max_allowance() {
  local backend="$1"
  local generation
  generation="$(derived_value generation_total "$backend")"
  jq -er --arg backend "$backend" --argjson generation "$generation" "
    $backend_filter
    | . as \$root
    | \$root.derived.max_configured_allowance[\$backend] as \$expr
    | if \$expr.operation != \"sum\" then error(\"unsupported allowance expression\") else
        reduce \$expr.phases[] as \$phase (0;
          . + (if \$phase == \"generation_total\" then \$generation else (\$root.phases[\$phase][\$backend] // 0) end))
      end
  " "$BUDGET_JSON"
}

case "${1:-}" in
  get)
    [[ "$#" -eq 3 ]] || usage
    get_value "$2" "$3"
    ;;
  diff-cap)
    [[ "$#" -eq 2 ]] || usage
    case "$2" in
      changed_lines|chunks) jq -er --arg field "$2" '.phases.diff_cap.limits[$field]' "$BUDGET_JSON" ;;
      soft_warning) jq -er '.phases.diff_cap.limits.soft_warning_lines.minimum' "$BUDGET_JSON" ;;
      recommended_split_by) jq -er '.phases.diff_cap.limits.soft_warning_lines.recommended_split_by' "$BUDGET_JSON" ;;
      *) usage ;;
    esac
    ;;
  review-post)
    [[ "$#" -eq 2 ]] || usage
    case "$2" in
      api_timeout|page_limit|inline_soft)
        jq_field="api_timeout_seconds"
        [[ "$2" == "page_limit" ]] && jq_field="page_limit"
        [[ "$2" == "inline_soft" ]] && jq_field="inline_posts_soft_seconds"
        jq -er --arg field "$jq_field" '.phases.review_post.breakdown[$field]' "$BUDGET_JSON"
        ;;
      *) usage ;;
    esac
    ;;
  generation-factor)
    [[ "$#" -eq 3 ]] || usage
    [[ "$3" == "magi" || "$3" == "codex" ]] || usage
    jq -er --arg field "$2" --arg backend "$3" \
      '.derived.generation_total[$backend].factors[$field]' "$BUDGET_JSON"
    ;;
  max-allowance)
    [[ "$#" -eq 2 ]] || usage
    max_allowance "$2"
    ;;
  assert-no-takeover)
    [[ "$#" -eq 1 ]] || usage
    jq -e '([.phases[] | select(.class == "soft" or .class == "mixed" or .class == "unbounded")] | length) == 0 or .policy.auto_takeover == false' "$BUDGET_JSON" >/dev/null
    ;;
  list)
    [[ "$#" -eq 1 ]] || usage
    jq -r '.phases | to_entries[] | [.key, .value.class, (.value.magi // ""), (.value.codex // "")] | @tsv' "$BUDGET_JSON"
    ;;
  *) usage ;;
esac
