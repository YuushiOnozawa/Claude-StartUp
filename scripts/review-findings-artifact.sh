#!/usr/bin/env bash
# MAGI/Codex findings table を canonical findings artifact へ変換する。
set -euo pipefail

usage() {
  echo "usage: bash scripts/review-findings-artifact.sh <magi|codex> <findings-table.json> [<failed-personas.json>]" >&2
  exit 2
}

die() {
  echo "$1" >&2
  exit 2
}

[[ $# -eq 2 || $# -eq 3 ]] || usage

ENGINE="$1"
FINDINGS_FILE="$2"
FAILED_PERSONAS_FILE="${3:-}"

case "$ENGINE" in
  magi|codex) ;;
  *) die "未知の engine です: $ENGINE" ;;
esac

[[ -r "$FINDINGS_FILE" ]] || die "入力ファイルを読み取れません: $FINDINGS_FILE"
if [[ $# -eq 3 ]]; then
  [[ -r "$FAILED_PERSONAS_FILE" ]] || die "failed-personas を読み取れません: $FAILED_PERSONAS_FILE"
fi

TMPDIR_ARTIFACT=$(mktemp -d)
trap 'rm -rf -- "$TMPDIR_ARTIFACT"' EXIT

read_json() {
  local input_file="$1"
  local label="$2"
  local value
  if ! value=$(jq -s -c 'if length == 1 then .[0] else error("expected exactly one JSON value") end' "$input_file" 2>/dev/null); then
    die "$label の JSON が不正です"
  fi
  printf '%s' "$value"
}

PERSONAS='["MELCHIOR", "BALTHASAR", "METATRON", "SANDALPHON", "LELIEL", "CASPER"]'

if [[ "$ENGINE" == "magi" ]]; then
  FINDINGS_JSON=$(read_json "$FINDINGS_FILE" "MAGI findings table")
  if ! jq -e '
    def nonempty_string: type == "string" and length > 0;
    def valid_line:
      type == "null"
      or (type == "number" and floor == . and . > 0);
    def valid_evidence:
      type == "null" or nonempty_string;
    def personas: ["MELCHIOR", "BALTHASAR", "METATRON", "SANDALPHON", "LELIEL", "CASPER"];
    type == "object"
    and .schema_version? == "1"
    and (.findings? | type) == "array"
    and ([.findings[].id] | length) == ([.findings[].id] | unique | length)
    and all(.findings[];
      . as $finding
      | all(["id", "persona", "severity", "headline", "body", "evidence", "original_path", "original_line"][];
          . as $key | ($finding | has($key)))
      and ($finding.id | nonempty_string)
      and ($finding.persona as $persona | (personas | index($persona)) != null)
      and ($finding.severity | nonempty_string)
      and ($finding.headline | nonempty_string)
      and ($finding.body | nonempty_string)
      and ($finding.evidence | valid_evidence)
      and ($finding.original_path | nonempty_string)
      and ($finding.original_line | valid_line)
    )
  ' <<<"$FINDINGS_JSON" >/dev/null 2>&1; then
    die "MAGI findings table の構造が不正です"
  fi
else
  FINDINGS_JSON=$(read_json "$FINDINGS_FILE" "Codex findings table")
  if ! jq -e '
    def nonempty_string: type == "string" and length > 0;
    def valid_line:
      type == "null"
      or (type == "number" and floor == . and . > 0);
    def gates: ["block", "defer", "manual"];
    def personas: ["MELCHIOR", "BALTHASAR", "METATRON", "SANDALPHON", "LELIEL", "CASPER"];
    type == "array"
    and ([.[].id] | length) == ([.[].id] | unique | length)
    and all(.[];
      . as $finding
      | all(["id", "source_persona", "path", "line", "headline", "body", "gate"][];
          . as $key | ($finding | has($key)))
      and ($finding.id | nonempty_string)
      and ($finding.source_persona as $persona | (personas | index($persona)) != null)
      and ($finding.path | nonempty_string)
      and ($finding.line | valid_line)
      and ($finding.headline | nonempty_string)
      and ($finding.body | nonempty_string)
      and ($finding.gate as $gate | (gates | index($gate)) != null)
    )
  ' <<<"$FINDINGS_JSON" >/dev/null 2>&1; then
    die "Codex findings table の構造が不正です"
  fi
fi

if [[ $# -eq 3 ]]; then
  FAILED_PERSONAS_JSON=$(read_json "$FAILED_PERSONAS_FILE" "failed-personas")
  if ! jq -e --argjson allowed "$PERSONAS" '
    type == "array"
    and all(.[];
      . as $persona
      | type == "string" and length > 0 and ($allowed | index($persona)) != null
    )
    and (length == (unique | length))
  ' <<<"$FAILED_PERSONAS_JSON" >/dev/null 2>&1; then
    die "failed-personas の構造が不正です"
  fi
  if jq -e 'length == 0' <<<"$FAILED_PERSONAS_JSON" >/dev/null 2>&1; then
    DETECTION_STATUS="complete"
  else
    DETECTION_STATUS="incomplete"
  fi
else
  FAILED_PERSONAS_JSON="null"
  DETECTION_STATUS="unknown"
fi

ARTIFACT_FILE="$TMPDIR_ARTIFACT/findings-artifact.json"
if [[ "$ENGINE" == "magi" ]]; then
  if ! jq -n \
    --slurpfile source "$FINDINGS_FILE" \
    --argjson failed "$FAILED_PERSONAS_JSON" \
    --arg status "$DETECTION_STATUS" '
      {
        schema_version: "1",
        engine: "magi",
        detection_status: $status,
        failed_personas: $failed,
        findings: ($source[0].findings | map({
          id: .id,
          source_persona: .persona,
          path: .original_path,
          line: .original_line,
          headline: .headline,
          body: .body,
          evidence: .evidence,
          reported_gate: null,
          gate_provenance: null
        }))
      }
    ' >"$ARTIFACT_FILE"; then
    die "canonical artifact の生成に失敗しました"
  fi
else
  if ! jq -n \
    --slurpfile source "$FINDINGS_FILE" \
    --argjson failed "$FAILED_PERSONAS_JSON" \
    --arg status "$DETECTION_STATUS" '
      {
        schema_version: "1",
        engine: "codex",
        detection_status: $status,
        failed_personas: $failed,
        findings: ($source[0] | map({
          id: .id,
          source_persona: .source_persona,
          path: .path,
          line: .line,
          headline: .headline,
          body: .body,
          evidence: null,
          reported_gate: .gate,
          gate_provenance: (if .source_persona == "CASPER" then "deterministic" else "model_reported" end)
        }))
      }
    ' >"$ARTIFACT_FILE"; then
    die "canonical artifact の生成に失敗しました"
  fi
fi

if ! jq -e '
  def nonempty_string: type == "string" and length > 0;
  def gates: ["block", "defer", "manual"];
  def provenances: ["model_reported", "deterministic"];
  def personas: ["MELCHIOR", "BALTHASAR", "METATRON", "SANDALPHON", "LELIEL", "CASPER"];
  def valid_line:
    type == "null"
    or (type == "number" and floor == . and . > 0);
  def valid_evidence:
    type == "null" or nonempty_string;
  type == "object"
  and has("schema_version") and .schema_version == "1"
  and has("engine") and (.engine | IN("magi", "codex"))
  and has("detection_status") and (.detection_status | IN("complete", "incomplete", "unknown"))
  and has("failed_personas")
  and (
    if .failed_personas == null then true
    else
      (.failed_personas | type) == "array"
      and all(.failed_personas[];
        . as $persona
        | type == "string" and length > 0 and (personas | index($persona)) != null
      )
      and ((.failed_personas | length) == (.failed_personas | unique | length))
    end
  )
  and (
    (.detection_status == "complete" and .failed_personas == [])
    or (.detection_status == "incomplete" and (.failed_personas | type) == "array" and (.failed_personas | length) > 0)
    or (.detection_status == "unknown" and .failed_personas == null)
  )
  and has("findings") and (.findings | type) == "array"
  and ([.findings[].id] | length) == ([.findings[].id] | unique | length)
  and all(.findings[];
    . as $finding
    | all(["id", "source_persona", "path", "line", "headline", "body", "evidence", "reported_gate", "gate_provenance"][];
        . as $key | ($finding | has($key)))
    and ($finding.id | nonempty_string)
    and ($finding.source_persona as $persona | (personas | index($persona)) != null)
    and ($finding.path | nonempty_string)
    and ($finding.line | valid_line)
    and ($finding.headline | nonempty_string)
    and ($finding.body | nonempty_string)
    and ($finding.evidence | valid_evidence)
    and (($finding.reported_gate == null) or ($finding.reported_gate as $gate | (gates | index($gate)) != null))
    and (($finding.gate_provenance == null) or ($finding.gate_provenance as $provenance | (provenances | index($provenance)) != null))
    and (($finding.reported_gate == null) == ($finding.gate_provenance == null))
  )
  and (
    if .engine == "magi" then
      all(.findings[]; .reported_gate == null and .gate_provenance == null)
    else
      all(.findings[];
        if .source_persona == "CASPER" then
          .reported_gate == "block" and .gate_provenance == "deterministic"
        else
          (.reported_gate as $gate | (gates | index($gate)) != null)
          and .gate_provenance == "model_reported"
        end
      )
    end
  )
' "$ARTIFACT_FILE" >/dev/null 2>&1; then
  die "canonical artifact の自己検証に失敗しました"
fi

jq -c '.' "$ARTIFACT_FILE"
