#!/usr/bin/env bash
# scripts/codex-review-merge.sh — Codex 監査結果の完全性検証と決定的マージ
set -euo pipefail

usage() {
  echo "usage: $0 FINDINGS_TABLE_JSON AUDIT_JSON SELF_TAMPER_JSON FAILED_PERSONAS_JSON" >&2
  exit 2
}

[[ $# -eq 4 ]] || usage

FINDINGS_FILE="$1"
AUDIT_FILE="$2"
SELF_TAMPER_FILE="$3"
FAILED_PERSONAS_FILE="$4"

for input_file in "$FINDINGS_FILE" "$AUDIT_FILE" "$SELF_TAMPER_FILE" "$FAILED_PERSONAS_FILE"; do
  [[ -r "$input_file" ]] || {
    echo "入力ファイルを読み取れません: $input_file" >&2
    exit 2
  }
done

strict_json() {
  local input_file="$1"
  jq -s -c 'if length == 1 then .[0] else error("expected exactly one JSON value") end' "$input_file"
}

if ! findings_json="$(strict_json "$FINDINGS_FILE" 2>/dev/null)"; then
  echo "findings table の JSON が不正です" >&2
  exit 2
fi

if ! failed_personas_json="$(strict_json "$FAILED_PERSONAS_FILE" 2>/dev/null)"; then
  echo "failed_personas の JSON が不正です" >&2
  exit 2
fi

if ! self_tamper_json="$(strict_json "$SELF_TAMPER_FILE" 2>/dev/null)"; then
  echo "self-tamper 判定の JSON が不正です" >&2
  exit 2
fi

if ! jq -e '
  def nonempty_string: type == "string" and length > 0;
  def personas: ["MELCHIOR", "BALTHASAR", "METATRON", "SANDALPHON", "LELIEL", "CASPER"];
  def gates: ["block", "defer", "manual"];
  def valid_line:
    type == "null"
    or (type == "number" and floor == .);
  def valid_finding:
    type == "object"
    and has("id") and (.id | nonempty_string)
    and has("source_persona") and (.source_persona as $p | (personas | index($p)) != null)
    and has("path") and (.path == null or (.path | nonempty_string))
    and has("line") and (.line | valid_line)
    and has("headline") and (.headline | nonempty_string)
    and has("body") and (.body | nonempty_string)
    and has("gate") and (.gate as $g | (gates | index($g)) != null);
  if type != "array" then false
  else
    ([.[].id] | length) == ([.[].id] | unique | length)
    and all(.[]; valid_finding)
  end
' <<<"$findings_json" >/dev/null 2>&1; then
  echo "findings table の構造が不正です" >&2
  exit 2
fi

if ! jq -e '
  type == "array" and all(.[]; type == "string")
' <<<"$failed_personas_json" >/dev/null 2>&1; then
  echo "failed_personas の構造が不正です" >&2
  exit 2
fi

if ! jq -e 'type == "boolean"' <<<"$self_tamper_json" >/dev/null 2>&1; then
  echo "self-tamper 判定は bool で指定してください" >&2
  exit 2
fi

# 監査 JSON の parse error / 非配列は監査全体失敗として扱う。
audit_global_failure=0
if ! audit_json="$(strict_json "$AUDIT_FILE" 2>/dev/null)"; then
  echo "監査出力 JSON の解析に失敗しました。全件を manual に退避します" >&2
  audit_global_failure=1
  audit_json='[]'
elif ! jq -e 'type == "array"' <<<"$audit_json" >/dev/null 2>&1; then
  echo "監査出力 JSON が配列ではありません。全件を manual に退避します" >&2
  audit_global_failure=1
  audit_json='[]'
fi

# member_ids の完全性は group 単位の判定より先に検証する。
# ここで未知 ID・欠落・重複が一つでもあれば監査全体失敗となる。
if [[ "$audit_global_failure" -eq 0 ]] && ! jq -n -e \
  --argjson findings "$findings_json" \
  --argjson audit "$audit_json" '
    def nonempty_string: type == "string" and length > 0;
    def valid_member_ids:
      type == "object"
      and has("member_ids")
      and (.member_ids | type == "array")
      and all(.member_ids[]; nonempty_string);
    if ($audit | type) != "array" then false
    elif any($audit[]; (valid_member_ids | not)) then false
    else
      ($findings | map(.id)) as $expected
      | ($audit | map(.member_ids) | add // []) as $actual
      | ($actual | sort) as $actual_sorted
      | ($actual_sorted | unique) as $actual_unique
      | ($actual_sorted == $actual_unique)
        and ($actual_unique == ($expected | sort))
    end
  ' >/dev/null 2>&1; then
  echo "監査出力の member_ids が findings table を完全にはカバーしていません。全件を manual に退避します" >&2
  audit_global_failure=1
fi

result_json="$(jq -n \
  --argjson table "$findings_json" \
  --argjson audit "$audit_json" \
  --argjson failed "$failed_personas_json" \
  --argjson self_tamper "$self_tamper_json" \
  --argjson audit_global_failed "$audit_global_failure" '
  def nonempty_string: type == "string" and length > 0;
  def allowed_noncasper: ["MELCHIOR", "BALTHASAR", "METATRON", "SANDALPHON", "LELIEL"];
  def gate_rank($gate):
    if $gate == "block" then 3
    elif $gate == "manual" then 2
    else 1
    end;
  def strongest_gate:
    if any(.[]; . == "block") then "block"
    elif any(.[]; . == "manual") then "manual"
    else "defer"
    end;
  def unique_preserving:
    reduce .[] as $item ({items: [], seen: []};
      if ((.seen | index($item)) != null) then .
      else .items += [$item] | .seen += [$item]
      end
    ) | .items;
  def raw_manual:
    {
      id: .id,
      source_persona: .source_persona,
      path: .path,
      line: .line,
      headline: .headline,
      body: .body,
      gate: "manual"
    };
  def synthetic_self_tamper($id):
    {
      id: $id,
      path: null,
      line: null,
      headline: "レビュー手順自身の変更が検出された",
      body: "レビュー手順自身の変更は、検出と手順の信頼境界が同じ差分にあるため無条件に人手確認が必要です。",
      gate: "manual",
      canonical_persona: null,
      source_personas: []
    };
  def self_id($ids):
    first(
      range(1; 1000000) as $n
      | ((if $n < 1000 then (("000" + ($n | tostring)) | .[-3:]) else ($n | tostring) end)) as $suffix
      | ("F-SELF-" + $suffix) as $candidate
      | select(($ids | index($candidate)) == null)
      | $candidate
    );

  ($table | reduce .[] as $finding ({}; .[$finding.id] = $finding)) as $by_id
  | ($table | map(.id)) as $existing_ids
  | ($audit | if type == "array" then . else [] end) as $groups
  | ($groups | map(
      if type != "object" then
        {
          group_id: null,
          member_ids: [],
          member_shape_valid: false,
          members: [],
          sources: [],
          all_casper: false,
          canonical_raw: null
        }
      else
        . as $group
        | (if ($group | has("member_ids") and ((.member_ids | type) == "array"))
           then $group.member_ids else [] end) as $member_ids
        | ($group | (
            has("member_ids")
            and ((.member_ids | type) == "array")
            and ((.member_ids | length) > 0)
            and all(.member_ids[]; nonempty_string)
          )) as $member_shape_valid
        | ($member_ids | map(if type == "string" then $by_id[.] else null end)) as $members
        | ($members | map(select(. != null) | .source_persona)) as $sources
        | (($members | length) > 0
           and ($members | all(.[]; . != null and .source_persona == "CASPER"))) as $all_casper
        | {
            group_id: (if ($group | has("group_id")) then $group.group_id else null end),
            member_ids: $member_ids,
            member_shape_valid: $member_shape_valid,
            members: $members,
            sources: $sources,
            all_casper: $all_casper,
            canonical_raw: (if ($group | has("canonical_persona")) then $group.canonical_persona else null end)
          }
      end
    )) as $normalized
  | ($normalized
     | map(.group_id | select(nonempty_string))
     | group_by(.)
     | map(select(length > 1) | .[0])) as $duplicate_group_ids
  | ($normalized | map(
      . as $group
      | ($group.sources | any(. == "CASPER")) as $has_casper
      | ($group.sources | any(. != "CASPER")) as $has_noncasper
      | ($has_casper and $has_noncasper) as $mixed_casper
      | ($group.canonical_raw as $canonical
         | ($group.all_casper
            or (($mixed_casper | not)
                and ($canonical | type) == "string"
                and ((allowed_noncasper | index($canonical)) != null)))
        ) as $canonical_valid
      | ($group.group_id | nonempty_string) as $group_id_valid
      | (($duplicate_group_ids | index($group.group_id)) != null) as $duplicate_group_id
      | (($group.member_shape_valid | not)
         or ($group_id_valid | not)
         or $duplicate_group_id
         or $mixed_casper
         or ($canonical_valid | not)) as $rejected
      | $group + {
          canonical: (if $group.all_casper then "CASPER" else $group.canonical_raw end),
          rejected: $rejected
        }
    )) as $classified
  | (if $self_tamper then self_id($existing_ids) else null end) as $self_tamper_id
  | if ($audit_global_failed == 1) then
      {
        pipeline_status: "incomplete",
        findings: [],
        manual_review: (
          ($table | map(raw_manual))
          + (if $self_tamper then [synthetic_self_tamper($self_tamper_id)] else [] end)
        ),
        failed_personas: $failed
      }
    else
      ($classified | map(select(.rejected | not))) as $valid_groups
      | ($classified | map(select(.rejected) | .member_ids[])) as $rejected_ids
      | ($table
         | map(select(.id as $id | ($rejected_ids | index($id)) != null) | raw_manual)) as $manual
      | ($valid_groups | map(
          . as $group
          | ($group.member_ids | map($by_id[.])) as $members
          | ($members
             | to_entries
             | sort_by([0 - (.value.gate | gate_rank(.)), .key])
             | .[0].value) as $representative
          | {
              group_id: $group.group_id,
              canonical_persona: $group.canonical,
              source_personas: ($members | map(.source_persona) | unique_preserving),
              path: $representative.path,
              line: $representative.line,
              headline: $representative.headline,
              body: $representative.body,
              gate: ($members | map(.gate) | strongest_gate)
            }
        )) as $final_findings
      | {
          pipeline_status: (if (($failed | length) > 0) then "incomplete" else "complete" end),
          findings: $final_findings,
          manual_review: ($manual + (if $self_tamper then [synthetic_self_tamper($self_tamper_id)] else [] end)),
          failed_personas: $failed
        }
    end
' )"

printf '%s\n' "$result_json"

if [[ "$audit_global_failure" -eq 1 ]]; then
  exit 1
fi
exit 0
