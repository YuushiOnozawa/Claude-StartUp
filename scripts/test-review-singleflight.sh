#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPER="$REPO_ROOT/scripts/review-singleflight.sh"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT
PASS=0
FAIL=0

record_result() {
  if [[ "$2" -eq 0 ]]; then echo "PASS: $1"; ((PASS++)) || true; else echo "FAIL: $1"; ((FAIL++)) || true; fi
}
run_sf() {
  REVIEW_SINGLEFLIGHT_TEST_MODE=1 REVIEW_SINGLEFLIGHT_NOW="${TEST_NOW:-100}" XDG_RUNTIME_DIR="$TEST_ROOT/runtime" \
    bash "$HELPER" "$@"
}
new_token() {
  local path="$1"
  (umask 077; printf '%s\n' "token-$(basename -- "$path")-secure" >"$path")
  chmod 600 -- "$path"
}

mkdir -p "$TEST_ROOT/runtime"
KEY=$'github.com\nowner/repo\n7'
new_token "$TEST_ROOT/token-one"
new_token "$TEST_ROOT/token-two"
set +e
BAD_SCOPE_OUT="$(run_sf status --scope broker --key "$KEY" 2>/dev/null)"
BAD_SCOPE_RC=$?
set -e
if [[ "$BAD_SCOPE_RC" -eq 2 && "$BAD_SCOPE_OUT" == *contract_violation* ]]; then result=0; else result=1; fi
record_result "helper は per_pr 以外の scope を受け付けない" "$result"
set +e
ACQUIRE_OUT="$(run_sf acquire --scope per_pr --key "$KEY" --owner-token-file "$TEST_ROOT/token-one" \
  --engine magi-hard --head-sha abc123 --overdue-seconds 10 --post-state in_progress \
  --owner-session-id session-1 --owner-run-id run-1 2>"$TEST_ROOT/acquire.err")"
ACQUIRE_RC=$?
set -e
LEASE_ID="$(jq -r '.lease_id' <<<"$ACQUIRE_OUT")"
KEY_HASH="$(printf 'per_pr\0%s' "$KEY" | sha256sum | cut -d' ' -f1)"
MUTEX_PATH="$TEST_ROOT/runtime/claude-review-sf/per_pr/$KEY_HASH.mutex"
MUTEX_INODE="$(stat -c '%i' "$MUTEX_PATH")"
if [[ "$ACQUIRE_RC" -eq 0 && "$ACQUIRE_OUT" == *'"state":"acquired"'* && -n "$LEASE_ID" ]]; then result=0; else result=1; fi
record_result "per_pr acquire が lease_id を発行する" "$result"
if ! grep -Fq 'token-one-secure' <<<"$ACQUIRE_OUT" && ! grep -Fq 'token-one-secure' "$TEST_ROOT/acquire.err"; then result=0; else result=1; fi
record_result "acquire 出力に owner_token を漏らさない" "$result"
LEASE_JSON="$TEST_ROOT/runtime/claude-review-sf/per_pr/$(printf 'per_pr\0%s' "$KEY" | sha256sum | cut -d' ' -f1).json"
if ! grep -Fq 'token-one-secure' "$LEASE_JSON"; then result=0; else result=1; fi
record_result "lease metadata JSON に raw owner_token を保存しない" "$result"

set +e
HELD_OUT="$(run_sf acquire --scope per_pr --key "$KEY" --owner-token-file "$TEST_ROOT/token-two" --engine codex-hard --overdue-seconds 20 2>"$TEST_ROOT/held.err")"
HELD_RC=$?
set -e
if [[ "$HELD_RC" -eq 1 && "$HELD_OUT" == *'"state":"held"'* && "$HELD_OUT" == *'token_fp'* ]]; then result=0; else result=1; fi
record_result "2本目の acquire は held / exit 1 になる" "$result"
if ! grep -Fq 'token-two-secure' <<<"$HELD_OUT" && ! grep -Fq 'token-two-secure' "$TEST_ROOT/held.err"; then result=0; else result=1; fi
record_result "held 診断に owner_token を漏らさない" "$result"

STATUS_OUT="$(run_sf status --scope per_pr --key "$KEY")"
if jq -e '.state == "held" and .holder.head_sha == "abc123" and .holder.post_state == "in_progress" and .post_notice == "GitHub 既存コメントを確認せよ" and .holder.current_phase == null and (.force_release_command | contains("--force-release")) and (.holder.held_resources | type == "array")' <<<"$STATUS_OUT" >/dev/null; then result=0; else result=1; fi
record_result "status が holder / head_sha / phase / resource / force-release 手順を出す" "$result"
if ! grep -Fq 'token-one-secure' <<<"$STATUS_OUT"; then result=0; else result=1; fi
record_result "status JSON に owner_token を漏らさない" "$result"
VERIFY_OUT="$(run_sf verify --scope per_pr --key "$KEY" --owner-token-file "$TEST_ROOT/token-one" --lease-id "$LEASE_ID")"
if jq -e '.state == "verified" and .lease_id == $id' --arg id "$LEASE_ID" <<<"$VERIFY_OUT" >/dev/null; then result=0; else result=1; fi
record_result "owner token と lease_id の一致を verify できる" "$result"

TEST_NOW=101
RENEW_OUT="$(run_sf renew --scope per_pr --key "$KEY" --owner-token-file "$TEST_ROOT/token-one" --lease-id "$LEASE_ID")"
if jq -e '.state == "renewed" and .last_checkpoint_at == 101' <<<"$RENEW_OUT" >/dev/null; then result=0; else result=1; fi
record_result "renew は last_checkpoint_at だけを更新する" "$result"
TEST_NOW=102
RENEW_PHASE_OUT="$(run_sf renew --scope per_pr --key "$KEY" --owner-token-file "$TEST_ROOT/token-one" --lease-id "$LEASE_ID" \
  --current-phase persona-MELCHIOR --last-completed-phase phase-0 --phase-started-at 102 --phase-budget 30 --post-state in_progress)"
if jq -e '.state == "renewed" and .current_phase == "persona-MELCHIOR" and .post_state == "in_progress"' <<<"$RENEW_PHASE_OUT" >/dev/null \
  && jq -e '.current_phase == "persona-MELCHIOR" and .last_completed_phase == "phase-0" and .phase_started_at == 102 and .phase_budget == 30 and .post_state == "in_progress"' "$LEASE_JSON" >/dev/null; then result=0; else result=1; fi
record_result "renew が phase/post state を metadata に反映する" "$result"
if [[ -f "$MUTEX_PATH" && "$(stat -c '%i' "$MUTEX_PATH")" == "$MUTEX_INODE" ]]; then result=0; else result=1; fi
record_result ".mutex は lease 更新後も同じ inode を保持する" "$result"
set +e
WRONG_VERIFY="$(run_sf verify --scope per_pr --key "$KEY" --owner-token-file "$TEST_ROOT/token-two" --lease-id "$LEASE_ID" 2>/dev/null)"
WRONG_VERIFY_RC=$?
set -e
if [[ "$WRONG_VERIFY_RC" -eq 3 && "$WRONG_VERIFY" != *'token-two-secure'* ]]; then result=0; else result=1; fi
record_result "不正 owner は verify exit 3 で停止する" "$result"

TEST_NOW=200
STALE_OUT="$(run_sf status --scope per_pr --key "$KEY")"
STALE_HASH="$(jq -r .key_hash <<<"$STALE_OUT")"
if jq -e '.state == "stale_suspected" and .holder.overdue_seconds > 0' <<<"$STALE_OUT" >/dev/null \
  && [[ -f "$TEST_ROOT/runtime/claude-review-sf/per_pr/$STALE_HASH.json" ]]; then result=0; else result=1; fi
record_result "TTL 超過は stale_suspected と表示し lease を削除しない" "$result"
set +e
STALE_ACQUIRE="$(run_sf acquire --scope per_pr --key "$KEY" --owner-token-file "$TEST_ROOT/token-two" --engine codex-hard --overdue-seconds 10 2>/dev/null)"
STALE_ACQUIRE_RC=$?
set -e
if [[ "$STALE_ACQUIRE_RC" -eq 1 && "$STALE_ACQUIRE" == *'"state":"stale_suspected"'* ]]; then result=0; else result=1; fi
record_result "stale_suspected の acquire は takeover せず exit 1 にする" "$result"
SWEEP_OUT="$(run_sf sweep --scope per_pr)"
if jq -e '.reclaimed == 0 and (.stale_suspected | length) >= 1 and (.notice | contains("削除しない"))' <<<"$SWEEP_OUT" >/dev/null \
  && [[ -f "$TEST_ROOT/runtime/claude-review-sf/per_pr/$STALE_HASH.json" ]]; then result=0; else result=1; fi
record_result "sweep は stale_suspected を列挙するだけで削除しない" "$result"

BROKEN_KEY=$'github.com\nowner/broken\n13'
new_token "$TEST_ROOT/token-broken"
run_sf acquire --scope per_pr --key "$BROKEN_KEY" --owner-token-file "$TEST_ROOT/token-broken" --engine magi-hard --overdue-seconds 100 >/dev/null
BROKEN_HASH="$(printf 'per_pr\0%s' "$BROKEN_KEY" | sha256sum | cut -d' ' -f1)"
BROKEN_JSON="$TEST_ROOT/runtime/claude-review-sf/per_pr/$BROKEN_HASH.json"
BROKEN_OTHER_KEY=$'github.com\nowner/other\n13'
jq --arg key "$BROKEN_OTHER_KEY" '.canonical_key=$key' "$BROKEN_JSON" >"$BROKEN_JSON.next" && mv -- "$BROKEN_JSON.next" "$BROKEN_JSON" && chmod 600 -- "$BROKEN_JSON"
BROKEN_SWEEP_OUT="$(run_sf sweep --scope per_pr)"
if jq -e --arg path "$BROKEN_JSON" '(.broken_leases | map(select(.path == $path and .reason == "key_hash_mismatch")) | length) == 1' <<<"$BROKEN_SWEEP_OUT" >/dev/null \
  && [[ -f "$BROKEN_JSON" ]]; then result=0; else result=1; fi
record_result "sweep は canonical key から key_hash を再計算し不整合を列挙する" "$result"

META_HASH_KEY=$'github.com\nowner/metahash\n14'
new_token "$TEST_ROOT/token-metahash"
run_sf acquire --scope per_pr --key "$META_HASH_KEY" --owner-token-file "$TEST_ROOT/token-metahash" --engine magi-hard --overdue-seconds 100 >/dev/null
META_HASH="$(printf 'per_pr\0%s' "$META_HASH_KEY" | sha256sum | cut -d' ' -f1)"
META_HASH_JSON="$TEST_ROOT/runtime/claude-review-sf/per_pr/$META_HASH.json"
jq '.key_hash = ("0" * 64)' "$META_HASH_JSON" >"$META_HASH_JSON.next" && mv -- "$META_HASH_JSON.next" "$META_HASH_JSON" && chmod 600 -- "$META_HASH_JSON"
META_SWEEP_OUT="$(run_sf sweep --scope per_pr)"
if jq -e --arg path "$META_HASH_JSON" '(.broken_leases | map(select(.path == $path and .reason == "key_hash_mismatch")) | length) == 1' <<<"$META_SWEEP_OUT" >/dev/null; then result=0; else result=1; fi
record_result "sweep は metadata key_hash の不整合も壊れた lease として列挙する" "$result"

set +e
NO_REASON_OUT="$(run_sf release --force-release --scope per_pr --key "$KEY" --expected-lease-id "$LEASE_ID" 2>/dev/null)"
NO_REASON_RC=$?
set -e
if [[ "$NO_REASON_RC" -eq 2 && "$NO_REASON_OUT" == *contract_violation* ]]; then result=0; else result=1; fi
record_result "force-release は --reason を必須にする" "$result"
set +e
CAS_OUT="$(run_sf release --force-release --scope per_pr --key "$KEY" --expected-lease-id wrong --reason cleanup 2>/dev/null)"
CAS_RC=$?
set -e
if [[ "$CAS_RC" -eq 3 && "$CAS_OUT" == *cas_mismatch* ]]; then result=0; else result=1; fi
record_result "force-release は expected lease_id の CAS を守る" "$result"
POST_HASH="$(printf '%s\0%s/%s\0%s' github.com owner repo 7 | sha256sum | cut -d' ' -f1)"
POST_LOCK="$TEST_ROOT/runtime/claude-review-post-owner-repo-7-$POST_HASH.lock"
exec 8>"$POST_LOCK"
flock -x 8
FORCE_OUT_FILE="$TEST_ROOT/force-release.out"
FORCE_RC_FILE="$TEST_ROOT/force-release.rc"
(
  set +e
  exec 8>&-
  REVIEW_SINGLEFLIGHT_TEST_MODE=1 REVIEW_SINGLEFLIGHT_NOW=200 REVIEW_SINGLEFLIGHT_POST_LOCK_WAIT_SECONDS=1 XDG_RUNTIME_DIR="$TEST_ROOT/runtime" \
    bash "$HELPER" release --force-release --scope per_pr --key "$KEY" --expected-lease-id "$LEASE_ID" --reason '確認済み stale lease' \
    >"$FORCE_OUT_FILE" 2>"$TEST_ROOT/force-release.err"
  echo "$?" >"$FORCE_RC_FILE"
) &
FORCE_PID=$!
sleep 0.2
if [[ ! -e "$FORCE_RC_FILE" ]]; then result=0; else result=1; fi
record_result "force-release は進行中 post lock の終了を待つ" "$result"
exec 8>&-
wait "$FORCE_PID"
FORCE_OUT="$(<"$FORCE_OUT_FILE")"
FORCE_RC="$(<"$FORCE_RC_FILE")"
if [[ "$FORCE_RC" -eq 0 ]] \
  && jq -e '.state == "force_released" and (.notice | contains("kill")) and .post_notice == "GitHub 既存コメントを確認せよ" and (.tombstone | type == "string")' <<<"$FORCE_OUT" >/dev/null \
  && [[ ! -f "$TEST_ROOT/runtime/claude-review-sf/per_pr/$STALE_HASH.json" ]] \
  && [[ -n "$(find "$TEST_ROOT/runtime/claude-review-sf/per_pr/tombstones" -name '*.json' -print -quit)" ]]; then result=0; else result=1; fi
record_result "force-release が post lock 後に tombstone を残して解除する" "$result"

CONCURRENT_KEY=$'github.com\nowner/concurrent\n9'
for n in $(seq 1 8); do
  new_token "$TEST_ROOT/concurrent-token-$n"
  (set +e; run_sf acquire --scope per_pr --key "$CONCURRENT_KEY" --owner-token-file "$TEST_ROOT/concurrent-token-$n" \
    --engine codex-hard --overdue-seconds 100 >"$TEST_ROOT/concurrent.$n.out" 2>/dev/null; echo $? >"$TEST_ROOT/concurrent.$n.rc") &
done
wait
SUCCESS_COUNT=0
for n in $(seq 1 8); do [[ "$(<"$TEST_ROOT/concurrent.$n.rc")" -eq 0 ]] && SUCCESS_COUNT=$((SUCCESS_COUNT+1)); done
if [[ "$SUCCESS_COUNT" -eq 1 ]]; then result=0; else result=1; fi
record_result "並行 acquire は1本だけ成功する" "$result"

BAD_KEY=$'github.com\nowner/bad\n11'
new_token "$TEST_ROOT/token-bad"
run_sf acquire --scope per_pr --key "$BAD_KEY" --owner-token-file "$TEST_ROOT/token-bad" --engine magi-hard --overdue-seconds 100 >/dev/null
BAD_HASH="$(printf 'per_pr\0%s' "$BAD_KEY" | sha256sum | cut -d' ' -f1)"
BAD_JSON="$TEST_ROOT/runtime/claude-review-sf/per_pr/$BAD_HASH.json"
jq '.last_checkpoint_at=9999999999' "$BAD_JSON" >"$BAD_JSON.next" && mv -- "$BAD_JSON.next" "$BAD_JSON" && chmod 600 -- "$BAD_JSON"
set +e
FUTURE_OUT="$(run_sf status --scope per_pr --key "$BAD_KEY" 2>/dev/null)"
FUTURE_RC=$?
set -e
if [[ "$FUTURE_RC" -eq 4 && "$FUTURE_OUT" == *invalid_metadata* ]]; then result=0; else result=1; fi
record_result "future timestamp は fail-closed exit 4 になる" "$result"
mv -- "$BAD_JSON" "$BAD_JSON.real"
ln -s -- "$BAD_JSON.real" "$BAD_JSON"
set +e
SYMLINK_OUT="$(run_sf status --scope per_pr --key "$BAD_KEY" 2>/dev/null)"
SYMLINK_RC=$?
set -e
if [[ "$SYMLINK_RC" -eq 5 && "$SYMLINK_OUT" == *io_error* ]]; then result=0; else result=1; fi
record_result "lease JSON symlink は fail-closed exit 5 になる" "$result"
set +e
FS_OUT="$(REVIEW_SINGLEFLIGHT_TEST_MODE=1 REVIEW_SINGLEFLIGHT_FS_TYPE=nfs XDG_RUNTIME_DIR="$TEST_ROOT/runtime" \
  bash "$HELPER" status --scope per_pr --key "$BAD_KEY" 2>/dev/null)"
FS_RC=$?
set -e
if [[ "$FS_RC" -eq 5 && "$FS_OUT" == *io_error* ]]; then result=0; else result=1; fi
record_result "network FS 模擬は暗黙 fallback せず exit 5 になる" "$result"

MISSING_KEY=$'github.com\nowner/missing\n12'
new_token "$TEST_ROOT/token-missing"
run_sf acquire --scope per_pr --key "$MISSING_KEY" --owner-token-file "$TEST_ROOT/token-missing" --engine magi-hard --overdue-seconds 100 >/dev/null
MISSING_HASH="$(printf 'per_pr\0%s' "$MISSING_KEY" | sha256sum | cut -d' ' -f1)"
MISSING_JSON="$TEST_ROOT/runtime/claude-review-sf/per_pr/$MISSING_HASH.json"
jq 'del(.post_state)' "$MISSING_JSON" >"$MISSING_JSON.next" && mv -- "$MISSING_JSON.next" "$MISSING_JSON" && chmod 600 -- "$MISSING_JSON"
set +e
MISSING_OUT="$(run_sf status --scope per_pr --key "$MISSING_KEY" 2>/dev/null)"
MISSING_RC=$?
set -e
if [[ "$MISSING_RC" -eq 4 && "$MISSING_OUT" == *invalid_metadata* ]]; then result=0; else result=1; fi
record_result "必須キー欠落の lease JSON は fail-closed exit 4 になる" "$result"

if bash -n "$HELPER" && bash -n "$REPO_ROOT/scripts/check-review-fast-no-post.sh"; then result=0; else result=1; fi
record_result "single-flight helper と fast detector の構文が正しい" "$result"

echo ""
echo "=== 結果: PASS=$PASS FAIL=$FAIL ==="
[[ "$FAIL" -eq 0 ]]
