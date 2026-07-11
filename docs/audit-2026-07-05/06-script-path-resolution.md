# 06. スキル内スクリプト参照のパス解決不統一（他プロジェクト実行時に破綻）

種別: 修正対応 / 深刻度: 高

## 現状

スキルはグローバル（`~/.claude/skills/`）として任意のプロジェクト cwd から呼ばれるのに、
補助スクリプトの参照方法が3通り混在している：

| 参照箇所 | 記述 | 任意 cwd での挙動 |
|---|---|---|
| magi-fast ステップ1 / magi-hard ステップ1 / execution-steps ステップ1-4 | `bash scripts/magi-diff-filter.sh`（相対） | ❌ ファイル不在 → パイプ出力が空 → **「差分がありません」と誤判定して終了**（フィルタ失敗が差分ゼロに化ける） |
| magi-hard ステップ2 | `bash scripts/magi-impact-context.sh`（相対） | ⚠ 失敗時空文字続行のため無音で IMPACT_CONTEXT が消える |
| execution-steps ステップ2 | `bash ~/.claude/scripts/ollama-run.sh`（絶対） | ✅ 動く |
| codex-audit.md / design-review.md | `ls ~/.claude/plugins/cache/openai-codex/codex/*/scripts/codex-companion.mjs \| sort -V \| tail -1`（グロブ） | ✅ 動く |
| codegen `references/spec-template.md` | `.../codex/1.0.5/scripts/codex-companion.mjs`（**バージョンハードコード**） | ❌ プラグイン更新で即破綻 |

「repo 内を優先、なければ ~/.claude/」という二段解決は references の Read には明記されているが、
シェル実行部には適用されていない。

## 影響

- Claude-StartUp 以外のプロジェクトで `/magi-fast` `/magi-hard` を実行すると、
  ロールプレイ防御フィルタが機能しないどころか、レビュー自体が「差分なし」で空振りする。
  dev-flow Phase 5 のレビューゲートが実質すり抜けになるため、開発フロー全体の品質保証が崩れる。
- Codex プラグインが 1.0.5 以外になると codegen の可用性チェックが常に失敗し、
  Haiku フォールバックに落ち続ける（= Codex 実装方針が無効化される）。

## 対応プラン

1. スクリプトパス解決の共通規約を定める。SKILL.md / references 内のシェル例をすべて次の形に統一：

   ```bash
   MAGI_SCRIPTS="${CLAUDE_STARTUP_SCRIPTS:-$HOME/.claude/scripts}"
   DIFF=$(printf '%s\n' "$DIFF" | bash "$MAGI_SCRIPTS/magi-diff-filter.sh")
   ```

   repo 開発時は `CLAUDE_STARTUP_SCRIPTS=./scripts` で上書き可能にする。
2. **フィルタ失敗と差分ゼロを区別する**。`magi-diff-filter.sh` 不在・非ゼロ終了なら
   「フィルタ実行失敗（パスを確認）」と表示して中断し、「差分がありません」とは言わせない。
   例: `DIFF_FILTERED=$(... ) || { echo "⚠ diff フィルタ失敗"; exit 1; }`
3. `spec-template.md` の codex-companion パスを codex-audit.md と同じグロブ + `sort -V | tail -1` 方式に置換。
   ついでに3ファイル（spec-template / codex-audit / design-review）でパス解決スニペットが
   コピペ重複しているため、`scripts/resolve-codex-companion.sh`（stdout にパスを出すだけ）に共通化する。
4. 修正対象の洗い出しは grep で機械的に行う：
   `grep -rn 'bash scripts/\|codex/1\.0\.5' skills/`
5. 検証: リポジトリ外の適当な git プロジェクトで `/magi-fast`（Ollama 有効）を実行し、
   フィルタ・チャンク分割・ollama-run が通ることを確認する。

## 受け入れ基準

- [ ] `grep -rn 'bash scripts/' skills/` がゼロ件
- [ ] `grep -rn 'codex/1\.0\.5' skills/` がゼロ件
- [ ] 他プロジェクト cwd から /magi-fast 実行でレビューが完走する
- [ ] フィルタスクリプト不在時に「差分なし」ではなくエラーが表示される

## 影響ファイル

- `skills/magi-fast/SKILL.md`, `skills/magi-hard/SKILL.md`
- `skills/magi-common/references/execution-steps.md`
- `skills/codegen/references/spec-template.md`
- （新規）`scripts/resolve-codex-companion.sh`
