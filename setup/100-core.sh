# setup/100-core.sh — git, node, npm, commitlint チェック
# Requires: ok, fail, check_cmd, check_package, npm_is_installed, npm_install, npm_install_hint, MISSING_CMDS (append-only), MISSING_NPM (append-only)

[[ "${BASH_SOURCE[0]}" == "$0" ]] && { echo "ERROR: setup.sh から source してください" >&2; exit 1; }

# --- core ---
check_cmd "git"  "git"  "brew install git  /  apt install git"
check_cmd "node" "node" "https://nodejs.org/"
check_cmd "npm"  "npm"  "Node.js に同梱"

# --- git hooks / commit quality ---
if command -v npm &>/dev/null; then
  check_package "commitlint" npm \
    "@commitlint/cli" "@commitlint/config-conventional"
fi
