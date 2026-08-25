#!/usr/bin/env bash
# 指定キーの完全一致で候補配列を first-occurrence order のまま重複統合する。
set -euo pipefail

usage() {
  echo "usage: bash scripts/review-dedup-findings.sh <key1,key2,...> <input.json>" >&2
  exit 2
}

die() {
  echo "$1" >&2
  exit 2
}

[[ $# -eq 2 ]] || usage

KEYS_CSV="$1"
INPUT_FILE="$2"

[[ -n "$KEYS_CSV" ]] || die "重複判定キーを指定してください"
[[ -r "$INPUT_FILE" ]] || die "入力ファイルを読み取れません: $INPUT_FILE"

if ! jq -e --arg key_csv "$KEYS_CSV" '
  ($key_csv | split(",")) as $keys
  | if ($keys | length) == 0 or any($keys[]; length == 0) then
      error("重複判定キーが空です")
    elif type != "array" then
      error("入力は JSON 配列で指定してください")
    elif any(.[]; type != "object") then
      error("入力配列の要素は JSON object で指定してください")
    elif any(.[]; . as $finding | any($keys[]; . as $key | ($finding | has($key) | not))) then
      error("指定された重複判定キーが候補に存在しません")
    else
      def strongest_gate:
        if any(.[]; . == "block") then "block"
        elif any(.[]; . == "manual") then "manual"
        else "defer"
        end;

      reduce .[] as $finding (
        {findings: [], seen_keys: [], gate_values: []};
        ($keys | map($finding[.])) as $key
        | (.seen_keys | map(. == $key) | index(true)) as $index
        | if $index == null then
            .findings += [$finding]
            | .seen_keys += [$key]
            | .gate_values += [if ($finding | has("gate")) then [$finding.gate] else [] end]
          elif ($finding | has("gate")) then
            .gate_values[$index] += [$finding.gate]
          else
            .
          end
      )
      | .findings as $findings
      | .gate_values as $gate_values
      | [range(0; ($findings | length)) as $index
         | $findings[$index] as $finding
         | if (($gate_values[$index] | length) > 1)
             and (($gate_values[$index] | unique | length) > 1) then
             $finding + {gate: ($gate_values[$index] | strongest_gate)}
           else
             $finding
           end]
    end
' "$INPUT_FILE"; then
  die "入力契約違反のため dedup を実行できません"
fi
