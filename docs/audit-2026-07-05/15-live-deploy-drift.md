# 15. 本番 ~/.claude クローンの git 状態正常化とデプロイフロー定義

種別: 修正対応（運用）/ 深刻度: 高

> **追記（2026-07-06）**: 本プランのフェーズ3（pull ベース同期）に対する代替案として
> 「~/.claude を git 配下から外し、開発リポジトリからの配備スクリプト（rsync ホワイトリスト）方式に
> する」が浮上している（core-02 README の人間確認点参照）。ランタイム変異が常態の本番ディレクトリと
> git 管理の相性の悪さが根本原因という見立て。**どちらを採るかは core-02 の Step 3 で確定させる**。
> フェーズ1（棚卸し・差分3分類）はどちらの案でも必要なので先行してよい。

## 実態（本番 WSL 環境で確認済み）

`~/.claude/` は Claude-StartUp リポジトリの clone（本番デプロイ先）だが：

- **HEAD が e1dc01f (#158) で、main (99166b8, #265) から約100PR 遅れている**
- 一方でファイル内容はローカル改変で最新化されている:
  - `skills/balthasar/SKILL.md` → gemma4:e4b-it-qat（#252 相当）
  - `skills/magi-hard/SKILL.md` → LELIEL・Codex 監査入り（#262 相当）
  - `skills/codegen/SKILL.md` → Codex 版（#254 相当）
- `git status` は M/MM/D 混在で 30 ファイル超が dirty（staged と unstaged が混在、
  agents 5体の作業ツリー削除、`hooks/error-detector.sh` 等の untracked あり）

つまり現在の運用は「**本番 ~/.claude を直接編集して動作を最新化 → 正式実装は srcs/Claude-StartUp
で dev-flow → 本番側は pull しない**」。git 履歴と本番実態が二重管理になっており、
- どの変更が main 反映済みで、どれが本番だけの未マージ実験かを git が答えられない
- 次に `git pull` した瞬間に大量コンフリクトが確定している
- 「リポジトリ = 再現可能なセットアップの正」という前提が本番で崩れている

## 対応プラン

### フェーズ 1: 棚卸し（読み取りのみ）

1. `git -C ~/.claude fetch origin`
2. ローカル改変を main と突合し3分類する:

   ```bash
   git -C ~/.claude diff HEAD --name-only | while read f; do
     git -C ~/.claude diff origin/main -- "$f" | head -1 | grep -q . \
       && echo "DRIFT: $f (mainと差分あり=未マージ実験 or 独自変更)" \
       || echo "SYNCED: $f (mainに同内容あり=手動先行適用済み)"
   done
   ```

   - **SYNCED**（main に同内容が既にある）→ 破棄してよい
   - **DRIFT**（main に無い変更）→ 未マージの実験。srcs 側で Issue/PR 化するか破棄を個別判断
   - **ローカル状態ファイル**（settings.json のツール注入 hook、CLAUDE.md の RTK import 等）
     → TOOLS.md の「ローカル差分」方針どおり保持

### フェーズ 2: 同期実行

3. 安全網: `cp -r ~/.claude ~/claude-backup-$(date +%m%d)`（credentials 含むため権限注意）
4. DRIFT 分を patch として退避: `git -C ~/.claude diff HEAD > ~/claude-local-drift.patch`
5. `git -C ~/.claude checkout -- .` → `git pull origin main`（agents 5体の作業ツリー削除は
   main 側でも削除済み（#203）なのでコンフリクトしない見込み）
6. ローカル状態ファイル（settings.json 等）はツールが再注入するか、patch から選択的に復元
7. `bash setup.sh` を再実行し、`--verify`（[10](10-setup-verify.md) 実装後）で状態確認

### フェーズ 3: 再発防止（デプロイフローの定義）

8. 「本番反映 = `git -C ~/.claude pull`」を正式手順とし、README に明記する。
   `/finished-pr`（マージ後クリーンアップ）に「~/.claude が clone ならば pull を提案する」
   ステップを追加すると、マージのたびに本番が追従する
9. 本番 ~/.claude を直接編集する実験は「untracked な *.local.* か CLAUDE.local.md に限る」
   規約を AGENTS.md / CLAUDE.md に追記。追跡ファイルを本番で直編集しない
10. 開発クローン（srcs/Claude-StartUp）と本番（~/.claude）の役割分担を DESIGN.md に1段落で明文化

## 受け入れ基準

- [ ] `git -C ~/.claude status --short` がローカル状態ファイルのみ（説明可能な差分だけ）になる
- [ ] `git -C ~/.claude log --oneline -1` が origin/main と一致
- [ ] マージ後に本番へ反映する手順がドキュメント化され、/finished-pr から辿れる

## 影響ファイル

- 本番 `~/.claude/`（git 操作のみ、リポジトリ変更なし）
- `README.md`, `DESIGN.md`, `AGENTS.md`, `skills/finished-pr/references/phases.md`
