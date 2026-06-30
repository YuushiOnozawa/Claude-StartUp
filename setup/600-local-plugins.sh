# setup/600-local-plugins.sh — skills・agents・scripts のデプロイ確認
# Requires: ok, SETUP_DIR

[[ "${BASH_SOURCE[0]}" == "$0" ]] && { echo "ERROR: setup.sh から source してください" >&2; exit 1; }

echo ""
echo "--- skills/agents/scripts ---"

# リポジトリが ~/.claude/ 直下にある場合はコピー不要（すでに正しい場所にある）
if [[ "$(dirname "$SETUP_DIR")" -ef "$HOME/.claude" ]]; then
  ok "リポジトリが ~/.claude/ 直下のためコピーをスキップ"
else
  echo "  ℹ  リポジトリが ~/.claude/ 外にあります。skills/agents/scripts の手動デプロイが必要です。"
fi
