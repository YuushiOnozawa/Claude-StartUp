#!/usr/bin/env bash
# handoff 後の state/envelope/cleanup が Bash プロセスをまたいで動くことを検証する。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE_HELPER="$REPO_ROOT/scripts/review-dispatch-state.sh"
ENVELOPE_HELPER="$REPO_ROOT/scripts/review-dispatch-envelope.sh"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

TMPDIR_PATH="$TEST_ROOT/dispatch"
mkdir -p -- "$TMPDIR_PATH"
TOKEN_FILE="$TMPDIR_PATH/sf-owner-token"
printf '%s\n' process-isolation-token > "$TOKEN_FILE"
chmod 600 "$TOKEN_FILE"

SF_HELPER="$TEST_ROOT/sf-helper.sh"
cat > "$SF_HELPER" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == release ]]; then
  printf '%s\n' '{"state":"released"}'
  exit 0
fi
exit 2
EOF
chmod 700 "$SF_HELPER"

STATE_FILE="$TMPDIR_PATH/dispatch-state.json"
jq -n \
  --arg tmpdir "$TMPDIR_PATH" --arg dispatch_state "$STATE_FILE" --arg state_helper "$STATE_HELPER" \
  --arg sf_helper "$SF_HELPER" --arg envelope_helper "$ENVELOPE_HELPER" \
  --arg canonical_key $'github.com\nowner/repo\n411' --arg owner_token_file "$TOKEN_FILE" \
  '{schema_version:"1",phase:"handoff",tmpdir:$tmpdir,dispatch_state:$dispatch_state,backend:"codex",state_helper:$state_helper,sf_helper:$sf_helper,envelope_helper:$envelope_helper,canonical_key:$canonical_key,owner_token_file:$owner_token_file,singleflight_file:($tmpdir + "/singleflight.json"),lease_id:"lease-process-isolation",per_pr:{acquired:true,lease_id:"lease-process-isolation"},saved_rc:0,post_state:"in_progress"}' \
  > "$STATE_FILE"

# 1つ目の Bash 呼び出しが終了した後、state 更新だけを永続化する。
env -i PATH="$PATH" bash -c '
  set -euo pipefail
  unset DISPATCH_TMPDIR DISPATCH_STATE SF_HELPER SF_CANONICAL_KEY SF_LEASE_ID
  bash "$1" set --dispatch-state "$2" --filter '\'' .phase="engine_running" '\''
' _ "$STATE_HELPER" "$STATE_FILE"

# 2つ目の呼び出しでは前プロセスの変数・関数を一切使わず、dispatch_state から再導出して envelope を生成する。
env -i PATH="$PATH" bash -c '
  set -euo pipefail
  unset DISPATCH_TMPDIR STATE_HELPER SF_HELPER ENVELOPE_HELPER SF_CANONICAL_KEY SF_TOKEN_FILE SF_LEASE_ID
  DISPATCH_STATE="$1"
  DISPATCH_TMPDIR="$(jq -er '\''.tmpdir'\'' "$DISPATCH_STATE")"
  STATE_HELPER="$(jq -er '\''.state_helper'\'' "$DISPATCH_STATE")"
  SF_HELPER="$(jq -er '\''.sf_helper'\'' "$DISPATCH_STATE")"
  ENVELOPE_HELPER="$(jq -er '\''.envelope_helper'\'' "$DISPATCH_STATE")"
  SF_CANONICAL_KEY="$(jq -er '\''.canonical_key'\'' "$DISPATCH_STATE")"
  bash "$STATE_HELPER" write-envelope --dispatch-state "$DISPATCH_STATE" --dispatch-tmpdir "$DISPATCH_TMPDIR" \
    --sf-helper "$SF_HELPER" --envelope-helper "$ENVELOPE_HELPER" --canonical-key "$SF_CANONICAL_KEY" \
    --backend "$(jq -er '\''.backend'\'' "$DISPATCH_STATE")" --status unavailable --post-state not_applicable \
    --reason "process isolation test"
' _ "$STATE_FILE"

RESULT_FILE="$TMPDIR_PATH/review-dispatch-result.json"
jq -e '.dispatch_status == "unavailable" and .post_state == "not_applicable" and (.failure_reason | length) > 0' "$RESULT_FILE" >/dev/null

# write-envelope も欠落した dispatch-state を受け付けず、既存 result を捏造しない。
MISSING_TMPDIR="$TEST_ROOT/missing-state"
mkdir -p -- "$MISSING_TMPDIR"
set +e
bash "$STATE_HELPER" write-envelope --dispatch-state "$MISSING_TMPDIR/dispatch-state.json" --dispatch-tmpdir "$MISSING_TMPDIR" \
  --sf-helper "$SF_HELPER" --envelope-helper "$ENVELOPE_HELPER" --canonical-key $'github.com\nowner/repo\n411' \
  --backend codex --status unavailable --post-state not_applicable --reason "missing state test" \
  >"$TEST_ROOT/missing-state.out" 2>"$TEST_ROOT/missing-state.err"
MISSING_STATE_RC=$?
set -e
if [[ "$MISSING_STATE_RC" -ne 0 && ! -e "$MISSING_TMPDIR/review-dispatch-result.json" ]]; then
  echo "PASS: write-envelope は欠落した dispatch-state を拒否する"
else
  echo "FAIL: write-envelope は欠落した dispatch-state を拒否する"
  exit 1
fi

# 3つ目の呼び出しも独立プロセスで cleanup を実行し、lease/state を更新する。
env -i PATH="$PATH" bash -c '
  set -euo pipefail
  unset DISPATCH_TMPDIR STATE_HELPER SF_HELPER SF_CANONICAL_KEY SF_TOKEN_FILE SF_LEASE_ID
  DISPATCH_STATE="$1"
  DISPATCH_TMPDIR="$(jq -er '\''.tmpdir'\'' "$DISPATCH_STATE")"
  STATE_HELPER="$(jq -er '\''.state_helper'\'' "$DISPATCH_STATE")"
  SF_HELPER="$(jq -er '\''.sf_helper'\'' "$DISPATCH_STATE")"
  SF_CANONICAL_KEY="$(jq -er '\''.canonical_key'\'' "$DISPATCH_STATE")"
  SF_TOKEN_FILE="$(jq -er '\''.owner_token_file'\'' "$DISPATCH_STATE")"
  SF_LEASE_ID="$(jq -er '\''.lease_id'\'' "$DISPATCH_STATE")"
  bash "$STATE_HELPER" cleanup --dispatch-state "$DISPATCH_STATE" --dispatch-tmpdir "$DISPATCH_TMPDIR" \
    --sf-helper "$SF_HELPER" --canonical-key "$SF_CANONICAL_KEY" \
    --owner-token-file "$SF_TOKEN_FILE" --lease-id "$SF_LEASE_ID"
' _ "$STATE_FILE"

jq -e '.per_pr.acquired == false and .phase == "cleaned"' "$STATE_FILE" >/dev/null
echo "PASS: handoff 後の state/envelope/cleanup が独立 Bash 呼び出しで動作する"
