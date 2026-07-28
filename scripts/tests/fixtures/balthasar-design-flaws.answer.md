# BALTHASAR Design Flaws Fixture Answer Key

## 目的

この fixture は、ローカル LLM（`llama3.1:8b` / `gemma4:e4b-it-qat`）が BALTHASAR の設計・アーキテクチャ観点で既知の設計欠陥をどれだけ検出できるかを測定するための合成 diff である。

## 使い方

`skills/magi-common/references/execution-steps.md` のステップ 2 と同じ組み立てで、BALTHASAR 用の `system.txt` / `prompt.txt` を作る。

- `system.txt`: `skills/balthasar/references/task-instruction.md`、`skills/balthasar/references/review-criteria.md`、`skills/magi-common/references/output-format.md`
- `prompt.txt`: `skills/magi-common/references/task-base.md` の後に `<TASK>` として `scripts/tests/fixtures/balthasar-design-flaws.diff`

実行例:

```bash
MAGI_TMPDIR=$(mktemp -d)
# 上記の構成で "$MAGI_TMPDIR/system.txt" と "$MAGI_TMPDIR/prompt.txt" を作成する
bash scripts/ollama-run.sh llama3.1:8b "$MAGI_TMPDIR/system.txt" < "$MAGI_TMPDIR/prompt.txt"
```

## 正解キー

| ID | 仕込んだ欠陥の説明 | diff 内の位置（新ファイル側） | review-criteria の観点 | 期待される重大度 |
|---|---|---|---|---|
| D1 | `post_review_comment` が既存 caller の旧引数順（`queue_file, session_id, body_file, dry_run`）を残したまま、実質シグネチャを `body_file, queue_file, dry_run` に変更している。 | `scripts/lib/review-digest.sh:25` | Backward compatibility | HIGH |
| D2 | `publish_review_digest` が設定ファイル読み込み、リモート取得、Markdown 整形、投稿を 1 関数で担っている。 | `scripts/lib/review-digest.sh:39` | Separation of concerns | HIGH |
| D3 | 下位ユーティリティである `scripts/lib/review-digest.sh` が、上位ワークフローの `scripts/review-digest-publish.sh` を `source` して変数を再利用している。 | `scripts/lib/review-digest.sh:8` | Dependency direction | HIGH |
| D4 | 高レベルの `run_review_digest_publish` 内に `sed -E` / `awk -F` / `sort` の低レベル TSV 処理が直書きされている。 | `scripts/lib/review-digest.sh:76` | Abstraction level | MEDIUM |
| D5 | `wrap_digest_once`、`wrap_digest_twice`、`wrap_digest_for_publish` が実質 1 行処理を包むだけの 3 段ラッパーになっている。 | `scripts/lib/review-digest.sh:100` | Excessive complexity | MEDIUM |

## 採点基準

- recall: D1〜D5 のうち何件を検出できたか。検出と認めるには `filepath` が一致していること。
- 捏造: diff に存在しないシンボル・値・ファイルを根拠にしていないこと。
- 重大度: D1 を HIGH と判定できたこと。
- 形式: `### [SEVERITY] filepath:line — headline` に従っていること。

## `llama3.1:8b` 合格条件

- D1 を HIGH で検出している。
- 5 件中 3 件以上を検出している。
- 捏造がゼロである。
- `gemma4:e4b-it-qat` の検出数との差が 1 件以内である。
