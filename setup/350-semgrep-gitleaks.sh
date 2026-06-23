# setup/350-semgrep-gitleaks.sh — Semgrep + gitleaks セキュリティ土台セットアップ
# Requires: ok, fail, check_package, _detect_os, _detect_arch, _install_binary_tar, MISSING_CMDS (append-only)
[[ "${BASH_SOURCE[0]}" == "$0" ]] && { echo "ERROR: setup.sh から source してください" >&2; exit 1; }

echo ""
echo "--- semgrep + gitleaks ---"

# Phase 1: ツール確認・自動インストール
check_package "pre-commit" pip pre-commit
check_package "semgrep"    pip semgrep

if ! command -v gitleaks &>/dev/null; then
  echo "  → gitleaks が未導入。バイナリをダウンロード中..."
  _install_gitleaks() {
    local version
    version=$(curl -fsSL "https://api.github.com/repos/gitleaks/gitleaks/releases/latest" \
              | grep '"tag_name"' | sed 's/.*"v\([^"]*\)".*/\1/' | head -1)
    [[ -z "$version" ]] && return 1
    [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && {
      fail "gitleaks: 予期しないバージョン形式: $version"; return 1
    }
    _install_binary_tar "gitleaks" \
      "https://github.com/gitleaks/gitleaks/releases/download/v${version}/gitleaks_${version}_$(_detect_os)_$(_detect_arch github).tar.gz"
  }
  if _install_gitleaks; then
    ok "gitleaks (バイナリ自動インストール完了)"
  else
    fail "gitleaks  →  https://github.com/gitleaks/gitleaks#installing"
    MISSING_CMDS+=("gitleaks")
  fi
  unset -f _install_gitleaks
else
  ok "gitleaks"
fi

# Phase 2: テンプレートを ~/.git-templates/security/ に配置
_SEC_SRC="$(dirname "${BASH_SOURCE[0]}")/../templates/security"
_SEC_DST="${HOME}/.git-templates/security"

if [[ ! -d "$_SEC_SRC" ]]; then
  fail "templates/security/  →  ソースディレクトリが見つかりません: $_SEC_SRC"
  MISSING_CMDS+=("security-templates")
else
  _src_real=$(realpath "$_SEC_SRC" 2>/dev/null || echo "$_SEC_SRC")
  _dst_real=$(realpath "$_SEC_DST" 2>/dev/null || echo "$_SEC_DST")
  if [[ "$_src_real" == "$_dst_real" ]]; then
    ok "テンプレート配置済み（ソース＝デスティネーション — スキップ）"
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
  [[ -f .pre-commit-config.yaml ]] && { echo "Warning: .pre-commit-config.yaml が既に存在します。削除後に再実行してください。" >&2; return 1; }
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

unset _SEC_SRC _SEC_DST _SEC_RC _SEC_RC_MARKER _src_real _dst_real
