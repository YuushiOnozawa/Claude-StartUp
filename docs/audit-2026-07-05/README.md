# Claude-StartUp 精査結果（2026-07-05）

リポジトリの目的（新規環境へのワンライナー展開 / Token削減 / 開発フローSKILL / 会話ログ蒸留による長期記憶 / 1スキル1ローカルLLM / Codex実装・Claudeオーケストラ）に照らした過不足・修正対応の一覧。

各項目の対応プランは同ディレクトリの個別 md を参照。

**検証方針**: ドキュメント（README/SKILLS.md/DESIGN.md/TOOLS.md）は更新が実装に追いついていないため、
**各 SKILL.md・setup/・hooks/ の実装と git 履歴を正**として判定した。ドキュメントと実装の食い違いは
すべて「ドキュメント側を実装に追随させる」方向で扱う（03 参照）。実装同士が矛盾する箇所（04）は
git 履歴（Issue #96/#97 のトリガー移設）で新旧を判定した。

## A. 修正対応が必要な箇所（現状バグ・不整合）

| # | 項目 | 深刻度 | プラン |
|---|------|--------|--------|
| 01 | MAGI エージェント定義の参照不整合 — #203 で5体分を意図的に削除したが execution-steps.md / casper に参照が残存、#234 で leliel.md だけ復活し方針が分裂（本番 ~/.claude にも実体なし） | 高 | [01-magi-agents-missing.md](01-magi-agents-missing.md) |
| 02 | `setup/800-ollama-models.sh` とスキルのモデル割当が不整合（LELIEL / BALTHASAR 新モデル未pull、不要モデル3本を pull） | 高 | [02-ollama-model-sync.md](02-ollama-model-sync.md) |
| 03 | ドキュメント陳腐化（SKILLS.md の5体表・旧モデル・codegen=gemma4 記述、DESIGN.md、README の local-plugins/） | 中 | [03-docs-staleness.md](03-docs-staleness.md) |
| 04 | `setup/410-hooks-distill.sh` が SessionEnd に knowledge-distill を二重登録（SessionStart ドレイン設計と競合）、ログパスも不一致 | 高 | [04-hooks-registration-conflict.md](04-hooks-registration-conflict.md) |
| 05 | `settings.json` の PostToolUse が参照する `error-detector.sh` がどの setup モジュールでも配備されない（自動エラー検知が無音で無効） | 中 | [05-error-detector-not-deployed.md](05-error-detector-not-deployed.md) |
| 06 | スキル内の `bash scripts/...` 相対パス参照 — 他プロジェクトで /magi-fast 実行時に diff フィルタが失敗し「差分なし」と誤判定。codex-companion のバージョン固定パスも混在 | 高 | [06-script-path-resolution.md](06-script-path-resolution.md) |
| 07 | リポジトリ衛生（未追跡ファイル4件、`.codex/` の gitignore 未対応、worktree 残骸） | 低 | [07-repo-hygiene.md](07-repo-hygiene.md) |
| 15 | 本番 `~/.claude` クローンが main から約100PR 遅れ + 30ファイル超の未コミット直編集で最新化されている（デプロイフロー不在。04 の二重登録もここで現在進行形） | 高 | [15-live-deploy-drift.md](15-live-deploy-drift.md) |

## B. 不足している機能（目的に対するギャップ）

| # | 項目 | 優先度 | プラン |
|---|------|--------|--------|
| 08 | Codex CLI が自動インストールされない（実装レイヤの中核なのに確認のみ） | 高 | [08-codex-auto-install.md](08-codex-auto-install.md) |
| 09 | Ollama 未起動だとモデル pull が黙ってスキップ → MAGI がフォールバック頼みになる。setup 内での serve 起動/常駐化がない | 高 | [09-ollama-serve-in-setup.md](09-ollama-serve-in-setup.md) |
| 10 | セットアップ後の統合検証（doctor/verify）がない — 何が動く状態かを一発で確認できない | 中 | [10-setup-verify.md](10-setup-verify.md) |
| 11 | CI がない（shellcheck / bash -n / 既存 test-*.sh の自動実行） | 中 | [11-ci-pipeline.md](11-ci-pipeline.md) |
| 12 | セットアップ後の手動ステップのチェックリスト不足（Codex 認証・pCloud OAuth・OLLAMA_TIER が README から辿れない） | 中 | [12-manual-steps-checklist.md](12-manual-steps-checklist.md) |

## C. 推奨追加機能

| # | 項目 | 優先度 | プラン |
|---|------|--------|--------|
| 13 | 【方針決定済み】知識ストアの疎結合化 — 記録層はローカル store で完結、Obsidian への配送/取込は独立した一方向 rsync 層に分離（rclone mount 廃止、pcloud キュー根治、人間ノートも RAG に取込） | 高 | [13-pcloud-fallback.md](13-pcloud-fallback.md) |
| 14 | Windows ネイティブ環境対応（現状 WSL/Linux 前提） | 低 | [14-windows-native.md](14-windows-native.md) |
| 16 | Obsidian 第2の脳ワークフロー — inbox にメモした URL 等を Claude が調査し knowledge として還流（/inbox スキル。13 の基盤の上に構築） | 中 | [16-obsidian-second-brain.md](16-obsidian-second-brain.md) |
| 17 | プロジェクト横断の長期記憶活用 — 蒸留を「経験カード」形式（結果・判断を構造化）に強化し、UserPromptSubmit の auto-recall フックで過去の類似経験を自動想起（要件4「A の経験を B で活用」を完成させる層） | 中 | [17-cross-project-recall.md](17-cross-project-recall.md) |

## 良好と評価した点（変更不要）

- setup/ のモジュール自動検出（番号プレフィックス）・冪等設計・`|| true` の使用基準明文化
- Codex 監査層の共通化（codex-audit.md）とプロンプトインジェクション対策（fence 隔離・--write 禁止・diff フィルタ二層構造）
- knowledge-distill のキュー/リトライ/dead-letter 設計、raw と distilled の対応保証
- settings.json の deny ルール（credentials / .env / rclone 破壊系）
- トークン削減の多層防御（RTK + lean-ctx + effortLevel medium + adaptive thinking off + autocompact 75%）

## 推奨着手順

1. **15**（本番 ~/.claude の git 正常化。これを先にやらないと、以降の修正を main に入れても本番に届かない）
2. **01 / 02 / 06**（レビューパイプラインの実動作に直結。1モデル1スキル原則が現状崩れている）
3. **04 / 13 / 05**（蒸留パイプライン刷新 — 二重登録解消（04）とローカル正移行（13）は同じフック群を
   触るため同系列の PR でやると手戻りが少ない。05 も hooks/ 配置の整理として同時に）
4. **08 / 09 / 10**（ワンライナー展開の完成度 — 「実行したら全部動く」に到達させる）
5. **03 / 12 / 11 / 07**（ドキュメント・CI・衛生）
6. **16 / 17**（13 の基盤完成後。16 = 人間→AI の還流、17 = 横断想起。この2つで「第2の脳」の要件4が完成する）
7. **14**（任意）
