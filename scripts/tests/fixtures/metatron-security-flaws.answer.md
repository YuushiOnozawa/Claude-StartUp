# METATRON Security Flaws Fixture Answer Key

## 目的
この fixture は、METATRON のセキュリティ観点で既知の脆弱性をどれだけ検出できるかを測定するための合成 diff である。
主用途は候補モデルの**比較**であり（`mistral:7b` / `deepseek-coder-v2:lite` / `ornith:latest` / Codex など）、絶対的な合否判定ではない。

## 使い方
`skills/magi-common/references/execution-steps.md` のステップ 2 と同じ組み立てで、METATRON 用の `system.txt` / `prompt.txt` を作る。

- `system.txt`: `skills/metatron/references/task-instruction.md`、`skills/metatron/references/review-criteria.md`、`skills/magi-common/references/output-format.md`
- `prompt.txt`: `skills/magi-common/references/task-base.md` の後に `<TASK>` / `</TASK>` で包んだ `scripts/tests/fixtures/metatron-security-flaws.diff`

```bash
MAGI_TMPDIR=$(mktemp -d)
# 上記の構成で "$MAGI_TMPDIR/system.txt" と "$MAGI_TMPDIR/prompt.txt" を作成する
bash scripts/ollama-run.sh mistral:7b "$MAGI_TMPDIR/system.txt" < "$MAGI_TMPDIR/prompt.txt"
```

## 正解キー表
| ID | 仕込んだ欠陥の説明 | diff 内の位置（新ファイル側） | review-criteria の観点 | 期待される重大度 |
| --- | --- | --- | --- | --- |
| S1 | `_artifact_sync_find_candidates` が外部入力の `pattern` を `sh -c "..."` 相当のコマンド文字列へ未クォートで埋め込んでいる。 | `scripts/lib/artifact-sync.sh:37` | Injection | HIGH |
| S2 | `_artifact_sync_read_named_manifest` が caller supplied の `artifact_name` をベースディレクトリへ直接連結し、`../` の正規化や検証なしで読み込んでいる。 | `scripts/lib/artifact-sync.sh:48` | Injection | HIGH |
| S3 | `_artifact_sync_log_download_command` が変数由来の認証トークンを含む curl コマンド文字列をログへ追記している。 | `scripts/lib/artifact-sync.sh:71` | Secret leakage | HIGH |
| S4 | `_artifact_sync_verify_md5` がダウンロード済み artifact の完全性検証に `md5sum` を使っている。 | `scripts/lib/artifact-sync.sh:92` | Weak cryptography | MEDIUM |
| S5 | `_artifact_sync_follow_metadata_link` が外部取得した JSON から `next_fetch_url` を取り出し、URL の検証なしで次の fetch 先として使っている。 | `scripts/lib/artifact-sync.sh:103` | Insufficient input validation | MEDIUM |

## 採点基準
- recall: S1〜S5 のうち何件を検出できたか。検出と認めるには `filepath` が `scripts/lib/artifact-sync.sh` と一致していること。
- 捏造: diff に存在しないシンボル・値・ファイルを根拠にしていないこと。
- 重大度: S1 を HIGH と判定できたこと。
- 形式: `### [SEVERITY] filepath:line — headline` に従っていること。

## 合格条件
- S1 を HIGH で検出している。
- 5 件中 3 件以上を検出している（BALTHASAR fixture で全モデル最高が 3/5 だったため、同じ水準に揃える）。
- 捏造がない。
- 指定の出力形式に従っている。

いずれの候補も満たさない場合は METATRON を Codex に確定する。
