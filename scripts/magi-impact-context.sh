#!/usr/bin/env bash

# magi-impact-context.sh — $DIFF から呼び出し元スニペット付き $IMPACT_CONTEXT を生成する
# Usage: bash scripts/magi-impact-context.sh "$DIFF"
# 失敗時は空文字を出力して exit 0（中断しない）
#
# ツール選定: codegraph（MCP 経由のコールグラフ）を優先し、未インストール時は rg、
# rg も無ければ grep -rn にフォールバックする。以前は rg 固定だったため、rg 未インストール
# 環境では全 symbol が無ヒットとなり $IMPACT_CONTEXT が常に空になっていた（失敗が
# 2>/dev/null と呼び出し元の「失敗時は空文字で続行」で二重に飲まれ検知できなかった）。
# ctags/cscope は動的に生成したインデックスの更新タイミングが不安定なため不採用。LSP は
# バックグラウンドサーバー起動を必要とし bash スクリプトからの呼び出しが困難なため不採用。
#
# 出力は2部構成:
#   1. symbol 単位の呼び出し元スニペット — 関数・変数の定義追加が既存コードに与える影響
#   2. パス単位の被参照 — 変更ファイル自体を配置・登録・起動している箇所
#      shell 中心の repo では 1 がほとんどヒットせず、回帰の実経路（setup による配置、
#      settings.json への hook 登録、他スクリプトからの起動）は 2 にしか現れないため。

DIFF="${1:-}"
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo ".")
MAX_CALLERS=5
CONTEXT_LINES=5
MAX_SYMBOLS=20      # LLM コンテキスト圧迫防止のための上限（パフォーマンス制限）
MAX_PATH_REFS=6     # 1ファイルあたりの被参照表示上限
MAX_BYTES=12000     # 総量上限。OLLAMA_NUM_CTX=16384 を溢れさせないため

# 検索から除外する: .git と repo 内 worktree の複製。worktree を含めると同一ファイルの
# コピーが呼び出し元として大量に出て、出力が 60KB 超に膨らみ num_ctx を溢れさせる。

# codegraph が居ても 0 件なら symbol ごとに _search へフォールスルーするため、
# rg の有無は codegraph の有無と無関係に効く。警告条件は rg だけで判定する。
if ! command -v rg >/dev/null 2>&1; then
  echo "warn: magi-impact-context: rg 未インストール。grep にフォールバックします" >&2
fi

# _search <pattern> <word_match:0|1> <limit>
_search() {
  local pat="$1" word="$2" limit="$3"
  if command -v rg >/dev/null 2>&1; then
    if [ "$word" = "1" ]; then
      # symbol 検索では設定・データファイルを除外する（shell 関数の呼び出し元になり得ない）
      rg -n --no-heading -w "$pat" "$REPO_ROOT" \
        --glob '!*.md' --glob '!*.txt' --glob '!*.json' --glob '!*.yaml' --glob '!*.yml' \
        --glob '!.git/*' --glob '!worktree/*' \
        2>/dev/null | head -"$limit"
    else
      rg -n --no-heading -F "$pat" "$REPO_ROOT" \
        --glob '!.git/*' --glob '!worktree/*' --glob '!*.jsonl' \
        2>/dev/null | head -"$limit"
    fi
  else
    if [ "$word" = "1" ]; then
      grep -rn -w --exclude='*.md' --exclude='*.txt' \
        --exclude='*.json' --exclude='*.yaml' --exclude='*.yml' \
        --exclude-dir=.git --exclude-dir=worktree \
        "$pat" "$REPO_ROOT" 2>/dev/null | head -"$limit"
    else
      grep -rn -F --exclude='*.jsonl' \
        --exclude-dir=.git --exclude-dir=worktree \
        "$pat" "$REPO_ROOT" 2>/dev/null | head -"$limit"
    fi
  fi
}

OUTPUT=""

# ---------- 1. symbol 単位の呼び出し元 ----------
# 既存パターン（def/function/fn/const/let/var）に加え、shell の `name() {` 形式も拾う。
#
# 汎用ヘルパー名は除外する。`fail` `cleanup` `ok` などは repo 全体に散在するため、
# 呼び出し元として検出しても影響分析の材料にならず、出力の大半をノイズで埋める
# （実測: 除外前は symbol セクションが 4.5KB を占め、有効な情報はゼロだった）。
_GENERIC_SYMBOLS='^(ok|fail|warn|error|info|log|die|usage|main|run|cleanup|trim|init|setup|teardown|check|start|stop|skip|pass|note|debug|print|echo|help|version)$'

_SYMBOLS_RAW=$( { printf '%s\n' "$DIFF" | grep '^+' | grep -v '^+++' \
                   | sed -nE 's/.*(def|function|fn|const|let|var)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\2/p'
                 printf '%s\n' "$DIFF" | grep '^+' | grep -v '^+++' \
                   | sed -nE 's/^\+[[:space:]]*(function[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*\(\)[[:space:]]*\{.*/\2/p'
               } 2>/dev/null | grep -v '^$') || true
SYMBOLS_ALL=$(printf '%s\n' "$_SYMBOLS_RAW" | sort -u | head -"$MAX_SYMBOLS") || true
SYMBOLS=$(printf '%s\n' "$_SYMBOLS_RAW" | grep -Ev "$_GENERIC_SYMBOLS" \
          | sort -u | head -"$MAX_SYMBOLS") || true

CODEGRAPH_AVAILABLE=0
if command -v codegraph >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  CODEGRAPH_STATUS=$(codegraph status -j "$REPO_ROOT" 2>/dev/null || true)
  # codegraph は未初期化でも exit 0 を返すため、status の JSON を parse して判定する。
  if printf '%s' "$CODEGRAPH_STATUS" | jq -e '.initialized == true' >/dev/null 2>&1; then
    CODEGRAPH_AVAILABLE=1
  fi
fi

if [ "$CODEGRAPH_AVAILABLE" = "1" ]; then
  SYMBOLS_FOR_LOOKUP="$SYMBOLS_ALL"
else
  SYMBOLS_FOR_LOOKUP="$SYMBOLS"
fi

for SYMBOL in $SYMBOLS_FOR_LOOKUP; do
  if [ "$CODEGRAPH_AVAILABLE" = "1" ]; then
    # -l は kind=="file" を捨てる前に効くため、そのまま MAX_CALLERS を渡すと
    # ファイルノードが枠を食い潰して実際の呼び出し元が数件しか残らない。
    # 多めに取得して、絞り込んだ後に MAX_CALLERS で切る。
    CALLERS=$(codegraph callers "$SYMBOL" -p "$REPO_ROOT" -l $((MAX_CALLERS * 2)) -j 2>/dev/null \
      | jq -r --arg repo "$REPO_ROOT" '
          if (.callers | type) == "array" then
            .callers[]
            | select(.kind != "file")
            | select((.filePath? | type) == "string" and (.startLine? | type) == "number")
            | "\($repo)/\(.filePath):\(.startLine|tostring)"
          else empty end
        ' 2>/dev/null | head -"$MAX_CALLERS" || true)
    # codegraph が 0 件なら、その言語に未対応の可能性があるため rg/grep にフォールスルーする。
    if [ -z "$CALLERS" ]; then
      [[ "$SYMBOL" =~ $_GENERIC_SYMBOLS ]] && continue
      CALLERS=$(_search "$SYMBOL" 1 "$MAX_CALLERS")
    fi
  else
    CALLERS=$(_search "$SYMBOL" 1 "$MAX_CALLERS")
  fi

  if [ -z "$CALLERS" ]; then
    continue
  fi

  OUTPUT="${OUTPUT}### ${SYMBOL}"
  OUTPUT="${OUTPUT}"$'\n'
  while IFS= read -r LINE; do
    FILEPATH=$(printf '%s' "$LINE" | cut -d: -f1)
    LINENUM=$(printf '%s' "$LINE" | cut -d: -f2)

    if [ -f "$FILEPATH" ] && [[ "$LINENUM" =~ ^[0-9]+$ ]]; then
      START=$(( LINENUM > CONTEXT_LINES ? LINENUM - CONTEXT_LINES : 1 ))
      END=$(( LINENUM + CONTEXT_LINES ))
      SNIPPET=$(sed -n "${START},${END}p" "$FILEPATH" 2>/dev/null || true)
      OUTPUT="${OUTPUT}**${FILEPATH}:${LINENUM}**"
      OUTPUT="${OUTPUT}"$'\n'
      OUTPUT="${OUTPUT}\`\`\`"
      OUTPUT="${OUTPUT}"$'\n'
      OUTPUT="${OUTPUT}${SNIPPET}"
      OUTPUT="${OUTPUT}"$'\n'
      OUTPUT="${OUTPUT}\`\`\`"
      OUTPUT="${OUTPUT}"$'\n'
    fi
  done <<< "$CALLERS"
done

# ---------- 2. パス単位の被参照 ----------
CHANGED_PATHS=$(printf '%s\n' "$DIFF" | grep '^diff --git' | awk '{print $NF}' | sed 's|^b/||' | sort -u) || true

PATH_SECTION=""
if [ -n "$CHANGED_PATHS" ]; then
  while IFS= read -r CHANGED; do
    BASE=$(basename "$CHANGED")
    # 自ファイル内の行は呼び出し元ではないので除外する
    REFS=$(_search "$BASE" 0 $((MAX_PATH_REFS + 4)) \
            | grep -v ":.*${CHANGED}:" | grep -v "/${CHANGED}:" | head -"$MAX_PATH_REFS") || true
    [ -z "$REFS" ] && continue
    PATH_SECTION="${PATH_SECTION}### ${CHANGED} の被参照"
    PATH_SECTION="${PATH_SECTION}"$'\n'
    PATH_SECTION="${PATH_SECTION}\`\`\`"
    PATH_SECTION="${PATH_SECTION}"$'\n'
    PATH_SECTION="${PATH_SECTION}${REFS}"
    PATH_SECTION="${PATH_SECTION}"$'\n'
    PATH_SECTION="${PATH_SECTION}\`\`\`"
    PATH_SECTION="${PATH_SECTION}"$'\n'
  done <<< "$CHANGED_PATHS"
fi

if [ -n "$PATH_SECTION" ]; then
  OUTPUT="${OUTPUT}## 変更ファイルの被参照（配置・登録・起動元）"
  OUTPUT="${OUTPUT}"$'\n'
  OUTPUT="${OUTPUT}${PATH_SECTION}"
fi

# ---------- 3. 総量上限と空検知 ----------
if [ -z "$OUTPUT" ]; then
  echo "warn: magi-impact-context: 呼び出し元を検出できませんでした（symbol・パスとも無ヒット）" >&2
  exit 0
fi

if [ "${#OUTPUT}" -gt "$MAX_BYTES" ]; then
  echo "warn: magi-impact-context: ${MAX_BYTES} バイト上限で切り詰めました" >&2
  OUTPUT="${OUTPUT:0:$MAX_BYTES}"$'\n'"...(truncated)"
fi

printf '%s' "$OUTPUT"
