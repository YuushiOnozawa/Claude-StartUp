# setup/350-semgrep-gitleaks.sh — Semgrep + gitleaks セキュリティ土台セットアップ
# Requires: ok, fail, MISSING_CMDS (append-only)
[[ "${BASH_SOURCE[0]}" == "$0" ]] && { echo "ERROR: setup.sh から source してください" >&2; exit 1; }

echo ""
echo "--- semgrep + gitleaks ---"

# Phase 1: ツール確認
check_cmd "pre-commit" "pre-commit" "pip install pre-commit"
check_cmd "gitleaks"   "gitleaks"   "https://github.com/gitleaks/gitleaks#installing"
check_cmd "semgrep"    "semgrep"    "pip install semgrep"

# Phase 2: テンプレートを ~/.git-templates/security/ に配置
_SEC_SRC="$(dirname "${BASH_SOURCE[0]}")/../templates/security"
_SEC_DST="${HOME}/.git-templates/security"

if [[ ! -d "$_SEC_SRC" ]]; then
  fail "templates/security/  →  ソースディレクトリが見つかりません: $_SEC_SRC"
  MISSING_CMDS+=("security-templates")
else
  mkdir -p "$_SEC_DST" "$_SEC_DST/github-workflows"
  if cp "$_SEC_SRC/.pre-commit-config.yaml" "$_SEC_DST/" \
    && cp "$_SEC_SRC/.gitleaks.toml"        "$_SEC_DST/" \
    && cp "$_SEC_SRC/github-workflows/security-scan.yml" "$_SEC_DST/github-workflows/"; then
    ok "テンプレート配置 → $_SEC_DST"
  else
    fail "テンプレート配置失敗  →  手動: cp -r $_SEC_SRC/* $_SEC_DST/"
    MISSING_CMDS+=("security-templates")
  fi
fi

# Phase 3: secinit 関数を rc ファイルに冪等登録
_SEC_RC_MARKER="Claude-StartUp: secinit"
case "$(basename "${SHELL:-/bin/bash}")" in
  zsh)  _SEC_RC="$HOME/.zshrc" ;;
  bash) _SEC_RC="$HOME/.bashrc" ;;
  *)    _SEC_RC="$HOME/.profile" ;;
esac

if ! { [[ -f "$_SEC_RC" ]] && grep -qF "$_SEC_RC_MARKER" "$_SEC_RC"; }; then
  {
    cat <<'SECINIT_EOF'

# Claude-StartUp: secinit
secinit() {
  local TMPL="${HOME}/.git-templates/security"
  [[ -d "$TMPL" ]] || { echo "Error: security templates not found. Run setup.sh first." >&2; return 1; }
  [[ -d .git ]] || git init || return 1
  cp "${TMPL}/.pre-commit-config.yaml" . || return 1
  cp "${TMPL}/.gitleaks.toml"          . || return 1
  pre-commit install || return 1
  command -v pre-commit >/dev/null 2>&1 && pre-commit validate-config || true  # 検証失敗は非致命的（semgrep の CLI 互換性問題に備え警告に留める）
  echo "✅ semgrep + gitleaks セットアップ完了 (CI テンプレート: ~/.git-templates/security/github-workflows/)"
}
SECINIT_EOF
  } >> "$_SEC_RC"
  ok "secinit 登録 → $_SEC_RC"
fi

unset _SEC_SRC _SEC_DST _SEC_RC _SEC_RC_MARKER
