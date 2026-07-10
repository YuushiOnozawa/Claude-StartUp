#!/usr/bin/env bash
# sync-check.sh: 実働環境の配布原本への還流漏れを検知する。
set -uo pipefail

usage() {
  echo "Usage: $0 [--verbose] [live_path] [repo_path]" >&2
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

relative_path() {
  local path="$1"
  printf '%s' "${path#"$live_path"/}"
}

display_path() {
  local path="$1"
  if [[ -d "$live_path/$path" ]]; then
    printf '%s/' "${path%/}"
  else
    printf '%s' "$path"
  fi
}

add_new_item() {
  local path="$1"
  local known_path reason
  for known_path in "${!known_deletions[@]}"; do
    [[ "$path" == "$known_path" ]] || continue
    reason="${known_deletions[$known_path]}"
    if [[ -n "$reason" ]]; then
      known_deletion_items+=("$(display_path "$path")  [$reason]")
    else
      known_deletion_items+=("$(display_path "$path")")
    fi
    return
  done
  new_items+=("$(display_path "$path")")
}

add_changed_item() {
  changed_items+=("$(display_path "$1")")
}

add_identical_item() {
  identical_items+=("$(display_path "$1")")
}

compare_path() {
  local live_item="$1"
  local repo_item="$2"
  local relative_item

  [[ -e "$live_item" ]] || return
  relative_item=$(relative_path "$live_item")

  if [[ ! -e "$repo_item" ]]; then
    add_new_item "$relative_item"
  elif LC_ALL=C diff -q "$live_item" "$repo_item" >/dev/null 2>&1; then
    add_identical_item "$relative_item"
  else
    add_changed_item "$relative_item"
  fi
}

compare_recursive() {
  local relative_root="$1"
  local live_root="$live_path/$relative_root"
  local repo_root="$repo_path/$relative_root"
  local diff_output line relative_item

  [[ -e "$live_root" ]] || return

  if [[ ! -e "$repo_root" ]]; then
    if [[ -d "$live_root" ]]; then
      shopt -s nullglob dotglob
      local live_item
      local entries=("$live_root"/*)
      shopt -u nullglob dotglob
      if ((${#entries[@]})); then
        for live_item in "${entries[@]}"; do
          add_new_item "$(relative_path "$live_item")"
        done
      else
        add_new_item "$relative_root"
      fi
    else
      add_new_item "$relative_root"
    fi
    return
  fi

  if diff_output=$(LC_ALL=C diff -rq "$live_root" "$repo_root"); then
    add_identical_item "$relative_root"
    return
  fi

  while IFS= read -r line; do
    case "$line" in
      "Only in $live_path"*:*)
        relative_item="${line#Only in $live_path/}"
        relative_item="${relative_item%%: *}/${relative_item##*: }"
        add_new_item "$relative_item"
        ;;
      "Files $live_path"*" differ"|"Binary files $live_path"*" differ"|"Symbolic links $live_path"*" differ")
        line="${line#Files }"
        line="${line#Binary files }"
        line="${line#Symbolic links }"
        relative_item="${line%% and *}"
        add_changed_item "$(relative_path "$relative_item")"
        ;;
      "File $live_path"*" is "*)
        relative_item="${line#File }"
        relative_item="${relative_item%% is *}"
        add_changed_item "$(relative_path "$relative_item")"
        ;;
    esac
  done <<<"$diff_output"
}

verbose=false
positional=()
while (($#)); do
  case "$1" in
    --verbose)
      verbose=true
      ;;
    --*)
      usage
      exit 2
      ;;
    *)
      positional+=("$1")
      ;;
  esac
  shift
done

if ((${#positional[@]} > 2)); then
  usage
  exit 2
fi

live_path="${positional[0]-$HOME/.claude}"
repo_path="${positional[1]-$HOME/srcs/Claude-StartUp}"
whitelist_path="$repo_path/scripts/sync-whitelist.conf"
known_deletions_path="$repo_path/scripts/sync-known-deletions.conf"

if [[ ! -f "$whitelist_path" ]]; then
  echo "Error: sync whitelist not found: $whitelist_path" >&2
  exit 2
fi
if [[ ! -d "$live_path" ]]; then
  echo "Error: live path is not a directory: $live_path" >&2
  exit 2
fi

declare -A known_deletions=()
if [[ -f "$known_deletions_path" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    line=$(trim "$line")
    [[ -z "$line" || "$line" == \#* ]] && continue
    if [[ "$line" == *'#'* ]]; then
      path=$(trim "${line%%#*}")
      reason=$(trim "${line#*#}")
    else
      path="$line"
      reason=""
    fi
    [[ -n "$path" ]] && known_deletions["$path"]="$reason"
  done <"$known_deletions_path"
else
  echo "Warning: known deletions file not found: $known_deletions_path" >&2
fi

new_items=()
changed_items=()
known_deletion_items=()
identical_items=()

while IFS= read -r line || [[ -n "$line" ]]; do
  [[ "$line" == '+ '* ]] || continue
  pattern="${line#+ }"
  if [[ "$pattern" =~ ^/(.+)/\*\*\*$ ]]; then
    compare_recursive "${BASH_REMATCH[1]}"
  elif [[ "$pattern" =~ ^/(.+)/\*\.sh$ ]]; then
    directory="${pattern#/}"
    directory="${directory%/*.sh}"
    shopt -s nullglob
    for live_item in "$live_path/$directory"/*.sh; do
      compare_path "$live_item" "$repo_path/$directory/${live_item##*/}"
    done
    shopt -u nullglob
  elif [[ "$pattern" == /* ]]; then
    compare_path "$live_path/${pattern#/}" "$repo_path/${pattern#/}"
  fi
done <"$whitelist_path"

sort_items() {
  local -n items="$1"
  ((${#items[@]})) || return
  mapfile -t items < <(printf '%s\n' "${items[@]}" | LC_ALL=C sort -u)
}

sort_items new_items
sort_items changed_items
sort_items known_deletion_items
sort_items identical_items

print_section() {
  local heading="$1"
  local -n items="$2"
  ((${#items[@]})) || return
  printf '%s\n' "$heading"
  local item
  for item in "${items[@]}"; do
    printf '  %s\n' "$item"
  done
  printf '\n'
}

print_section '=== 要還流（新規）: 実働環境にのみ存在 ===' new_items
print_section '=== 要還流（変更）: 両側に存在するが差分あり ===' changed_items
print_section '=== 削除予定（既知）: 還流しない ===' known_deletion_items
if "$verbose"; then
  printf '%s\n' '=== 同一 ==='
  for item in "${identical_items[@]}"; do
    printf '  %s\n' "$item"
  done
fi

if ((${#new_items[@]} + ${#changed_items[@]})); then
  exit 1
fi
