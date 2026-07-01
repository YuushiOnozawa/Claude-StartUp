#!/usr/bin/env bash
# hooks/lib/queue.sh — 汎用フックエラーキューライブラリ
# Usage: source "$(dirname "$0")/lib/queue.sh"

QUEUE_BASE_DIR="${HOME}/.claude/hooks/queue"
QUEUE_LOCK_DIR="${QUEUE_BASE_DIR}/.locks"

# queue_push: キューにアイテムを追加する
# 引数: hook_name reason source_path [cwd]
queue_push() {
  local hook_name="$1"
  local reason="$2"
  local source_path="$3"
  local cwd="${4:-}"

  local queue_dir="${QUEUE_BASE_DIR}/${hook_name}"
  mkdir -p "$queue_dir" "$QUEUE_LOCK_DIR"

  local ts
  ts=$(date +%Y%m%d-%H%M%S)
  local item_file="${queue_dir}/${ts}-${RANDOM}.json"
  local tmp_file="${item_file}.tmp"

  jq -n \
    --arg source_path "$source_path" \
    --arg cwd "$cwd" \
    --arg reason "$reason" \
    '{"source_path":$source_path,"cwd":$cwd,"reason":$reason,"retry_count":0}' \
    > "$tmp_file" && mv "$tmp_file" "$item_file" && return 0 || { rm -f "$tmp_file"; return 1; }
}

# queue_count: キューのアイテム数を返す
# 引数: hook_name [reason_filter]
queue_count() {
  local hook_name="$1"
  local reason_filter="${2:-}"

  local queue_dir="${QUEUE_BASE_DIR}/${hook_name}"
  [[ -d "$queue_dir" ]] || { echo 0; return; }

  local count=0
  for f in "${queue_dir}"/*.json; do
    [[ -f "$f" ]] || continue
    if [[ -n "$reason_filter" ]]; then
      local r
      r=$(jq -r '.reason // ""' "$f" 2>/dev/null)
      [[ "$r" == "$reason_filter" ]] || continue
    fi
    ((count++)) || true
  done
  echo "$count"
}

# queue_summary: キューの概要文字列を返す（件数あり→"N件: ...", なし→空文字）
# 引数: hook_name
queue_summary() {
  local hook_name="$1"
  local queue_dir="${QUEUE_BASE_DIR}/${hook_name}"
  [[ -d "$queue_dir" ]] || { echo ""; return; }

  local items=()
  for f in "${queue_dir}"/*.json; do
    [[ -f "$f" ]] || continue
    local reason ts
    reason=$(jq -r '.reason // "unknown"' "$f" 2>/dev/null)
    ts=$(basename "$f" .json)
    items+=("${ts}(${reason})")
  done

  if [[ ${#items[@]} -gt 0 ]]; then
    echo "${#items[@]}件: ${items[*]}"
  else
    echo ""
  fi
}

# queue_drain: キューアイテムを処理する（flock で同時実行排除）
# 引数: hook_name reason_filter(""で全件) callback関数名
# callback は item_file パスを受け取り、成功なら 0、失敗なら 非0 を返す
queue_drain() {
  local hook_name="$1"
  local reason_filter="$2"
  local callback="$3"

  local queue_dir="${QUEUE_BASE_DIR}/${hook_name}"
  [[ -d "$queue_dir" ]] || return 0

  local lock_file="${QUEUE_LOCK_DIR}/${hook_name}.lock"
  mkdir -p "$QUEUE_LOCK_DIR"

  (
    flock -n 9 || { echo "[queue] lock busy, skipping drain" >&2; exit 0; }

    for item_file in "${queue_dir}"/*.json; do
      [[ -f "$item_file" ]] || continue

      # reason フィルタ
      if [[ -n "$reason_filter" ]]; then
        local item_reason
        item_reason=$(jq -r '.reason // ""' "$item_file" 2>/dev/null)
        [[ "$item_reason" == "$reason_filter" ]] || continue
      fi

      # source ファイル存在確認
      local source_path
      source_path=$(jq -r '.source_path // ""' "$item_file" 2>/dev/null)
      if [[ -n "$source_path" ]] && [[ ! -f "$source_path" ]]; then
        queue_deadletter "$hook_name" "$item_file" "source_not_found"
        continue
      fi

      # コールバック実行
      if "$callback" "$item_file"; then
        rm -f "$item_file" "${item_file%.json}.notified" 2>/dev/null
      else
        local retry_count
        retry_count=$(jq '.retry_count // 0' "$item_file" 2>/dev/null)
        if [[ "$retry_count" -ge 3 ]]; then
          queue_deadletter "$hook_name" "$item_file" "max_retries"
        else
          jq --argjson n "$((retry_count + 1))" '.retry_count = $n' "$item_file" \
            > "${item_file}.tmp" && mv "${item_file}.tmp" "$item_file" || true
        fi
      fi
    done

  ) 9>"$lock_file"
}

# queue_deadletter: アイテムをデッドレターキューへ移動する
# 引数: hook_name item_file reason
queue_deadletter() {
  local hook_name="$1"
  local item_file="$2"
  local reason="${3:-unknown}"

  local dl_dir="${QUEUE_BASE_DIR}/dead-letter/${hook_name}"
  mkdir -p "$dl_dir"

  local basename
  basename=$(basename "$item_file" .json)
  if jq --arg dl_reason "$reason" '. + {"dead_letter_reason": $dl_reason}' "$item_file" \
      > "${dl_dir}/${basename}.json" 2>/dev/null; then
    rm -f "$item_file" "${item_file%.json}.notified" 2>/dev/null
  fi
}

# queue_notify_needed: 未通知アイテムがあれば 0、なければ 1 を返す
# 引数: hook_name
queue_notify_needed() {
  local hook_name="$1"
  local queue_dir="${QUEUE_BASE_DIR}/${hook_name}"
  [[ -d "$queue_dir" ]] || return 1

  for f in "${queue_dir}"/*.json; do
    [[ -f "$f" ]] || continue
    local flag="${f%.json}.notified"
    [[ -f "$flag" ]] || return 0  # 未通知あり
  done
  return 1  # 全件通知済み
}

# queue_notify_mark: 全アイテムに通知済みフラグを立てる
# 引数: hook_name
queue_notify_mark() {
  local hook_name="$1"
  local queue_dir="${QUEUE_BASE_DIR}/${hook_name}"
  [[ -d "$queue_dir" ]] || return 0

  for f in "${queue_dir}"/*.json; do
    [[ -f "$f" ]] || continue
    touch "${f%.json}.notified" 2>/dev/null || true
  done
}

# queue_notify_send: デスクトップ通知（失敗は無視）
# 引数: title message
queue_notify_send() {
  local title="$1"
  local message="$2"
  command -v notify-send &>/dev/null \
    && notify-send "$title" "$message" 2>/dev/null || true
}
