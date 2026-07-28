# setup/100-core.sh — git, node, npm, ripgrep, commitlint チェック
# Requires: ok, fail, check_cmd, check_package, npm_is_installed, npm_install, npm_install_hint, _detect_os, _detect_arch, _install_binary_tar, ensure_local_bin_in_path, MISSING_CMDS (append-only), MISSING_NPM (append-only)

[[ "${BASH_SOURCE[0]}" == "$0" ]] && { echo "ERROR: setup.sh から source してください" >&2; exit 1; }

# --- core ---
check_cmd "git"  "git"  "brew install git  /  apt install git"
check_cmd "node" "node" "https://nodejs.org/"
check_cmd "npm"  "npm"  "Node.js に同梱"

_ripgrep_is_installed() {
  local candidate path_entry version_out
  local -a path_entries
  IFS=':' read -r -a path_entries <<< "${PATH:-}"
  for path_entry in "$HOME/.local/bin" "${path_entries[@]}"; do
    [[ -z "$path_entry" ]] && continue
    candidate="$path_entry/rg"
    [[ -f "$candidate" && -x "$candidate" ]] || continue
    case "$candidate" in
      */.claude/*|*/.codex/*|*@openai/codex*|*codex-path*|*/plugins/cache/*) continue ;;
    esac
    # パイプで grep -q に渡すと、早期終了による SIGPIPE が pipefail 下で偽の失敗になりうるため
    # 一旦変数に受けてから判定する
    version_out="$("$candidate" --version 2>/dev/null)" || continue
    [[ "$version_out" == *ripgrep* ]] && return 0
  done
  return 1
}

if ! _ripgrep_is_installed; then
  echo "  → ripgrep が未導入。バイナリをダウンロード中..."
  _install_ripgrep() {
    local version os arch target url
    version=$(curl -fsSL "https://api.github.com/repos/BurntSushi/ripgrep/releases/latest" \
              | grep '"tag_name"' | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/' | head -1)
    [[ -z "$version" ]] && return 1
    [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && {
      fail "ripgrep: 予期しないバージョン形式: $version"; return 1
    }
    os="$(_detect_os)" || return 1
    arch="$(_detect_arch rust)" || return 1
    case "$os/$arch" in
      linux/x86_64)   target="x86_64-unknown-linux-musl" ;;
      linux/aarch64)  target="aarch64-unknown-linux-musl" ;;
      darwin/x86_64)  target="x86_64-apple-darwin" ;;
      darwin/aarch64) target="aarch64-apple-darwin" ;;
      *) fail "ripgrep: 未対応 OS/arch: $os/$arch"; return 1 ;;
    esac
    url="https://github.com/BurntSushi/ripgrep/releases/download/${version}/ripgrep-${version}-${target}.tar.gz"
    _install_binary_tar "rg" "$url" "rg"
  }
  if _install_ripgrep; then
    ok "ripgrep (バイナリ自動インストール完了)"
    ensure_local_bin_in_path
  else
    fail "ripgrep  →  brew install ripgrep  /  apt install ripgrep"
    MISSING_CMDS+=("ripgrep")
  fi
  unset -f _install_ripgrep
else
  ok "ripgrep"
fi
unset -f _ripgrep_is_installed

# --- git hooks / commit quality ---
if command -v npm &>/dev/null; then
  check_package "commitlint" npm \
    "@commitlint/cli" "@commitlint/config-conventional"
fi
