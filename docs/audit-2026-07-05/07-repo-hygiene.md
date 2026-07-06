# 07. リポジトリ衛生（未追跡ファイル・gitignore・残骸）

種別: 修正対応 / 深刻度: 低

## 現状

`git status` に以下の未追跡が滞留している：

| パス | 内容 | 対応方針 |
|---|---|---|
| `.codex/hooks.json` | agmsg 用 SessionStart/End フック。`/home/ylocal/...` の絶対パスを含むマシン固有設定 | セッションまとめ（2026-07-03）で「agmsg はリポジトリに含めない・個人設定として残す」と決定済み → `.gitignore` に `.codex/` を追加 |
| `2026-07-03-session-summary.md` | セッションの作業メモ。内容は Issue #251/#252/PR #253 に反映済み | 削除、または `docs/session-notes/` へ移動して追跡。ルート直下に日付ファイルを置く運用は避ける |
| `CLAUDE.local.md` | マシン固有メモ（CLAUDE.md の方針で .gitignore 対象と明記されている） | `.gitignore` に `CLAUDE.local.md` を追加（現状 ignore されておらず status に出続ける） |
| `scripts/index-investigations.sh` | 調査系スクリプト | 使うなら commit（コメントヘッダ整備）、実験なら scratch へ退避。放置しない |

その他：

- `worktree/refactor/knowledge-distill-raw-first/` — マージ済みと思われる worktree 残骸（リポジトリ全体の
  コピーがそのまま残っている）。`/worktree done refactor/knowledge-distill-raw-first` で掃除する。
  `/finished-pr` の Phase 6 が worktree 削除を担う設計なので、消し忘れが起きた原因
  （finished-pr を通さなかった／失敗した）も軽く確認する。
- `.claude/scheduled_tasks.lock`, `.claude/settings.local.json` — `.gitignore` の `.claude/` で無視済み。対応不要。

## 対応プラン

1. `.gitignore` に追記：

   ```
   # Codex 個人設定（agmsg フック等、マシン固有）
   /.codex/

   # マシン固有メモ（CLAUDE.md の管理方針参照）
   CLAUDE.local.md
   ```

2. `2026-07-03-session-summary.md` は削除（内容は Issue/PR に反映済みのため）。
   セッションまとめを残したい運用なら `docs/session-notes/` を作りそちらに置く規約を README に書く。
3. `scripts/index-investigations.sh` の要否をユーザーに確認 → commit or 削除。
4. worktree 残骸を `/worktree done` で削除。
5. `/commit` スキルで1関心事ずつコミット（gitignore 追記と削除は分ける）。

## 受け入れ基準

- [ ] `git status --short` がクリーン（意図した未追跡ゼロ）
- [ ] `worktree/` 配下が空
- [ ] ルート直下に日付付き一時ファイルがない

## 影響ファイル

- `.gitignore`
- 削除/移動: `2026-07-03-session-summary.md`, `worktree/refactor/...`, `scripts/index-investigations.sh`（要判断）
