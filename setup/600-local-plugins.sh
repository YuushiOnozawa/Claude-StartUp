# setup/600-local-plugins.sh — skills・agents のデプロイ
# Requires: ok, fail, MISSING_CMDS (append-only), SETUP_DIR

[[ "${BASH_SOURCE[0]}" == "$0" ]] && { echo "ERROR: setup.sh から source してください" >&2; exit 1; }

echo ""
echo "--- skills ---"

# repo/skills/ → ~/.claude/skills/ にコピー（Skill ツールの参照先）
_skills_src="$(dirname "$SETUP_DIR")/skills"
if [[ -d "$_skills_src" ]]; then
  _skill_count=0
  for _skill_dir in "$_skills_src"/*/; do
    [[ -d "$_skill_dir" ]] || continue
    _skill_name="$(basename "$_skill_dir")"
    # src=dst になる場合はスキップ（リポジトリが ~/.claude/ 直下の場合）
    if [[ "$_skill_dir" -ef "$HOME/.claude/skills/$_skill_name" ]]; then
      continue
    fi
    rm -rf "$HOME/.claude/skills/$_skill_name"
    mkdir -p "$HOME/.claude/skills/$_skill_name"
    cp -r "$_skill_dir/." "$HOME/.claude/skills/$_skill_name/"
    _skill_count=$((_skill_count + 1))
  done
  ok "skills $_skill_count 件を ~/.claude/skills/ にコピー"
else
  echo "  ℹ  skills/ ディレクトリが見つかりません。スキルのコピーをスキップ。"
fi
unset _skills_src _skill_dir _skill_name _skill_count

echo ""
echo "--- agents ---"

# repo/agents/ → ~/.claude/agents/ にコピー（MAGIペルソナ等のエージェント定義）
# ※ skills（汎用ツール）とは責務が異なる: agents はレビュー人格・手順を定義するアーキテクチャ資産
_agents_src="$(dirname "$SETUP_DIR")/agents"
if [[ -d "$_agents_src" ]]; then
  rm -rf "$HOME/.claude/agents"
  mkdir -p "$HOME/.claude/agents"
  _agent_count=0
  for _agent_file in "$_agents_src"/*.md; do
    [[ -f "$_agent_file" ]] || continue
    cp "$_agent_file" "$HOME/.claude/agents/"
    _agent_count=$((_agent_count + 1))
  done
  ok "agents $_agent_count 件を ~/.claude/agents/ にコピー"
else
  echo "  ℹ  agents/ ディレクトリが見つかりません。エージェントのコピーをスキップ。"
fi
unset _agents_src _agent_file _agent_count

echo ""
echo "--- scripts ---"

# repo/scripts/ → ~/.claude/scripts/ にコピー（ollama-run.sh 等の共有スクリプト）
_scripts_src="$(dirname "$SETUP_DIR")/scripts"
if [[ -d "$_scripts_src" ]]; then
  mkdir -p "$HOME/.claude/scripts"
  _script_count=0
  for _script_file in "$_scripts_src"/*.sh; do
    [[ -f "$_script_file" ]] || continue
    cp "$_script_file" "$HOME/.claude/scripts/"
    chmod +x "$HOME/.claude/scripts/$(basename "$_script_file")"
    _script_count=$((_script_count + 1))
  done
  ok "scripts $_script_count 件を ~/.claude/scripts/ にコピー"
else
  echo "  ℹ  scripts/ ディレクトリが見つかりません。スクリプトのコピーをスキップ。"
fi
unset _scripts_src _script_file _script_count
