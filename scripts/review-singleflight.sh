#!/usr/bin/env bash
# scripts/review-singleflight.sh — hard review の per-PR single-flight lease
set -uo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SELF_PATH="$(realpath -m -- "$SCRIPT_DIR/review-singleflight.sh" 2>/dev/null || printf '%s' "$SCRIPT_DIR/review-singleflight.sh")"

usage() {
  echo "usage: review-singleflight.sh {acquire|renew|verify|release|status|sweep} --scope per_pr ..." >&2
  exit 2
}

emit_error() {
  local operation="$1" code="$2" state="$3" reason="$4"
  jq -cn --arg operation "$operation" --arg state "$state" --arg scope "${SCOPE:-per_pr}" \
    --arg reason "$reason" '{operation:$operation,state:$state,scope:$scope,reason:$reason}'
  printf 'review-singleflight: %s\n' "$reason" >&2
  exit "$code"
}

emit_usage_error() {
  emit_error "${OPERATION:-unknown}" 2 "contract_violation" "$1"
}

now_seconds() {
  if [[ "${REVIEW_SINGLEFLIGHT_TEST_MODE:-0}" == "1" && -n "${REVIEW_SINGLEFLIGHT_NOW:-}" ]]; then
    [[ "$REVIEW_SINGLEFLIGHT_NOW" =~ ^[0-9]+$ ]] || return 1
    printf '%s\n' "$REVIEW_SINGLEFLIGHT_NOW"
  else
    date +%s
  fi
}

stat_value() {
  local format="$1" path="$2"
  stat -c "$format" -- "$path" 2>/dev/null || stat -f "$format" -- "$path" 2>/dev/null
}

runtime_dir="${XDG_RUNTIME_DIR:-}"
LOCK_ROOT=""
SCOPE_DIR=""
JSON_FILE=""
MUTEX_FILE=""
MUTEX_OPEN=false
POST_LOCK_OPEN=false

cleanup_fds() {
  if [[ "$MUTEX_OPEN" == true ]]; then
    flock -u 9 2>/dev/null || true
    exec 9>&- 2>/dev/null || true
    MUTEX_OPEN=false
  fi
  if [[ "$POST_LOCK_OPEN" == true ]]; then
    flock -u 8 2>/dev/null || true
    exec 8>&- 2>/dev/null || true
    POST_LOCK_OPEN=false
  fi
}
trap cleanup_fds EXIT HUP INT TERM

validate_runtime_dir() {
  [[ -n "$runtime_dir" && "$runtime_dir" == /* ]] || return 1
  [[ -d "$runtime_dir" && ! -L "$runtime_dir" ]] || return 1
  local fs_type
  if [[ "${REVIEW_SINGLEFLIGHT_TEST_MODE:-0}" == "1" && -n "${REVIEW_SINGLEFLIGHT_FS_TYPE:-}" ]]; then
    fs_type="$REVIEW_SINGLEFLIGHT_FS_TYPE"
  else
    fs_type="$(findmnt -no FSTYPE -T "$runtime_dir" 2>/dev/null | awk 'NF {print $1; exit}' || true)"
    [[ -n "$fs_type" ]] || fs_type="$(stat -f -c %T -- "$runtime_dir" 2>/dev/null || true)"
    [[ -n "$fs_type" ]] || fs_type="$(stat -f '%HT' -- "$runtime_dir" 2>/dev/null || true)"
  fi
  case "$fs_type" in
    tmpfs|ramfs|ext2|ext3|ext4|xfs|btrfs|zfs|apfs|hfs+|ufs|overlay|overlayfs) ;;
    *) return 1 ;;
  esac
}

prepare_lock_root() {
  validate_runtime_dir || return 1
  LOCK_ROOT="$runtime_dir/claude-review-sf"
  [[ ! -L "$LOCK_ROOT" ]] || return 1
  if [[ ! -e "$LOCK_ROOT" ]]; then
    (umask 077 && mkdir -p -- "$LOCK_ROOT") || return 1
  fi
  [[ -d "$LOCK_ROOT" && ! -L "$LOCK_ROOT" ]] || return 1
  chmod 700 -- "$LOCK_ROOT" 2>/dev/null || return 1
  local owner mode
  owner="$(stat_value '%u' "$LOCK_ROOT")" || return 1
  mode="$(stat_value '%a' "$LOCK_ROOT")" || return 1
  [[ "$owner" == "$(id -u)" && "$mode" == "700" ]] || return 1
  SCOPE_DIR="$LOCK_ROOT/per_pr"
  [[ ! -L "$SCOPE_DIR" ]] || return 1
  if [[ ! -e "$SCOPE_DIR" ]]; then
    (umask 077 && mkdir -p -- "$SCOPE_DIR") || return 1
  fi
  [[ -d "$SCOPE_DIR" && ! -L "$SCOPE_DIR" ]] || return 1
  chmod 700 -- "$SCOPE_DIR" 2>/dev/null || return 1
  owner="$(stat_value '%u' "$SCOPE_DIR")" || return 1
  mode="$(stat_value '%a' "$SCOPE_DIR")" || return 1
  [[ "$owner" == "$(id -u)" && "$mode" == "700" ]] || return 1
}

canonicalize_key() {
  local key="$1"
  local -a parts=()
  mapfile -t parts < <(printf '%s' "$key" | awk '{print}')
  [[ "${#parts[@]}" -eq 3 ]] || return 1
  local forge_host="${parts[0]}" owner_repo="${parts[1]}" pr_number="${parts[2]}"
  [[ "$forge_host" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || return 1
  [[ "$owner_repo" =~ ^[a-z0-9][a-z0-9_.-]*/[a-z0-9][a-z0-9_.-]*$ ]] || return 1
  [[ "$pr_number" =~ ^[1-9][0-9]*$ ]] || return 1
  [[ "$key" == "$(printf '%s\n%s\n%s' "$forge_host" "$owner_repo" "$pr_number")" ]] || return 1
  CANONICAL_KEY="$key"
  KEY_FORGE_HOST="$forge_host"
  KEY_OWNER="${owner_repo%%/*}"
  KEY_REPO="${owner_repo#*/}"
  KEY_NUMBER="$pr_number"
}

key_hash_for() {
  printf '%s\0%s' "$SCOPE" "$CANONICAL_KEY" | sha256sum | cut -d' ' -f1
}

ensure_mutex_file() {
  MUTEX_FILE="$SCOPE_DIR/$KEY_HASH.mutex"
  [[ ! -L "$MUTEX_FILE" ]] || return 1
  python3 - "$MUTEX_FILE" <<'PY' >/dev/null 2>&1
import os
import sys
path = sys.argv[1]
fd = os.open(path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
os.fchmod(fd, 0o600)
os.close(fd)
PY
  [[ -f "$MUTEX_FILE" && ! -L "$MUTEX_FILE" ]] || return 1
  local owner mode
  owner="$(stat_value '%u' "$MUTEX_FILE")" || return 1
  mode="$(stat_value '%a' "$MUTEX_FILE")" || return 1
  [[ "$owner" == "$(id -u)" && "$mode" == "600" ]] || return 1
}

open_mutex() {
  ensure_mutex_file || return 1
  local wait_seconds="${REVIEW_SINGLEFLIGHT_MUTEX_WAIT_SECONDS:-5}"
  [[ "$wait_seconds" =~ ^[1-9][0-9]*$ ]] || return 1
  exec 9>>"$MUTEX_FILE" || return 1
  if ! flock -x -w "$wait_seconds" -E 9 9 2>/dev/null; then
    exec 9>&- 2>/dev/null || true
    return 1
  fi
  MUTEX_OPEN=true
}

read_token() {
  local xtrace_was_on=0
  [[ $- == *x* ]] && xtrace_was_on=1
  set +o xtrace
  local token_file="$1"
  local owner mode token rc=4
  if [[ "$token_file" == /* && -f "$token_file" && ! -L "$token_file" ]]; then
    if owner="$(stat_value '%u' "$token_file")"; then
      if mode="$(stat_value '%a' "$token_file")"; then
        if [[ "$owner" == "$(id -u)" && "$mode" == "600" ]]; then
          if token="$(<"$token_file")" && [[ "$token" =~ ^[A-Za-z0-9._:-]{8,256}$ ]] \
            && [[ "$token" != *$'\n'* && "$token" != *$'\r'* && "$token" != *' '* && "$token" != *$'\t'* ]]; then
            OWNER_TOKEN="$token"
            if TOKEN_FP="$(printf '%s' "$token" | sha256sum | cut -c1-8)"; then
              rc=0
            fi
          fi
        fi
      fi
    fi
  fi
  if (( xtrace_was_on )); then
    set -o xtrace
  else
    set +o xtrace
  fi
  return "$rc"
}

strict_json_file() {
  jq -s -c 'if length == 1 then .[0] else error("expected one JSON value") end' -- "$1" 2>/dev/null
}

read_metadata() {
  METADATA_PRESENT=false
  METADATA_JSON=''
  [[ ! -L "$JSON_FILE" ]] || return 5
  [[ -e "$JSON_FILE" ]] || return 0
  [[ -f "$JSON_FILE" ]] || return 5
  local owner mode
  owner="$(stat_value '%u' "$JSON_FILE")" || return 5
  mode="$(stat_value '%a' "$JSON_FILE")" || return 5
  [[ "$owner" == "$(id -u)" && "$mode" == "600" ]] || return 5
  METADATA_JSON="$(strict_json_file "$JSON_FILE")" || return 4
  METADATA_PRESENT=true
}

metadata_is_valid() {
  local current_now="$1"
  jq -e --arg scope "$SCOPE" --arg key_hash "$KEY_HASH" --arg key "$CANONICAL_KEY" \
    --arg forge_host "$KEY_FORGE_HOST" --arg owner "$KEY_OWNER" --arg repo "$KEY_REPO" --argjson pr_number "$KEY_NUMBER" \
    --argjson now "$current_now" '
    def nonempty_string: type == "string" and length > 0;
    def timestamp: type == "number" and floor == . and . >= 0 and . <= $now;
    type == "object"
    and .schema_version == 1 and .scope == $scope and .key_hash == $key_hash
    and .canonical_key == $key
    and (.forge_host | nonempty_string) and .forge_host == $forge_host
    and (.owner | type == "string" and . == ascii_downcase and length > 0) and .owner == $owner
    and (.repo | type == "string" and . == ascii_downcase and length > 0) and .repo == $repo
    and (.pr_number | type == "number" and floor == . and . > 0) and .pr_number == $pr_number
    and (.lease_id | nonempty_string)
    and (.token_fp | type == "string" and test("^[0-9a-f]{8}$"))
    and (.engine | type == "string" and IN("review-hard", "magi-hard", "codex-hard"))
    and (.head_sha | type == "null" or nonempty_string)
    and (.owner_session_id | nonempty_string) and (.owner_run_id | nonempty_string)
    and (.host | nonempty_string) and (.acquired_at | timestamp) and (.started_at | timestamp)
    and .started_at == .acquired_at
    and ((.last_checkpoint_at) as $last | .acquired_at as $acquired | ($last | timestamp) and $last >= $acquired)
    and (.last_completed_phase | type == "null" or nonempty_string)
    and (.current_phase | type == "null" or nonempty_string)
    and (.phase_started_at | type == "null" or timestamp)
    and (.phase_budget | type == "null" or (type == "number" and floor == . and . >= 0))
    and (.planned_overdue_at | type == "number" and floor == . and . > 0)
    and (.post_state | type == "string" and IN("not_started", "in_progress", "complete", "unknown", "post_failed", "posted", "not_applicable"))
    and (.held_resources | type == "array") and (.waiting_resources | type == "array")
    and (.artifact_path | type == "null" or nonempty_string)
    and (.log_path | type == "null" or nonempty_string)
    and (.run_artifact_path | type == "null" or nonempty_string)
    and (.run_log_path | type == "null" or nonempty_string)
  ' <<<"$METADATA_JSON" >/dev/null 2>&1
}

metadata_is_stale() {
  local current_now="$1" last planned
  last="$(jq -r '.last_checkpoint_at' <<<"$METADATA_JSON")"
  planned="$(jq -r '.planned_overdue_at' <<<"$METADATA_JSON")"
  (( current_now - last > planned ))
}

safe_holder_json() {
  local current_now="$1" state="$2"
  local lease_id token_fp acquired last planned elapsed remaining overdue
  lease_id="$(jq -r '.lease_id' <<<"$METADATA_JSON")"
  token_fp="$(jq -r '.token_fp' <<<"$METADATA_JSON")"
  acquired="$(jq -r '.acquired_at' <<<"$METADATA_JSON")"
  last="$(jq -r '.last_checkpoint_at' <<<"$METADATA_JSON")"
  planned="$(jq -r '.planned_overdue_at' <<<"$METADATA_JSON")"
  elapsed=$((current_now - acquired))
  remaining=$((planned - (current_now - last)))
  overdue=$((current_now - last - planned))
  jq -cn --arg state "$state" --arg lease_id "$lease_id" --arg token_fp "$token_fp" \
    --arg forge_host "$(jq -r '.forge_host' <<<"$METADATA_JSON")" \
    --arg owner "$(jq -r '.owner' <<<"$METADATA_JSON")" \
    --arg repo "$(jq -r '.repo' <<<"$METADATA_JSON")" \
    --arg head_sha "$(jq -r '.head_sha // ""' <<<"$METADATA_JSON")" \
    --argjson pr_number "$(jq -c '.pr_number' <<<"$METADATA_JSON")" \
    --arg engine "$(jq -r '.engine' <<<"$METADATA_JSON")" \
    --arg owner_session_id "$(jq -r '.owner_session_id' <<<"$METADATA_JSON")" \
    --arg owner_run_id "$(jq -r '.owner_run_id' <<<"$METADATA_JSON")" \
    --arg host "$(jq -r '.host' <<<"$METADATA_JSON")" \
    --argjson acquired_at "$acquired" --argjson last_checkpoint_at "$last" \
    --argjson elapsed_seconds "$elapsed" --argjson planned_overdue_at "$planned" \
    --argjson ttl_remaining_seconds "$remaining" --argjson overdue_seconds "$overdue" \
    --arg current_phase "$(jq -r '.current_phase // ""' <<<"$METADATA_JSON")" \
    --arg last_completed_phase "$(jq -r '.last_completed_phase // ""' <<<"$METADATA_JSON")" \
    --arg phase_started_at "$(jq -r '.phase_started_at // ""' <<<"$METADATA_JSON")" \
    --arg phase_budget "$(jq -r '.phase_budget // ""' <<<"$METADATA_JSON")" \
    --arg post_state "$(jq -r '.post_state' <<<"$METADATA_JSON")" \
    --argjson held_resources "$(jq -c '.held_resources' <<<"$METADATA_JSON")" \
    --argjson waiting_resources "$(jq -c '.waiting_resources' <<<"$METADATA_JSON")" \
    --arg artifact_path "$(jq -r '.artifact_path // ""' <<<"$METADATA_JSON")" \
    --arg log_path "$(jq -r '.log_path // ""' <<<"$METADATA_JSON")" \
    --arg run_artifact_path "$(jq -r '.run_artifact_path // .artifact_path // ""' <<<"$METADATA_JSON")" \
    --arg run_log_path "$(jq -r '.run_log_path // .log_path // ""' <<<"$METADATA_JSON")" \
    '{state:$state,forge_host:$forge_host,owner:$owner,repo:$repo,pr_number:$pr_number,
      head_sha:(if $head_sha=="" then null else $head_sha end),
      lease_id:$lease_id,token_fp:$token_fp,engine:$engine,
      owner_session_id:$owner_session_id,owner_run_id:$owner_run_id,host:$host,
      acquired_at:$acquired_at,last_checkpoint_at:$last_checkpoint_at,
      elapsed_seconds:$elapsed_seconds,planned_overdue_at:$planned_overdue_at,
      ttl_remaining_seconds:$ttl_remaining_seconds,overdue_seconds:$overdue_seconds,
      current_phase:(if $current_phase=="" then null else $current_phase end),
      last_completed_phase:(if $last_completed_phase=="" then null else $last_completed_phase end),
      phase_started_at:(if $phase_started_at=="" then null else ($phase_started_at|tonumber) end),
      phase_budget:(if $phase_budget=="" then null else ($phase_budget|tonumber) end),
      post_state:$post_state,held_resources:$held_resources,waiting_resources:$waiting_resources,
      artifact_path:(if $artifact_path=="" then null else $artifact_path end),
      log_path:(if $log_path=="" then null else $log_path end),
      run_artifact_path:(if $run_artifact_path=="" then null else $run_artifact_path end),
      run_log_path:(if $run_log_path=="" then null else $run_log_path end)}'
}

atomic_write() {
  local destination="$1" content="$2" tmp
  local destination_dir="$(dirname -- "$destination")"
  [[ -d "$destination_dir" && ! -L "$destination_dir" ]] || return 1
  [[ ! -L "$destination" ]] || return 1
  tmp="$(mktemp "$destination_dir/.atomic.tmp.XXXXXX" 2>/dev/null)" || return 1
  chmod 600 -- "$tmp" 2>/dev/null || { rm -f -- "$tmp"; return 1; }
  if ! printf '%s\n' "$content" >"$tmp"; then rm -f -- "$tmp"; return 1; fi
  if ! mv -f -- "$tmp" "$destination"; then rm -f -- "$tmp"; return 1; fi
}

validate_token_against_metadata() {
  local metadata_token_fp
  metadata_token_fp="$(jq -r '.token_fp // empty' <<<"$METADATA_JSON")"
  [[ -n "$metadata_token_fp" && "$metadata_token_fp" == "$TOKEN_FP" ]] || return 3
}

post_lock_path() {
  local prefix post_hash
  prefix="$(printf '%s-%s-%s' "$KEY_OWNER" "$KEY_REPO" "$KEY_NUMBER" | tr -cs 'a-z0-9._-' '-' | cut -c1-48)"
  post_hash="$(printf '%s\0%s/%s\0%s' "$KEY_FORGE_HOST" "$KEY_OWNER" "$KEY_REPO" "$KEY_NUMBER" | sha256sum | cut -d' ' -f1)"
  POST_LOCK_FILE="$runtime_dir/claude-review-post-${prefix}-${post_hash}.lock"
}

open_post_lock() {
  post_lock_path
  [[ ! -L "$POST_LOCK_FILE" ]] || return 1
  local wait_seconds="${REVIEW_SINGLEFLIGHT_POST_LOCK_WAIT_SECONDS:-3120}"
  [[ "$wait_seconds" =~ ^[1-9][0-9]*$ ]] || return 1
  (umask 077 && : >"$POST_LOCK_FILE") 2>/dev/null || return 1
  chmod 600 -- "$POST_LOCK_FILE" 2>/dev/null || return 1
  exec 8>>"$POST_LOCK_FILE" || return 1
  if ! flock -x -w "$wait_seconds" -E 9 8 2>/dev/null; then
    exec 8>&- 2>/dev/null || true
    return 1
  fi
  POST_LOCK_OPEN=true
}

parse_args() {
  [[ "$#" -ge 1 ]] || usage
  OPERATION="$1"; shift
  if [[ "$OPERATION" == force-release ]]; then OPERATION=release; FORCE_RELEASE=true; fi
  case "$OPERATION" in acquire|renew|verify|release|status|sweep) ;; *) usage ;; esac
  SCOPE_SET=false KEY_SET=false TOKEN_FILE_SET=false LEASE_ID_SET=false
  FORCE_RELEASE="${FORCE_RELEASE:-false}"; EXPECTED_SET=false; REASON_SET=false; OVERDUE_SET=false
  ENGINE=""; HEAD_SHA=""; OWNER_SESSION_ID="unspecified"; OWNER_RUN_ID="unspecified"
  OWNER_HOST="$(hostname 2>/dev/null || printf '%s' unknown)"
  CURRENT_PHASE=""; LAST_COMPLETED_PHASE=""; PHASE_STARTED_AT=""; PHASE_BUDGET=""
  CURRENT_PHASE_SET=false; LAST_COMPLETED_PHASE_SET=false; PHASE_STARTED_AT_SET=false; PHASE_BUDGET_SET=false
  POST_STATE=not_started; POST_STATE_SET=false; HELD_RESOURCES='[]'; WAITING_RESOURCES='[]'
  ARTIFACT_PATH=""; LOG_PATH=""; CANONICAL_KEY=""; TOKEN_FILE=""; LEASE_ID=""
  EXPECTED_LEASE_ID=""; RELEASE_REASON=""; OVERDUE_SECONDS=""
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --scope) [[ "$#" -ge 2 ]] || emit_usage_error "--scope の値がありません"; SCOPE="$2"; SCOPE_SET=true; shift 2 ;;
      --key) [[ "$#" -ge 2 ]] || emit_usage_error "--key の値がありません"; CANONICAL_KEY="$2"; KEY_SET=true; shift 2 ;;
      --owner-token-file) [[ "$#" -ge 2 ]] || emit_usage_error "owner token file の値がありません"; TOKEN_FILE="$2"; TOKEN_FILE_SET=true; shift 2 ;;
      --engine) [[ "$#" -ge 2 ]] || emit_usage_error "--engine の値がありません"; ENGINE="$2"; shift 2 ;;
      --head-sha) [[ "$#" -ge 2 ]] || emit_usage_error "--head-sha の値がありません"; HEAD_SHA="$2"; shift 2 ;;
      --lease-id) [[ "$#" -ge 2 ]] || emit_usage_error "--lease-id の値がありません"; LEASE_ID="$2"; LEASE_ID_SET=true; shift 2 ;;
      --expected-lease-id) [[ "$#" -ge 2 ]] || emit_usage_error "--expected-lease-id の値がありません"; EXPECTED_LEASE_ID="$2"; EXPECTED_SET=true; shift 2 ;;
      --reason) [[ "$#" -ge 2 ]] || emit_usage_error "--reason の値がありません"; RELEASE_REASON="$2"; REASON_SET=true; shift 2 ;;
      --overdue-seconds|--ttl-seconds)
        [[ "$#" -ge 2 ]] || emit_usage_error "$1 の値がありません"
        [[ "$2" =~ ^[1-9][0-9]*$ ]] || emit_usage_error "overdue seconds は正整数でなければなりません"
        [[ "$OVERDUE_SET" == false || "$OVERDUE_SECONDS" == "$2" ]] || emit_usage_error "overdue seconds が重複しています"
        OVERDUE_SECONDS="$2"; OVERDUE_SET=true; shift 2 ;;
      --owner-session-id) [[ "$#" -ge 2 ]] || emit_usage_error "owner session id の値がありません"; OWNER_SESSION_ID="$2"; shift 2 ;;
      --owner-run-id) [[ "$#" -ge 2 ]] || emit_usage_error "owner run id の値がありません"; OWNER_RUN_ID="$2"; shift 2 ;;
      --host) [[ "$#" -ge 2 ]] || emit_usage_error "host の値がありません"; OWNER_HOST="$2"; shift 2 ;;
      --current-phase) [[ "$#" -ge 2 ]] || emit_usage_error "current phase の値がありません"; CURRENT_PHASE="$2"; CURRENT_PHASE_SET=true; shift 2 ;;
      --last-completed-phase) [[ "$#" -ge 2 ]] || emit_usage_error "last completed phase の値がありません"; LAST_COMPLETED_PHASE="$2"; LAST_COMPLETED_PHASE_SET=true; shift 2 ;;
      --phase-started-at) [[ "$#" -ge 2 ]] || emit_usage_error "phase started at の値がありません"; PHASE_STARTED_AT="$2"; PHASE_STARTED_AT_SET=true; shift 2 ;;
      --phase-budget) [[ "$#" -ge 2 ]] || emit_usage_error "phase budget の値がありません"; PHASE_BUDGET="$2"; PHASE_BUDGET_SET=true; shift 2 ;;
      --post-state) [[ "$#" -ge 2 ]] || emit_usage_error "post state の値がありません"; POST_STATE="$2"; POST_STATE_SET=true; shift 2 ;;
      --held-resources) [[ "$#" -ge 2 ]] || emit_usage_error "held resources の値がありません"; HELD_RESOURCES="$2"; shift 2 ;;
      --waiting-resources) [[ "$#" -ge 2 ]] || emit_usage_error "waiting resources の値がありません"; WAITING_RESOURCES="$2"; shift 2 ;;
      --artifact-path) [[ "$#" -ge 2 ]] || emit_usage_error "artifact path の値がありません"; ARTIFACT_PATH="$2"; shift 2 ;;
      --log-path) [[ "$#" -ge 2 ]] || emit_usage_error "log path の値がありません"; LOG_PATH="$2"; shift 2 ;;
      --renew) [[ "$OPERATION" == acquire ]] || emit_usage_error "--renew は acquire にだけ指定できます"; OPERATION=renew; shift ;;
      --force-release) [[ "$OPERATION" == release ]] || emit_usage_error "--force-release は release にだけ指定できます"; FORCE_RELEASE=true; shift ;;
      *) emit_usage_error "未知の引数です" ;;
    esac
  done
  [[ "$SCOPE_SET" == true && "$SCOPE" == per_pr ]] || emit_usage_error "--scope per_pr の指定が必須です"
  [[ "$KEY_SET" == true ]] || { [[ "$OPERATION" == sweep ]] || emit_usage_error "--key の指定が必須です"; }
  if [[ "$KEY_SET" == true ]]; then canonicalize_key "$CANONICAL_KEY" || emit_usage_error "canonical key が不正です"; fi
  if [[ "$OPERATION" == acquire ]]; then
    [[ "$TOKEN_FILE_SET" == true && "$TOKEN_FILE" == /* ]] || emit_usage_error "owner token file の指定が必須です"
    [[ -n "$ENGINE" && "$ENGINE" =~ ^(review-hard|magi-hard|codex-hard)$ ]] || emit_usage_error "engine が不正です"
    [[ "$OVERDUE_SET" == true ]] || emit_usage_error "--overdue-seconds の指定が必須です"
    [[ "$HEAD_SHA" == "" || "$HEAD_SHA" != *$'\n'* ]] || emit_usage_error "head sha が不正です"
  elif [[ "$OPERATION" == renew || "$OPERATION" == verify ]]; then
    [[ "$TOKEN_FILE_SET" == true && "$TOKEN_FILE" == /* ]] || emit_usage_error "owner token file の指定が必須です"
    [[ "$LEASE_ID_SET" == true && -n "$LEASE_ID" ]] || emit_usage_error "--lease-id の指定が必須です"
  elif [[ "$OPERATION" == release ]]; then
    if [[ "$FORCE_RELEASE" == true ]]; then
      [[ "$EXPECTED_SET" == true && -n "$EXPECTED_LEASE_ID" ]] || emit_usage_error "--expected-lease-id の指定が必須です"
      [[ "$REASON_SET" == true && -n "$RELEASE_REASON" ]] || emit_usage_error "--reason の指定が必須です"
    else
      [[ "$TOKEN_FILE_SET" == true && "$TOKEN_FILE" == /* ]] || emit_usage_error "owner token file の指定が必須です"
      [[ "$LEASE_ID_SET" == true && -n "$LEASE_ID" ]] || emit_usage_error "--lease-id の指定が必須です"
    fi
  fi
  [[ "$CURRENT_PHASE" != *$'\n'* && "$LAST_COMPLETED_PHASE" != *$'\n'* ]] || emit_usage_error "phase metadata が不正です"
  if [[ "$PHASE_STARTED_AT_SET" == true ]]; then
    [[ "$PHASE_STARTED_AT" =~ ^[0-9]+$ ]] || emit_usage_error "phase started at は整数でなければなりません"
  fi
  if [[ "$PHASE_BUDGET_SET" == true ]]; then
    [[ "$PHASE_BUDGET" =~ ^[0-9]+$ ]] || emit_usage_error "phase budget は非負整数でなければなりません"
  fi
  if [[ "$POST_STATE_SET" == true ]]; then
    [[ "$POST_STATE" =~ ^(not_started|in_progress|complete|unknown|post_failed|posted|not_applicable)$ ]] || emit_usage_error "post state が不正です"
  fi
}

acquire_lease() {
  local current_now="$1"
  if [[ "$METADATA_PRESENT" == true ]]; then
    metadata_is_valid "$current_now" || emit_error acquire 4 invalid_metadata "既存 lease metadata が不正です"
    local state=held holder
    metadata_is_stale "$current_now" && state=stale_suspected
    holder="$(safe_holder_json "$current_now" "$state")" || emit_error acquire 5 io_error "holder 診断を生成できません"
    jq -cn --arg state "$state" --arg scope "$SCOPE" --argjson holder "$holder" \
      '{operation:"acquire",state:$state,scope:$scope,holder:$holder}'
    exit 1
  fi
  read_token "$TOKEN_FILE" || emit_error acquire 4 token_missing "owner token file が不正か消失しています"
  jq -n -e --argjson held "$HELD_RESOURCES" --argjson waiting "$WAITING_RESOURCES" \
    '($held|type)=="array" and ($waiting|type)=="array"' >/dev/null 2>&1 \
    || emit_usage_error "resource metadata は JSON array でなければなりません"
  [[ "$POST_STATE" =~ ^(not_started|in_progress|complete|unknown)$ ]] || emit_usage_error "post state が不正です"
  [[ "$OWNER_SESSION_ID" != *$'\n'* && "$OWNER_RUN_ID" != *$'\n'* && "$OWNER_HOST" != *$'\n'* ]] || emit_usage_error "owner metadata が不正です"
  local lease_id
  lease_id="$(python3 -c 'import uuid; print(uuid.uuid4())' 2>/dev/null)" || emit_error acquire 5 io_error "lease id を生成できません"
  local phase_started_json=null phase_budget_json=null artifact_json=null log_json=null head_sha_json=null
  [[ -n "$PHASE_STARTED_AT" ]] && phase_started_json="$PHASE_STARTED_AT"
  [[ -n "$PHASE_BUDGET" ]] && phase_budget_json="$PHASE_BUDGET"
  [[ -n "$ARTIFACT_PATH" ]] && artifact_json="$(jq -cn --arg v "$ARTIFACT_PATH" '$v')"
  [[ -n "$LOG_PATH" ]] && log_json="$(jq -cn --arg v "$LOG_PATH" '$v')"
  [[ -n "$HEAD_SHA" ]] && head_sha_json="$(jq -cn --arg v "$HEAD_SHA" '$v')"
  METADATA_JSON="$(jq -cn --argjson schema_version 1 --arg scope "$SCOPE" --arg key_hash "$KEY_HASH" \
    --arg canonical_key "$CANONICAL_KEY" --arg forge_host "$KEY_FORGE_HOST" --arg owner "$KEY_OWNER" --arg repo "$KEY_REPO" \
    --argjson pr_number "$KEY_NUMBER" --arg lease_id "$lease_id" --arg token_fp "$TOKEN_FP" \
    --arg engine "$ENGINE" --argjson head_sha "$head_sha_json" --arg owner_session_id "$OWNER_SESSION_ID" \
    --arg owner_run_id "$OWNER_RUN_ID" --arg host "$OWNER_HOST" --argjson acquired_at "$current_now" \
    --argjson last_checkpoint_at "$current_now" --arg last_completed_phase "$LAST_COMPLETED_PHASE" --arg current_phase "$CURRENT_PHASE" \
    --argjson phase_started_at "$phase_started_json" --argjson phase_budget "$phase_budget_json" \
    --argjson planned_overdue_at "$OVERDUE_SECONDS" --arg post_state "$POST_STATE" --argjson held_resources "$HELD_RESOURCES" \
    --argjson waiting_resources "$WAITING_RESOURCES" --argjson artifact_path "$artifact_json" --argjson log_path "$log_json" \
    '{schema_version:$schema_version,scope:$scope,key_hash:$key_hash,canonical_key:$canonical_key,forge_host:$forge_host,
      owner:$owner,repo:$repo,pr_number:$pr_number,lease_id:$lease_id,token_fp:$token_fp,engine:$engine,
      head_sha:$head_sha,owner_session_id:$owner_session_id,owner_run_id:$owner_run_id,host:$host,acquired_at:$acquired_at,started_at:$acquired_at,
      last_checkpoint_at:$last_checkpoint_at,last_completed_phase:(if $last_completed_phase=="" then null else $last_completed_phase end),
      current_phase:(if $current_phase=="" then null else $current_phase end),phase_started_at:$phase_started_at,phase_budget:$phase_budget,
      planned_overdue_at:$planned_overdue_at,post_state:$post_state,held_resources:$held_resources,waiting_resources:$waiting_resources,
      artifact_path:$artifact_path,log_path:$log_path,run_artifact_path:$artifact_path,run_log_path:$log_path}')" || emit_error acquire 5 io_error "lease metadata を生成できません"
  atomic_write "$JSON_FILE" "$METADATA_JSON" || emit_error acquire 5 io_error "lease metadata の atomic rename に失敗しました"
  jq -cn --arg scope "$SCOPE" --arg lease_id "$lease_id" --arg token_fp "$TOKEN_FP" --argjson planned_overdue_at "$OVERDUE_SECONDS" \
    '{operation:"acquire",state:"acquired",scope:$scope,lease_id:$lease_id,token_fp:$token_fp,planned_overdue_at:$planned_overdue_at}'
  exit 0
}

renew_lease() {
  local current_now="$1"
  [[ "$METADATA_PRESENT" == true ]] || emit_error renew 3 not_owner "現在の per_pr lease がありません"
  metadata_is_valid "$current_now" || emit_error renew 4 invalid_metadata "既存 lease metadata が不正です"
  metadata_is_stale "$current_now" && emit_error renew 3 not_owner "lease は stale_suspected のため renew できません"
  read_token "$TOKEN_FILE" || emit_error renew 4 token_missing "owner token file が不正か消失しています"
  validate_token_against_metadata
  case "$?" in 3) emit_error renew 3 not_owner "owner token または lease_id が一致しません" ;; 4) emit_error renew 4 invalid_metadata "token fingerprint が metadata と一致しません" ;; esac
  [[ "$(jq -r '.lease_id' <<<"$METADATA_JSON")" == "$LEASE_ID" ]] || emit_error renew 3 not_owner "owner token または lease_id が一致しません"
  METADATA_JSON="$(jq --argjson now "$current_now" \
    --arg current_phase "$CURRENT_PHASE" --arg last_completed_phase "$LAST_COMPLETED_PHASE" \
    --arg phase_started_at "$PHASE_STARTED_AT" --arg phase_budget "$PHASE_BUDGET" --arg post_state "$POST_STATE" \
    --argjson current_phase_set "$CURRENT_PHASE_SET" --argjson last_completed_phase_set "$LAST_COMPLETED_PHASE_SET" \
    --argjson phase_started_at_set "$PHASE_STARTED_AT_SET" --argjson phase_budget_set "$PHASE_BUDGET_SET" \
    --argjson post_state_set "$POST_STATE_SET" '
      .last_checkpoint_at=$now
      | if $current_phase_set then .current_phase=(if $current_phase == "" then null else $current_phase end) else . end
      | if $last_completed_phase_set then .last_completed_phase=(if $last_completed_phase == "" then null else $last_completed_phase end) else . end
      | if $phase_started_at_set then .phase_started_at=($phase_started_at|tonumber) else . end
      | if $phase_budget_set then .phase_budget=($phase_budget|tonumber) else . end
      | if $post_state_set then .post_state=$post_state else . end
    ' <<<"$METADATA_JSON")" \
    || emit_error renew 5 io_error "lease checkpoint を生成できません"
  atomic_write "$JSON_FILE" "$METADATA_JSON" || emit_error renew 5 io_error "lease checkpoint の atomic rename に失敗しました"
  jq -cn --arg scope "$SCOPE" --arg lease_id "$LEASE_ID" --arg token_fp "$TOKEN_FP" --argjson checkpoint "$current_now" \
    --arg current_phase "$(jq -r '.current_phase // ""' <<<"$METADATA_JSON")" \
    --arg post_state "$(jq -r '.post_state' <<<"$METADATA_JSON")" \
    '{operation:"renew",state:"renewed",scope:$scope,lease_id:$lease_id,token_fp:$token_fp,last_checkpoint_at:$checkpoint,
      current_phase:(if $current_phase=="" then null else $current_phase end),post_state:$post_state}'
  exit 0
}

verify_lease() {
  local current_now="$1"
  [[ "$METADATA_PRESENT" == true ]] || emit_error verify 3 not_owner "現在の per_pr lease がありません"
  metadata_is_valid "$current_now" || emit_error verify 4 invalid_metadata "既存 lease metadata が不正です"
  metadata_is_stale "$current_now" && emit_error verify 3 not_owner "lease は stale_suspected です"
  read_token "$TOKEN_FILE" || emit_error verify 4 token_missing "owner token file が不正か消失しています"
  validate_token_against_metadata
  case "$?" in 3) emit_error verify 3 not_owner "owner token または lease_id が一致しません" ;; 4) emit_error verify 4 invalid_metadata "token fingerprint が metadata と一致しません" ;; esac
  [[ "$(jq -r '.lease_id' <<<"$METADATA_JSON")" == "$LEASE_ID" ]] || emit_error verify 3 not_owner "owner token または lease_id が一致しません"
  jq -cn --arg scope "$SCOPE" --arg lease_id "$LEASE_ID" --arg token_fp "$TOKEN_FP" \
    '{operation:"verify",state:"verified",scope:$scope,lease_id:$lease_id,token_fp:$token_fp}'
  exit 0
}

release_lease() {
  local current_now="$1"
  [[ "$METADATA_PRESENT" == true ]] || emit_error release 3 not_owner "現在の per_pr lease がありません"
  metadata_is_valid "$current_now" || emit_error release 4 invalid_metadata "既存 lease metadata が不正です"
  read_token "$TOKEN_FILE" || emit_error release 4 token_missing "owner token file が不正か消失しています"
  validate_token_against_metadata
  case "$?" in 3) emit_error release 3 not_owner "owner token または lease_id が一致しません" ;; 4) emit_error release 4 invalid_metadata "token fingerprint が metadata と一致しません" ;; esac
  [[ "$(jq -r '.lease_id' <<<"$METADATA_JSON")" == "$LEASE_ID" ]] || emit_error release 3 not_owner "owner token または lease_id が一致しません"
  rm -f -- "$JSON_FILE" || emit_error release 5 io_error "lease metadata を削除できません"
  jq -cn --arg scope "$SCOPE" --arg lease_id "$LEASE_ID" --arg token_fp "$TOKEN_FP" \
    '{operation:"release",state:"released",scope:$scope,lease_id:$lease_id,token_fp:$token_fp}'
  exit 0
}

force_release_lease() {
  local current_now="$1"
  [[ "$METADATA_PRESENT" == true ]] || emit_error release 3 not_owner "現在の per_pr lease がありません"
  metadata_is_valid "$current_now" || emit_error release 4 invalid_metadata "既存 lease metadata が不正です"
  local current_lease
  current_lease="$(jq -r '.lease_id' <<<"$METADATA_JSON")"
  [[ "$current_lease" == "$EXPECTED_LEASE_ID" ]] || emit_error release 3 cas_mismatch "expected lease_id が一致しません"
  local tombstone_dir="$SCOPE_DIR/tombstones" tombstone_id tombstone_path tombstone_json
  [[ ! -L "$tombstone_dir" ]] || emit_error release 5 io_error "tombstone directory が symlink です"
  (umask 077 && mkdir -p -- "$tombstone_dir") || emit_error release 5 io_error "tombstone directory を作成できません"
  chmod 700 -- "$tombstone_dir" 2>/dev/null || emit_error release 5 io_error "tombstone directory の権限を設定できません"
  tombstone_id="$(printf '%s' "$current_lease" | sha256sum | cut -c1-16)"
  tombstone_path="$tombstone_dir/${KEY_HASH}-${current_now}-${tombstone_id}.json"
  tombstone_json="$(jq -cn --arg scope "$SCOPE" --arg key_hash "$KEY_HASH" --arg canonical_key "$CANONICAL_KEY" \
    --arg lease_id "$current_lease" --arg reason "$RELEASE_REASON" --argjson released_at "$current_now" \
    --arg released_by_uid "$(id -u)" --arg released_by_host "$OWNER_HOST" --arg post_state "$(jq -r '.post_state' <<<"$METADATA_JSON")" \
    '{schema_version:1,kind:"singleflight-tombstone",scope:$scope,key_hash:$key_hash,canonical_key:$canonical_key,lease_id:$lease_id,
      released_at:$released_at,released_by:{uid:$released_by_uid,host:$released_by_host},reason:$reason,previous_post_state:$post_state}')" \
    || emit_error release 5 io_error "tombstone を生成できません"
  atomic_write "$tombstone_path" "$tombstone_json" || emit_error release 5 io_error "tombstone を保存できません"
  rm -f -- "$JSON_FILE" || emit_error release 5 io_error "force-release の lease 削除に失敗しました"
  local post_notice=""
  case "$(jq -r '.post_state' <<<"$METADATA_JSON")" in in_progress|unknown) post_notice="GitHub 既存コメントを確認せよ" ;; esac
  jq -cn --arg scope "$SCOPE" --arg lease_id "$current_lease" --arg tombstone "$tombstone_path" \
    --arg post_notice "$post_notice" '{operation:"release",state:"force_released",scope:$scope,lease_id:$lease_id,tombstone:$tombstone,
      notice:"解除は旧 owner を kill しない",post_notice:(if $post_notice=="" then null else $post_notice end)}'
  exit 0
}

status_lease() {
  local current_now="$1" state holder=null force_command post_notice=""
  if [[ "$METADATA_PRESENT" == false ]]; then
    jq -cn --arg scope "$SCOPE" --arg key "$CANONICAL_KEY" --arg key_hash "$KEY_HASH" \
      '{operation:"status",state:"unlocked",scope:$scope,canonical_key:$key,key_hash:$key_hash,holder:null}'
    exit 0
  fi
  metadata_is_valid "$current_now" || emit_error status 4 invalid_metadata "既存 lease metadata が不正です"
  state=held; metadata_is_stale "$current_now" && state=stale_suspected
  holder="$(safe_holder_json "$current_now" "$state")" || emit_error status 5 io_error "status 診断を生成できません"
  printf -v force_command '%q ' bash "$SELF_PATH" release --force-release --scope per_pr --key "$CANONICAL_KEY" \
    --expected-lease-id "$(jq -r '.lease_id' <<<"$METADATA_JSON")" --reason '人間が owner と GitHub 状態を確認した'
  [[ "$(jq -r '.post_state' <<<"$METADATA_JSON")" == in_progress || "$(jq -r '.post_state' <<<"$METADATA_JSON")" == unknown ]] \
    && post_notice="GitHub 既存コメントを確認せよ"
  jq -cn --arg scope "$SCOPE" --arg key "$CANONICAL_KEY" --arg key_hash "$KEY_HASH" --argjson holder "$holder" \
    --arg force_command "${force_command% }" --arg post_notice "$post_notice" \
    '{operation:"status",state:$holder.state,scope:$scope,canonical_key:$key,key_hash:$key_hash,holder:$holder,
      force_release_command:$force_command,notice:"解除は旧 owner を kill しない",post_notice:(if $post_notice=="" then null else $post_notice end)}'
  exit 0
}

close_sweep_mutex() {
  if [[ "$MUTEX_OPEN" == true ]]; then
    flock -u 9 2>/dev/null || true
    exec 9>&- 2>/dev/null || true
    MUTEX_OPEN=false
  fi
}

sweep_leases() {
  local current_now
  current_now="$(now_seconds)" || emit_error sweep 5 io_error "時刻を取得できません"
  local -a stale_items=()
  local skipped_invalid=0 path base hash raw item expected_hash metadata_hash
  local -a broken_items=()
  shopt -s nullglob
  for path in "$SCOPE_DIR"/*.json; do
    [[ -L "$path" ]] && { skipped_invalid=$((skipped_invalid+1)); continue; }
    [[ -f "$path" ]] || continue
    base="$(basename -- "$path")"; hash="${base%.json}"
    [[ "$hash" =~ ^[0-9a-f]{64}$ ]] || { skipped_invalid=$((skipped_invalid+1)); continue; }
    KEY_HASH="$hash"; JSON_FILE="$path"; MUTEX_FILE="$SCOPE_DIR/$hash.mutex"
    if ! open_mutex; then skipped_invalid=$((skipped_invalid+1)); continue; fi
    raw="$(strict_json_file "$path")"
    if [[ $? -ne 0 ]]; then close_sweep_mutex; skipped_invalid=$((skipped_invalid+1)); continue; fi
    METADATA_JSON="$raw"; SCOPE=per_pr
    if ! jq -e --arg hash "$hash" --argjson now "$current_now" '
      type=="object" and .schema_version==1 and .scope=="per_pr"
      and (.canonical_key|type=="string" and length>0) and (.lease_id|type=="string" and length>0)
      and (.token_fp|type=="string" and test("^[0-9a-f]{8}$"))
      and (.acquired_at|type=="number" and floor==. and .>=0 and .<=$now)
      and (.last_checkpoint_at as $last | .acquired_at as $acquired
           | ($last | type=="number" and floor==. and . >= $acquired and . <= $now))
      and (.planned_overdue_at|type=="number" and floor==. and .>0)
    ' <<<"$METADATA_JSON" >/dev/null 2>&1; then close_sweep_mutex; skipped_invalid=$((skipped_invalid+1)); continue; fi
    canonicalize_key "$(jq -r '.canonical_key' <<<"$METADATA_JSON")" || { close_sweep_mutex; skipped_invalid=$((skipped_invalid+1)); continue; }
    expected_hash="$(key_hash_for)"
    metadata_hash="$(jq -r '.key_hash // empty' <<<"$METADATA_JSON")"
    if [[ "$expected_hash" != "$hash" || "$metadata_hash" != "$expected_hash" ]]; then
      broken_items+=("$(jq -cn --arg path "$path" --arg file_hash "$hash" --arg metadata_key_hash "$metadata_hash" --arg expected_key_hash "$expected_hash" \
        '{path:$path,reason:"key_hash_mismatch",file_hash:$file_hash,metadata_key_hash:$metadata_key_hash,expected_key_hash:$expected_key_hash}')")
      close_sweep_mutex
      continue
    fi
    KEY_HASH="$expected_hash"
    if ! metadata_is_valid "$current_now"; then close_sweep_mutex; skipped_invalid=$((skipped_invalid+1)); continue; fi
    if metadata_is_stale "$current_now"; then item="$(safe_holder_json "$current_now" stale_suspected)"; stale_items+=("$item"); fi
    close_sweep_mutex
  done
  local stale_json='[]' broken_json='[]'
  for item in "${stale_items[@]}"; do stale_json="$(jq -c --argjson item "$item" '. + [$item]' <<<"$stale_json")"; done
  for item in "${broken_items[@]}"; do broken_json="$(jq -c --argjson item "$item" '. + [$item]' <<<"$broken_json")"; done
  jq -cn --argjson stale_suspected "$stale_json" --argjson broken_leases "$broken_json" --argjson skipped_invalid "$skipped_invalid" \
    '{operation:"sweep",state:"done",scope:"per_pr",stale_suspected:$stale_suspected,reclaimed:0,skipped_invalid:$skipped_invalid,
      broken_leases:$broken_leases,notice:"stale_suspected は列挙のみで削除しない。壊れた lease は削除しない"}'
  exit 0
}

main() {
  command -v jq >/dev/null 2>&1 || emit_error "${1:-unknown}" 5 io_error "jq が必要です"
  command -v flock >/dev/null 2>&1 || emit_error "${1:-unknown}" 5 io_error "flock が必要です"
  parse_args "$@"
  prepare_lock_root || emit_error "$OPERATION" 5 io_error "lock root が local FS ではないか、所有者・権限・I/O が不正です"
  if [[ "$OPERATION" == sweep ]]; then sweep_leases; fi
  KEY_HASH="$(key_hash_for)" || emit_error "$OPERATION" 5 io_error "key hash を計算できません"
  JSON_FILE="$SCOPE_DIR/$KEY_HASH.json"
  if [[ "$FORCE_RELEASE" == true ]]; then open_post_lock || emit_error "$OPERATION" 5 io_error "post lock を取得できません"; fi
  open_mutex || emit_error "$OPERATION" 5 io_error "mutex lock を取得できません"
  local current_now
  current_now="$(now_seconds)" || emit_error "$OPERATION" 5 io_error "時刻を取得できません"
  read_metadata
  case "$?" in 4) emit_error "$OPERATION" 4 invalid_metadata "lease JSON が壊れているか、必須キーが欠落しています" ;; 5) emit_error "$OPERATION" 5 io_error "lease JSON の symlink・権限・I/O が不正です" ;; esac
  case "$OPERATION" in
    acquire) acquire_lease "$current_now" ;;
    renew) renew_lease "$current_now" ;;
    verify) verify_lease "$current_now" ;;
    release) [[ "$FORCE_RELEASE" == true ]] && force_release_lease "$current_now" || release_lease "$current_now" ;;
    status) status_lease "$current_now" ;;
  esac
}

main "$@"
