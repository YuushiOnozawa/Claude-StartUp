#!/usr/bin/env bash
# scripts/review-dispatch-envelope.sh — review dispatch envelope の契約検証
set -euo pipefail

usage() {
  echo "usage: bash scripts/review-dispatch-envelope.sh validate <envelope.json>" >&2
  exit 2
}

die() {
  echo "review-dispatch envelope 契約違反: $1" >&2
  exit 2
}

[[ $# -eq 2 && "$1" == "validate" ]] || usage
ENVELOPE_FILE="$2"
[[ -r "$ENVELOPE_FILE" ]] || die "envelope を読み取れません: $ENVELOPE_FILE"
command -v jq >/dev/null 2>&1 || die "jq が必要です"

read_json() {
  local input_file="$1"
  local value
  if ! value="$(jq -s -c 'if length == 1 then .[0] else error("expected exactly one JSON value") end' "$input_file" 2>/dev/null)"; then
    die "envelope は単一の JSON 値でなければなりません"
  fi
  printf '%s' "$value"
}

ENVELOPE_JSON="$(read_json "$ENVELOPE_FILE")"

if ! jq -e '
  def required_keys:
    ["schema_version", "artifact_type", "review_kind", "backend",
     "dispatch_status", "gate_decision", "lgtm_eligible", "blocking_count",
     "manual_review_required", "manual_review", "artifact_ref",
     "adjudication_ref", "post_state", "failure_reason", "native_result"];
  def nullable_nonempty_string:
    if . == null then true
    elif type == "string" then length > 0
    else false
    end;
  def nullable_container:
    . == null or (type == "object" or type == "array");
  def nonnegative_integer_or_null:
    if . == null then true
    elif type == "number" then floor == . and . >= 0
    else false
    end;

  . as $envelope
  | (
      type == "object"
      and (required_keys | all(.[]; . as $key | ($envelope | has($key))))
      and (.schema_version | type == "string" and . == "1")
      and (.artifact_type | type == "string" and . == "review-dispatch-result")
      and (.review_kind | type == "string" and IN("fast", "hard"))
      and (.backend | type == "string" and IN("magi", "codex"))
      and (.dispatch_status | type == "string" and IN("complete", "incomplete", "failed", "unavailable"))
      and (.gate_decision | type == "string" and IN("lgtm", "block", "manual", "indeterminate"))
      and (.lgtm_eligible | type == "boolean")
      and (.blocking_count | nonnegative_integer_or_null)
      and (.manual_review_required | type == "boolean")
      and (.manual_review | nullable_container)
      and (.artifact_ref | nullable_nonempty_string)
      and (.adjudication_ref | nullable_nonempty_string)
      and (.post_state | type == "string" and IN("posted", "post_failed", "not_applicable"))
      and (.failure_reason | type == "null" or type == "string")
      and (.native_result | type == "object")
      and (
        (.lgtm_eligible != true)
        or (
          .dispatch_status == "complete"
          and .gate_decision == "lgtm"
          and .blocking_count == 0
          and .manual_review_required == false
        )
      )
      and (
        (.lgtm_eligible != true or .review_kind != "hard")
        or .post_state == "posted"
      )
      and (
        (.dispatch_status == "complete")
        or (
          .lgtm_eligible == false
          and (.failure_reason | type == "string" and length > 0)
        )
      )
      and (
        (.review_kind != "fast")
        or (
          .artifact_ref == null
          and .adjudication_ref == null
          and .post_state == "not_applicable"
        )
      )
      and (
        (.review_kind != "hard")
        or (.dispatch_status == "unavailable")
        or (.post_state | IN("posted", "post_failed"))
      )
      and (
        (.review_kind != "hard")
        or (.dispatch_status != "unavailable")
        or (.post_state == "not_applicable")
      )
      and (
        (.review_kind != "hard")
        or (.gate_decision != "manual")
      )
      and (
        (.review_kind != "hard")
        or ((.gate_decision | IN("lgtm", "block")) | not)
        or (.artifact_ref != null and .adjudication_ref != null)
      )
      and (
        (.gate_decision != "indeterminate")
        or (
          .dispatch_status != "complete"
          and .lgtm_eligible == false
        )
      )
      and (
        (.dispatch_status != "failed")
        or .gate_decision == "indeterminate"
      )
      and (
        (.post_state != "post_failed")
        or (.failure_reason | type == "string" and length > 0)
      )
      and (
        (.gate_decision != "block")
        or (.blocking_count | type == "number" and floor == . and . >= 1)
      )
      and (
        (.gate_decision != "lgtm")
        or .blocking_count == 0
      )
      and (
        (.manual_review == null)
        or .manual_review_required == true
      )
      and (
        (.dispatch_status != "failed")
        or (.manual_review_required == true)
      )
      and (
        (.dispatch_status != "unavailable")
        or (.manual_review_required == true)
      )
    )
' <<<"$ENVELOPE_JSON" >/dev/null 2>&1; then
  die "必須キー、型、enum、または状態の組合せが不正です"
fi

exit 0
