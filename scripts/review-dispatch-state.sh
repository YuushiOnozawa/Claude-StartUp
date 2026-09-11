#!/usr/bin/env bash
# scripts/review-dispatch-state.sh — handoff 後の dispatch state/envelope/cleanup 操作
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_ENVELOPE_HELPER="$SCRIPT_DIR/review-dispatch-envelope.sh"

usage() {
  cat >&2 <<'EOF'
usage:
  review-dispatch-state.sh set --dispatch-state PATH --filter JQ_FILTER [--arg NAME VALUE] [--argjson NAME JSON] ...
  review-dispatch-state.sh write-envelope --dispatch-state PATH --dispatch-tmpdir PATH \
    --sf-helper PATH --envelope-helper PATH --canonical-key KEY --backend magi|codex \
    --status STATUS --post-state POST_STATE --reason REASON
  review-dispatch-state.sh cleanup --dispatch-state PATH --dispatch-tmpdir PATH \
    --sf-helper PATH --canonical-key KEY --owner-token-file PATH --lease-id LEASE_ID
EOF
  exit 2
}

die() {
  echo "review-dispatch-state: $1" >&2
  exit 2
}

require_absolute_path() {
  local name="$1" value="$2"
  [[ "$value" == /* ]] || die "$name は絶対パスでなければなりません"
}

require_file() {
  local name="$1" value="$2"
  [[ -r "$value" && ! -L "$value" ]] || die "$name を読み取れません: $value"
}

set_state() {
  local dispatch_state="" filter=""
  local -a jq_args=()

  while (($#)); do
    case "$1" in
      --dispatch-state)
        [[ $# -ge 2 ]] || usage
        dispatch_state="$2"
        shift 2
        ;;
      --filter)
        [[ $# -ge 2 ]] || usage
        filter="$2"
        shift 2
        ;;
      --arg|--argjson)
        [[ $# -ge 3 ]] || usage
        jq_args+=("$1" "$2" "$3")
        shift 3
        ;;
      *)
        usage
        ;;
    esac
  done

  [[ -n "$dispatch_state" && -n "$filter" ]] || usage
  require_absolute_path dispatch-state "$dispatch_state"
  require_file dispatch-state "$dispatch_state"
  local state_tmp="${dispatch_state}.tmp.$$"
  ( umask 077 && jq "${jq_args[@]}" "$filter" "$dispatch_state" > "$state_tmp" && mv -f -- "$state_tmp" "$dispatch_state" ) \
    || { rm -f -- "$state_tmp"; die "dispatch-state.json の更新に失敗しました"; }
}

write_envelope() {
  local dispatch_state="" dispatch_tmpdir="" sf_helper="" envelope_helper="$DEFAULT_ENVELOPE_HELPER"
  local canonical_key="" backend="" status="" post_state="" reason=""

  while (($#)); do
    case "$1" in
      --dispatch-state|--dispatch-tmpdir|--sf-helper|--envelope-helper|--canonical-key|--backend|--status|--post-state|--reason)
        [[ $# -ge 2 ]] || usage
        case "$1" in
          --dispatch-state) dispatch_state="$2" ;;
          --dispatch-tmpdir) dispatch_tmpdir="$2" ;;
          --sf-helper) sf_helper="$2" ;;
          --envelope-helper) envelope_helper="$2" ;;
          --canonical-key) canonical_key="$2" ;;
          --backend) backend="$2" ;;
          --status) status="$2" ;;
          --post-state) post_state="$2" ;;
          --reason) reason="$2" ;;
        esac
        shift 2
        ;;
      *)
        usage
        ;;
    esac
  done

  [[ -n "$dispatch_state" && -n "$dispatch_tmpdir" && -n "$sf_helper" && -n "$envelope_helper" \
    && -n "$canonical_key" && -n "$backend" && -n "$status" && -n "$post_state" && -n "$reason" ]] || usage
  require_absolute_path dispatch-state "$dispatch_state"
  require_file dispatch-state "$dispatch_state"
  require_absolute_path dispatch-tmpdir "$dispatch_tmpdir"
  require_absolute_path sf-helper "$sf_helper"
  require_absolute_path envelope-helper "$envelope_helper"
  [[ "$backend" == magi || "$backend" == codex ]] || die "backend が不正です"
  [[ "$status" == failed || "$status" == unavailable ]] || die "envelope status が不正です"
  [[ "$post_state" == posted || "$post_state" == post_failed || "$post_state" == not_applicable ]] \
    || die "post_state が不正です"
  [[ -d "$dispatch_tmpdir" && ! -L "$dispatch_tmpdir" ]] || die "dispatch tmpdir を利用できません"
  require_file envelope-helper "$envelope_helper"

  local output="$dispatch_tmpdir/review-dispatch-result.json"
  local output_tmp="${output}.tmp.$$"
  if ! ( umask 077
    jq -n --arg backend "$backend" --arg status "$status" --arg post_state "$post_state" --arg reason "$reason" \
      '{schema_version:"1",artifact_type:"review-dispatch-result",review_kind:"hard",backend:$backend,dispatch_status:$status,gate_decision:"indeterminate",lgtm_eligible:false,blocking_count:null,manual_review_required:true,manual_review:null,artifact_ref:null,adjudication_ref:null,post_state:$post_state,failure_reason:$reason,native_result:{}}' \
      > "$output_tmp"
    if ! jq -e '((keys|sort) == (["schema_version","artifact_type","review_kind","backend","dispatch_status","gate_decision","lgtm_eligible","blocking_count","manual_review_required","manual_review","artifact_ref","adjudication_ref","post_state","failure_reason","native_result"]|sort))' "$output_tmp" >/dev/null \
      || ! bash "$envelope_helper" validate "$output_tmp" >/dev/null; then
      jq -n --arg backend "$backend" --arg reason "dispatch envelope builder/validator failed: $reason" \
        '{schema_version:"1",artifact_type:"review-dispatch-result",review_kind:"hard",backend:$backend,dispatch_status:"failed",gate_decision:"indeterminate",lgtm_eligible:false,blocking_count:null,manual_review_required:true,manual_review:null,artifact_ref:null,adjudication_ref:null,post_state:"posted",failure_reason:$reason,native_result:{}}' \
        > "$output_tmp"
      bash "$envelope_helper" validate "$output_tmp" >/dev/null
    fi
    mv -f -- "$output_tmp" "$output"
  ); then
    rm -f -- "$output_tmp"
    die "dispatch envelope の生成または検証に失敗しました"
  fi
  printf 'review-dispatch result: %s\n' "$(realpath -m -- "$output")"
}

cleanup_dispatch() {
  local dispatch_state="" dispatch_tmpdir="" sf_helper="" canonical_key="" owner_token_file="" lease_id=""

  while (($#)); do
    case "$1" in
      --dispatch-state|--dispatch-tmpdir|--sf-helper|--canonical-key|--owner-token-file|--lease-id)
        [[ $# -ge 2 ]] || usage
        case "$1" in
          --dispatch-state) dispatch_state="$2" ;;
          --dispatch-tmpdir) dispatch_tmpdir="$2" ;;
          --sf-helper) sf_helper="$2" ;;
          --canonical-key) canonical_key="$2" ;;
          --owner-token-file) owner_token_file="$2" ;;
          --lease-id) lease_id="$2" ;;
        esac
        shift 2
        ;;
      *)
        usage
        ;;
    esac
  done

  [[ -n "$dispatch_state" && -n "$dispatch_tmpdir" && -n "$sf_helper" && -n "$canonical_key" \
    && -n "$owner_token_file" && -n "$lease_id" ]] || usage
  require_absolute_path dispatch-state "$dispatch_state"
  require_absolute_path dispatch-tmpdir "$dispatch_tmpdir"
  require_absolute_path sf-helper "$sf_helper"
  require_absolute_path owner-token-file "$owner_token_file"
  require_file dispatch-state "$dispatch_state"
  require_file sf-helper "$sf_helper"
  require_file owner-token-file "$owner_token_file"
  [[ -d "$dispatch_tmpdir" && ! -L "$dispatch_tmpdir" ]] || die "dispatch tmpdir を利用できません"

  local rc
  rc="$(jq -r '.saved_rc // 0' "$dispatch_state" 2>/dev/null || printf '%s' 5)"
  [[ "$rc" =~ ^[0-9]+$ ]] || rc=5
  local release_rc=0
  if [[ "$(jq -r '.per_pr.acquired // false' "$dispatch_state" 2>/dev/null || printf '%s' false)" == true ]]; then
    timeout 10 bash "$sf_helper" release --scope per_pr --key "$canonical_key" \
      --owner-token-file "$owner_token_file" --lease-id "$lease_id" \
      >"$dispatch_tmpdir/release.json" 2>"$dispatch_tmpdir/release.err" || release_rc=$?
    if [[ "$release_rc" -eq 0 ]]; then
      set_state --dispatch-state "$dispatch_state" --filter '.per_pr.acquired=false | .phase="cleaned"'
    else
      echo "review-dispatch: per_pr lease の release に失敗。stale_suspected として残存。手動 --force-release が必要" >&2
      rc=5
      set_state --dispatch-state "$dispatch_state" --filter '.saved_rc=$rc | .phase="cleanup_failed"' --argjson rc "$rc" || true
    fi
  fi
  return "$rc"
}

[[ $# -ge 1 ]] || usage
case "$1" in
  set)
    shift
    set_state "$@"
    ;;
  write-envelope)
    shift
    write_envelope "$@"
    ;;
  cleanup)
    shift
    cleanup_dispatch "$@"
    ;;
  *)
    usage
    ;;
esac
