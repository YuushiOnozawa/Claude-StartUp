# setup/600-local-plugins.sh — skills のコピーと local-plugins のデプロイ・設定生成
# Requires: ok, fail, MISSING_CMDS (append-only), SETUP_DIR

[[ "${BASH_SOURCE[0]}" == "$0" ]] && { echo "ERROR: setup.sh から source してください" >&2; exit 1; }

# --- local-plugins: ~/.claude/local-plugins へのデプロイ ---
echo ""
echo "--- skills ---"

# repo/skills/ → ~/.claude/skills/ にコピー（Skill ツールの参照先）
_skills_src="$(dirname "$SETUP_DIR")/skills"
if [[ -d "$_skills_src" ]]; then
  _skill_count=0
  for _skill_dir in "$_skills_src"/*/; do
    [[ -d "$_skill_dir" ]] || continue
    _skill_name="$(basename "$_skill_dir")"
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
echo "--- local-plugins ---"

if ! command -v jq &>/dev/null; then
  fail "local-plugins  →  jq が必要です (brew install jq / apt install jq)"
  MISSING_CMDS+=("local-plugins-jq")
  return
fi

# パス設定（SETUP_DIR は setup.sh で定義済み）
_lp_owner="$(git -C "$(dirname "$SETUP_DIR")" config user.name 2>/dev/null || true)"
[[ -z "$_lp_owner" ]] && _lp_owner="${USER:-local}"
_LP_SRC="$(dirname "$SETUP_DIR")/local-plugins"
_LP_DEST="$HOME/.claude/local-plugins"
_LP_MARKETPLACE="$_LP_DEST/.claude-plugin/marketplace.json"
_LP_SETTINGS="$HOME/.claude/settings.json"
_LP_LOCAL_SETTINGS="$(dirname "$SETUP_DIR")/.claude/settings.local.json"

# 展開先のベースディレクトリを作成
mkdir -p "$_LP_DEST/.claude-plugin" "$_LP_DEST/skills"

# 各プラグインを走査してコピーし、marketplace エントリを収集
_lp_skill_entries="[]"

for _lp_plugin_dir in "$_LP_SRC"/*/; do
  [[ -d "$_lp_plugin_dir" ]] || continue
  _lp_plugin_name="$(basename "$_lp_plugin_dir")"
  _lp_plugin_json="$_lp_plugin_dir/.claude-plugin/plugin.json"

  # skills/* を持つプラグイン（skill プラグイン）
  if [[ -d "$_lp_plugin_dir/skills" ]]; then
    for _lp_skill_dir in "$_lp_plugin_dir/skills"/*/; do
      [[ -d "$_lp_skill_dir" ]] || continue
      _lp_skill_name="$(basename "$_lp_skill_dir")"
      mkdir -p "$_LP_DEST/skills/$_lp_skill_name"
      cp -r "$_lp_skill_dir/." "$_LP_DEST/skills/$_lp_skill_name/"
    done

    # marketplace.json 用エントリを構築
    if [[ -f "$_lp_plugin_json" ]]; then
      _lp_p_name="$(jq -r '.name' "$_lp_plugin_json")"
      _lp_p_desc="$(jq -r '.description' "$_lp_plugin_json")"
      # plugin.json の name が空・null の場合はスキップ（壊れたエントリを防ぐ）
      [[ -z "$_lp_p_name" || "$_lp_p_name" == "null" ]] && continue

      # skills/ 下の全サブディレクトリを "./skills/<name>" の配列に
      _lp_skills_arr="[]"
      for _lp_skill_dir in "$_lp_plugin_dir/skills"/*/; do
        [[ -d "$_lp_skill_dir" ]] || continue
        _lp_s="./skills/$(basename "$_lp_skill_dir")"
        _lp_skills_arr="$(jq --arg s "$_lp_s" '. += [$s]' <<< "$_lp_skills_arr")"
      done

      _lp_skill_entries="$(jq \
        --arg name "$_lp_p_name" \
        --arg desc "$_lp_p_desc" \
        --argjson skills "$_lp_skills_arr" \
        '. += [{"name":$name,"description":$desc,"source":"./","strict":false,"skills":$skills}]' \
        <<< "$_lp_skill_entries")"
    fi
  fi

  # commands/* を持つプラグイン（command プラグイン）
  if [[ -d "$_lp_plugin_dir/commands" ]]; then
    mkdir -p "$_LP_DEST/$_lp_plugin_name"
    cp -r "$_lp_plugin_dir/." "$_LP_DEST/$_lp_plugin_name/"
  fi
done

# marketplace.json を完全新規生成（skill プラグインが1件以上の場合のみ）
# ※ 再セットアップ時、削除済みプラグインのファイルは残留するが
#    marketplace.json から除外されるため Claude Code には認識されない
_lp_skill_count="$(jq 'length' <<< "$_lp_skill_entries")"
if [[ "$_lp_skill_count" -gt 0 ]]; then
  jq -n \
    --argjson plugins "$_lp_skill_entries" \
    --arg owner "$_lp_owner" \
    '{
      "name": "local-skills",
      "owner": {"name": $owner},
      "metadata": {"description": "ローカルカスタムスキル集", "version": "1.0.0"},
      "plugins": $plugins
    }' > "$_LP_MARKETPLACE"
  ok "marketplace.json ($_lp_skill_count スキル登録)"
else
  echo "  ℹ  skill プラグインが見つかりません。marketplace.json の生成をスキップ。"
fi

# settings.json に extraKnownMarketplaces と enabledPlugins を追加する関数
_lp_update_settings() {
  local f="$1" tmp="${1}.tmp"
  local _pd _pj _key

  # ファイルが存在しない・空の場合は空オブジェクトから生成
  [[ -s "$f" ]] || echo '{}' > "$f"

  # extraKnownMarketplaces["local-skills"] を追加（なければ）
  jq '.extraKnownMarketplaces["local-skills"] //=
    {"source":{"source":"directory","path":"~/.claude/local-plugins"}}' \
    "$f" > "$tmp" && mv "$tmp" "$f" || { rm -f "$tmp"; return 1; }

  # 現在 LP_SRC に存在するプラグイン名の配列を構築
  local _valid_keys="[]"
  for _pd in "$_LP_SRC"/*/; do
    [[ -d "$_pd" ]] || continue
    _pj="$_pd/.claude-plugin/plugin.json"
    [[ -f "$_pj" ]] || continue
    _valid_keys="$(jq --arg k "$(jq -r '.name' "$_pj")@local-skills" '. += [$k]' <<< "$_valid_keys")"
  done

  # @local-skills エントリのうち存在しないものを削除（廃止プラグインの残留防止）
  jq --argjson valid "$_valid_keys" \
    '.enabledPlugins = (.enabledPlugins // {} | to_entries | map(select(
      (.key | test("@local-skills$") | not) or (.key | IN($valid[]))
    )) | from_entries)' \
    "$f" > "$tmp" && mv "$tmp" "$f" || { rm -f "$tmp"; return 1; }

  # 各プラグインを enabledPlugins に追加（新規のみ、既存の false は保持）
  for _pd in "$_LP_SRC"/*/; do
    [[ -d "$_pd" ]] || continue
    _pj="$_pd/.claude-plugin/plugin.json"
    [[ -f "$_pj" ]] || continue
    _key="$(jq -r '.name' "$_pj")@local-skills"
    jq --arg key "$_key" '.enabledPlugins[$key] //= true' "$f" > "$tmp" && mv "$tmp" "$f" || { rm -f "$tmp"; return 1; }
  done
}

if _lp_update_settings "$_LP_SETTINGS"; then
  ok "settings.json (enabledPlugins, extraKnownMarketplaces)"
else
  fail "settings.json の更新に失敗"
  MISSING_CMDS+=("local-plugins-settings")
fi

# settings.local.json が存在する場合も同様に更新（CLAUDE.md の要件）
if [[ -f "$_LP_LOCAL_SETTINGS" ]]; then
  if _lp_update_settings "$_LP_LOCAL_SETTINGS"; then
    ok "settings.local.json (同期済み)"
  else
    fail "settings.local.json の更新に失敗"
  fi
fi

unset -f _lp_update_settings
unset _LP_SRC _LP_DEST _LP_MARKETPLACE _LP_SETTINGS _LP_LOCAL_SETTINGS
unset _lp_owner _lp_skill_entries _lp_skill_count
unset _lp_plugin_dir _lp_plugin_name _lp_plugin_json
unset _lp_p_name _lp_p_desc _lp_skills_arr _lp_s _lp_skill_dir _lp_skill_name
