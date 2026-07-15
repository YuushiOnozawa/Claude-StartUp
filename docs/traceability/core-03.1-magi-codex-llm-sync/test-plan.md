# Test Plan: Core 03.1 — MAGI / Codex / ローカルLLM連携の実体・参照・割当ズレ

> ステータス: approved（2026-07-16 作成・実行・同日人間承認済み）
> 対応 specification: approved（SPEC-03.1-06 改訂再承認 2026-07-16）
> 実行結果: **全 23 項目 PASS**（2026-07-16 実行）

## テスト観点一覧

| TEST ID | 対応 SPEC | 観点 | 区分 | 結果 |
|---|---|---|---|---|
| TEST-03.1-01 | SPEC-03.1-01 | 6ペルソナ SKILL.md に `agents/` 参照がない（正常系）/ `PERSONA_NAME` 全6体・`OLLAMA_MODEL` 5体（CASPER 除く）が残存（誤削除の異常系検知） | 自動（grep） | PASS（3項目） |
| TEST-03.1-02 | SPEC-03.1-02 | repo `agents/leliel.md` 不存在 / 対象外の `agents/code-reviewer.md` が誤削除されていない（境界条件）/ live `~/.claude/agents/leliel.md` 不存在（受け入れ条件「リポジトリ・実働環境とも」） | 自動（ls） | PASS（3項目） |
| TEST-03.1-03 | SPEC-03.1-03 | execution-steps.md に `$AGENT_PATH`・`agents/` が 0 件（fail 基準）/ Haiku fallback に `task-instruction` あり / CASPER 用 `CLAUDE_RULES` あり | 自動（grep） | PASS（4項目） |
| TEST-03.1-04 | SPEC-03.1-04 | `bash scripts/` 相対参照なし（ollama-check 二段フォールバック一段目は対象外の境界条件）/ `bash "$HOME/.claude/scripts/` 形式がちょうど 3 箇所 | 自動（grep） | PASS（2項目） |
| TEST-03.1-05 | SPEC-03.1-04 | 別プロジェクト cwd からの完走（差分検出 → filter → split → **Ollama モデル実呼び出し**まで） | 手動 E2E | PASS（2026-07-14 スクリプト解決検証 + **2026-07-16 フル E2E**: 一時 git repo から qwen2.5-coder:7b 呼び出しまで完走、モデルが注入バグを正しく検出。監査 A-005 対応） |
| TEST-03.1-06 | SPEC-03.1-05 | `setup/800-ollama-models.sh` 不存在 / `setup/401-ollama.sh` に言及なし（fail 基準）/ `setup/setup.sh` から参照なし（fail 基準） | 自動（ls + grep） | PASS（3項目） |
| TEST-03.1-07 | SPEC-03.1-06 | LELIEL=`llama3.1:8b`・METATRON=`granite3.3:8b`（2026-07-16 改訂仕様の現状値） | 自動（grep） | PASS（2項目） |
| TEST-03.1-08 | SPEC-03.1-07 | `setup/850-codex.sh` が作成コミット（#255 / f1f5aef）以降変更されていない | 自動（git log） | PASS（1項目） |
| TEST-03.1-09 | （Step 7 保留の引き継ぎ） | live `~/.claude/scripts/` と repo `scripts/` の同一性（magi-diff-filter / magi-split-hunk / magi-impact-context / ollama-check / ollama-run の 5 本を cmp） | 自動（cmp） | PASS（5項目） |

## 実行記録

- **実行日**: 2026-07-16（Step 8。全 IMPL 実装済みのため設計と同時に実行）
- **結果**: 自動 21 項目 + 手動流用 2 項目（TEST-03.1-05 の成功/失敗条件）= 全 PASS
- **実行方法**: 各観点を bash ワンライナー（grep / ls / cmp / git log）で連続実行。ログ要点:
  - agents/ 参照・AGENT_PATH: 0 件
  - 絶対パス `bash "$HOME/.claude/scripts/`: execution-steps.md L153/L186 + magi-hard/SKILL.md L134 の 3 箇所
  - live/repo スクリプト 5 本: バイト一致（cmp）
- **備考**: 初回実行時 T04b（絶対パス 3 箇所）が FAIL 表示になったが、テストハーネス側の
  シェルクォートバグ（eval 内の `\$HOME` エスケープ）で、直接 grep で 3 箇所を確認し PASS と判定

## 未テスト仕様

なし（全 SPEC にテスト観点を設定し実行済み）。ただし以下は本 core のテスト範囲外:

- OLLAMA_HOST 疎通・モデル存在確認 → core-03.3（setup readiness）のテスト範囲
- #289 sink/legacy mode の後方互換 → MAGI-HARD トリアージ再設計 Epic で E2E 済み（design-review 指摘 4 参照）

## CI 候補（将来）

- TEST-03.1-01/03/04/06 の grep 検査は環境非依存のため CI 化可能（core-03.4 継続保証のスコープで検討）
- TEST-03.1-09（live/repo 同一性）は実働環境依存のため CI 不可。core-02 の sync-check 運用でカバー
