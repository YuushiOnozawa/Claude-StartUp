#!/usr/bin/env bash
# scripts/review-adjudicate-findings.sh — 妥当性・重要度から最終 gate を導出する
set -euo pipefail

usage() {
  echo "usage: $0 ENGINE FINDINGS_META_FILE VALIDITY_FILE IMPORTANCE_FILE" >&2
  exit 2
}

[[ $# -eq 4 ]] || usage

ENGINE="$1"
FINDINGS_META_FILE="$2"
VALIDITY_FILE="$3"
IMPORTANCE_FILE="$4"

[[ "$ENGINE" == "magi" || "$ENGINE" == "codex" ]] || usage

[[ -r "$FINDINGS_META_FILE" ]] || {
  echo "findings meta ファイルを読み取れません: $FINDINGS_META_FILE" >&2
  exit 2
}

strict_json() {
  local input_file="$1"
  jq -s -c 'if length == 1 then .[0] else error("expected exactly one JSON value") end' "$input_file"
}

if ! findings_meta_json="$(strict_json "$FINDINGS_META_FILE" 2>/dev/null)"; then
  echo "findings meta の JSON が不正です" >&2
  exit 2
fi

if ! jq -e '
  def nonempty_string: type == "string" and length > 0;
  def valid_reported_gate:
    type == "null" or (type == "string" and IN("block", "defer", "manual"));
  def valid_meta:
    type == "object"
    and has("id") and (.id | nonempty_string)
    and has("source_persona") and (.source_persona | nonempty_string)
    and has("reported_gate") and (.reported_gate | valid_reported_gate);
  type == "array"
  and ([.[].id] | length) == ([.[].id] | unique | length)
  and all(.[]; valid_meta)
' <<<"$findings_meta_json" >/dev/null 2>&1; then
  echo "findings meta の構造が不正です" >&2
  exit 2
fi

if jq -e 'length == 0' <<<"$findings_meta_json" >/dev/null 2>&1; then
  printf '%s\n' '{"schema_version":"1","artifact_type":"review-adjudication","results":[],"validity_global_failure":false}'
  exit 0
fi

validity_global_failure=0
validity_json='[]'
if [[ ! -r "$VALIDITY_FILE" ]]; then
  echo "妥当性判定ファイルを読み取れません。全件をfail-closedで扱います: $VALIDITY_FILE" >&2
  validity_global_failure=1
elif ! validity_json="$(strict_json "$VALIDITY_FILE" 2>/dev/null)"; then
  echo "妥当性判定のJSON解析に失敗しました。全件をfail-closedで扱います" >&2
  validity_global_failure=1
elif ! jq -n -e \
  --argjson meta "$findings_meta_json" \
  --argjson validity "$validity_json" '
    def nonempty_string: type == "string" and length > 0;
    def valid_result:
      type == "object"
      and has("id") and (.id | nonempty_string)
      and has("verdict")
      and (.verdict | type == "string" and IN("valid", "false_positive", "needs_human"));
    ($meta | map(.id) | sort) as $expected
    | if ($validity | type) != "array" then false
      else
        ($validity | map(.id) | sort) as $actual
        | ($validity | map(.id) | unique | sort) as $unique
        | all($validity[]; valid_result)
          and ($actual == $unique)
          and ($actual == $expected)
      end
  ' >/dev/null 2>&1; then
  echo "妥当性判定の形状またはfinding ID集合が不正です。全件をfail-closedで扱います" >&2
  validity_global_failure=1
  validity_json='[]'
fi

importance_json='[]'
if ! importance_candidate="$(strict_json "$IMPORTANCE_FILE" 2>/dev/null)"; then
  echo "重要度判定のJSON解析に失敗しました。該当findingをdeferにします" >&2
elif jq -e '
  type == "object"
  and has("error")
  and (.error | type == "string" and IN("IMPORTANCE_ERROR", "IMPORTANCE_SKIPPED"))
' <<<"$importance_candidate" >/dev/null 2>&1; then
  echo "重要度判定が失敗しました。該当findingをdeferにします" >&2
elif jq -n -e \
  --argjson meta "$findings_meta_json" \
  --argjson importance "$importance_candidate" '
    def nonempty_string: type == "string" and length > 0;
    def valid_importance:
      type == "object"
      and has("id") and (.id | nonempty_string)
      and has("importance")
      and (.importance | type == "string" and IN("HIGH", "MEDIUM", "LOW"));
    ($meta | map(.id)) as $allowed
    | if ($importance | type) != "array" then false
      elif ($importance | length) == 0 then false
      else
        ($importance | map(.id)) as $importance_ids
        | all($importance[]; valid_importance)
          and (($importance_ids | length) == ($importance_ids | unique | length))
          and all($importance_ids[]; . as $id | ($allowed | index($id)) != null)
      end
  ' >/dev/null 2>&1; then
  importance_json="$importance_candidate"
elif jq -e 'type == "array" and length == 0' <<<"$importance_candidate" >/dev/null 2>&1; then
  importance_json='[]'
else
  echo "重要度判定の形状またはfinding ID集合が不正です。該当findingをdeferにします" >&2
fi

result_json="$(jq -n -c \
  --arg engine "$ENGINE" \
  --argjson meta "$findings_meta_json" \
  --argjson validity "$validity_json" \
  --argjson importance "$importance_json" \
  --argjson validity_global_failed "$validity_global_failure" '
  def verdict_for($id):
    (first($validity[] | select(.id == $id) | .verdict) // null);
  def importance_for($id):
    (first($importance[] | select(.id == $id) | .importance) // null);
  {
    schema_version: "1",
    artifact_type: "review-adjudication",
    results: [
      $meta[]
      | . as $finding
      | if $validity_global_failed == 1 then
          {
            id: $finding.id,
            verdict: null,
            importance: null,
            importance_status: "not_applicable",
            reported_gate: $finding.reported_gate,
            final_gate: null
          }
        else
          (verdict_for($finding.id)) as $verdict
          | if ($engine == "codex" and $finding.source_persona == "CASPER") then
              {
                id: $finding.id,
                verdict: $verdict,
                importance: null,
                importance_status: "not_applicable",
                reported_gate: $finding.reported_gate,
                final_gate: (if $verdict == "false_positive" then "defer" else "block" end)
              }
            elif $verdict == "false_positive" then
              {
                id: $finding.id,
                verdict: $verdict,
                importance: null,
                importance_status: "not_applicable",
                reported_gate: $finding.reported_gate,
                final_gate: "defer"
              }
            else
              (importance_for($finding.id)) as $importance_value
              | {
                  id: $finding.id,
                  verdict: $verdict,
                  importance: $importance_value,
                  importance_status: (if $importance_value == null then "failed" else "ok" end),
                  reported_gate: $finding.reported_gate,
                  final_gate: (if $importance_value == "HIGH" or $importance_value == "MEDIUM" then "block" else "defer" end)
                }
            end
        end
    ],
    validity_global_failure: ($validity_global_failed == 1)
  }
' )" || {
  echo "review adjudication 結果の生成に失敗しました" >&2
  exit 2
}

printf '%s\n' "$result_json"
if [[ "$validity_global_failure" -eq 1 ]]; then
  exit 1
fi
exit 0
