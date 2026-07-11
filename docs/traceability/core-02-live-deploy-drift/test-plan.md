# Test Plan: Core 02 — 実働環境で生まれた開発内容の還流経路が未定義

> ステータス: approved（2026-07-11 人間確認済み）
> 前回の draft（旧 core-05 版）は前提変更（2026-07-07）により全面改訂

## テスト結果サマリー（2026-07-11）

| SPEC | テスト観点数 | 自動 | verify | CI | 手動 | 結果 |
|---|---|---|---|---|---|---|
| SPEC-02-01（de-git） | 2 | 0 | 0 | 0 | 2 | **PENDING**（手動操作未実施） |
| SPEC-02-02（whitelist） | 3 | 1 | 2 | 0 | 0 | **PASS** |
| SPEC-02-03（sync-check.sh） | 11 | 9 | 1 | 1 | 0 | **9 PASS / 0 FAIL / 1 SKIP** |
| SPEC-02-04（手順文書化） | 2 | 1 | 1 | 0 | 0 | **PASS** |
| SPEC-02-05（除外保証） | 0 | — | — | — | — | SPEC-02-02/03 で担保 |
| SPEC-02-06（配備ツール） | 0 | — | — | — | — | 未実装（対象外） |
| SPEC-02-07（手動スキルのみ） | 1 | 0 | 1 | 0 | 0 | **PASS** |

---

## SPEC-02-01: de-git（手動確認）

| TEST ID | 内容 | 区分 | 結果 | 備考 |
|---|---|---|---|---|
| TEST-02-01-01 | `~/.claude/.git/` が存在しない | 手動確認 | **PENDING** | 2026-07-11 時点: `~/.claude/.git/` が存在（de-git 未実施）。PR #280 merge 後に手動実行推奨 |
| TEST-02-01-02 | `git -C ~/.claude status` が "not a git repository" を返す | 手動確認 | **PENDING** | TEST-02-01-01 実施後に確認 |

> de-git は実環境への破壊的一回限り操作のため自動化不可。SPEC-02-01 の境界条件「新規環境には .git/ がないため不要」のため、新規環境でのテストは不要

---

## SPEC-02-02: ホワイトリスト定義ファイル

| TEST ID | 内容 | 区分 | 結果 |
|---|---|---|---|
| TEST-02-02-01 | `scripts/sync-whitelist.conf` が存在する | 自動テスト（`ls` 確認） | **PASS**（2026-07-11） |
| TEST-02-02-02 | include 対象（skills/, hooks/*.sh, hooks/lib/, agents/, dotfiles/, scripts/, rules/, commands/, templates/, CLAUDE.md）が全件記載されている | verify（`grep "^+ "` 確認） | **PASS**（2026-07-11、10項目全件確認） |
| TEST-02-02-03 | exclude 対象（settings.json, settings.local.json, CLAUDE.local.md 等）が明示されている | verify（`grep "^- "` 確認） | **PASS**（2026-07-11） |

### テスト実行コマンド

```bash
ls scripts/sync-whitelist.conf scripts/sync-known-deletions.conf
grep "^+ " scripts/sync-whitelist.conf
grep "^- /settings" scripts/sync-whitelist.conf
```

---

## SPEC-02-03: 還流検知スクリプト

既存テストスクリプト `scripts/test-sync-check.sh` を流用。

### 実行結果（2026-07-11）

```
SKIP: shellcheck -S error が通る (shellcheck not installed)
PASS: bash -n が通る
PASS: 実働環境のみにあるファイルを新規として検出
PASS: 両側で異なるファイルを変更として検出
PASS: 既知削除予定を通常の還流対象から除外
PASS: 同一ファイルは --verbose 時だけ表示
PASS: settings.json と CLAUDE.local.md を除外
PASS: whitelist がない場合は exit 2
PASS: 実働環境パスがない場合は exit 2
PASS: known-deletions がなくても正常終了

Results: 9 PASS / 0 FAIL / 1 SKIP
```

### TEST 一覧

| TEST ID | 内容 | 区分 | 結果 |
|---|---|---|---|
| TEST-02-03-01 | `shellcheck -S error scripts/sync-check.sh` が通る | CI | **SKIP**（shellcheck 未インストール。CI 環境では実行推奨） |
| TEST-02-03-02 | `bash -n scripts/sync-check.sh` が通る（構文チェック） | 自動テスト | **PASS** |
| TEST-02-03-03 | 実働環境のみ存在するファイルが「要還流（新規）」に分類される（exit 1） | 自動テスト（fixture） | **PASS** |
| TEST-02-03-04 | 両側に存在して差分あるファイルが「要還流（変更）」に分類される（exit 1） | 自動テスト（fixture） | **PASS** |
| TEST-02-03-05 | known-deletions に記載のファイルが「削除予定（既知）」に分類され exit 0 になる | 自動テスト（fixture） | **PASS** |
| TEST-02-03-06 | 同一ファイルはデフォルト非表示、`--verbose` 時のみ「同一」に表示される | 自動テスト（fixture） | **PASS** |
| TEST-02-03-07 | `settings.json` / `CLAUDE.local.md` が出力に現れない（exclude 保証） | 自動テスト（fixture） | **PASS** |
| TEST-02-03-08 | `sync-whitelist.conf` 不存在 → exit 2 で中断 | 自動テスト（異常系） | **PASS** |
| TEST-02-03-09 | 実働環境パス不存在 → exit 2 で中断 | 自動テスト（異常系） | **PASS** |
| TEST-02-03-10 | `sync-known-deletions.conf` 不存在でも正常終了（warning 出力） | 自動テスト | **PASS** |
| TEST-02-03-11 | 実環境（`~/.claude/` vs `~/srcs/Claude-StartUp/`）で実行し、還流漏れスキルが出力される | verify（手動） | **未実施**（手動実行で確認推奨） |

---

## SPEC-02-04: 還流手順の文書化

| TEST ID | 内容 | 区分 | 結果 |
|---|---|---|---|
| TEST-02-04-01 | `README.md` に「還流手順」セクション（行 65）が存在する | 自動テスト（`grep`） | **PASS**（2026-07-11） |
| TEST-02-04-02 | `/sync-check` 起動方法・各カテゴリ対処手順・スキル名・ファイルパスが正確に記載されている | 手動確認 | 手動確認要（PR #280 で実装済み） |

### テスト実行コマンド

```bash
grep -n "還流手順" README.md
```

---

## SPEC-02-05: settings.json とローカルデータの除外保証

TEST-02-02-03（whitelist の exclude 記載）と TEST-02-03-07（fixture による動作確認）で担保済み。追加テストなし。

---

## SPEC-02-06: 配備ツール（実装しない）

本 core では実装しない（2026-07-07 確定）。テスト対象外。

---

## SPEC-02-07: 手動スキルのみの保証

| TEST ID | 内容 | 区分 | 結果 |
|---|---|---|---|
| TEST-02-07-01 | `~/.claude/settings.json` の `hooks` セクションに `sync-check` の登録がない | verify（`grep` 確認） | **PASS**（2026-07-11） |

### テスト実行コマンド

```bash
grep -r "sync-check" ~/.claude/settings.json && echo "FAIL" || echo "PASS"
```

---

## 未テスト・手動確認が残る項目

| SPEC | TEST ID | 内容 | 理由 |
|---|---|---|---|
| SPEC-02-01 | TEST-02-01-01/02 | de-git 実施の確認 | 破壊的一回限り操作のため自動化不可。ユーザーが手動実施 |
| SPEC-02-03 | TEST-02-03-01 | shellcheck -S error | shellcheck 未インストール（CI 環境推奨） |
| SPEC-02-03 | TEST-02-03-11 | 実環境での実行確認 | 実環境（~/.claude）での手動実行が必要 |
| SPEC-02-04 | TEST-02-04-02 | README 内容の正確性確認 | 内容の妥当性判断は人間確認が必要 |

---

## CI との連携

以下を CI に追加することを推奨（現時点では未設定）:

1. `shellcheck -S error scripts/sync-check.sh`（shellcheck インストール前提）
2. `bash scripts/test-sync-check.sh`（全 fixture テスト）
3. `ls scripts/sync-whitelist.conf scripts/sync-known-deletions.conf`（設定ファイル存在確認）

---

## テスト実行方法

```bash
# 自動テスト一括実行
bash scripts/test-sync-check.sh

# verify 項目（手動）
ls scripts/sync-whitelist.conf
grep "^+ " scripts/sync-whitelist.conf
grep -n "還流手順" README.md
grep -r "sync-check" ~/.claude/settings.json && echo "FAIL" || echo "PASS"

# de-git 確認（手動・実施後）
ls ~/.claude/.git/ &>/dev/null && echo "PENDING" || echo "PASS"
git -C ~/.claude status 2>&1 | grep "not a git repository"
```
