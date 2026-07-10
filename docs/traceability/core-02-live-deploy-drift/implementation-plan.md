# Implementation Plan: Core 02 — 実働環境で生まれた開発内容の還流経路が未定義

> ステータス: approved（2026-07-07 人間確認済み）
> 対応 specification: approved（2026-07-07）

## 前提確認

| 項目 | 現状 |
|---|---|
| `~/.claude/.git/` | 存在する（de-git 未実施） |
| `scripts/sync-whitelist.conf` | 未存在（新設） |
| `scripts/sync-known-deletions.conf` | 未存在（新設） |
| `skills/sync-check/` | 未存在（新設） |
| README.md 還流手順セクション | 未存在（追加） |
| `~/.claude/settings.json` の hooks | 変更しない（SPEC-02-07） |

---

## 実装項目一覧

| IMPL ID | 内容 | 対応 SPEC | 変更ファイル | 実行方法 | ステータス | 実装参照 |
|---|---|---|---|---|---|---|
| IMPL-02-01 | `scripts/sync-whitelist.conf` 新設（ホワイトリスト定義） | SPEC-02-02, SPEC-02-05 | `scripts/sync-whitelist.conf`（新規） | `/codegen` + `/commit` | ✅ done | commit 6955706 |
| IMPL-02-02 | `scripts/sync-known-deletions.conf` 新設（既知削除予定リスト） | SPEC-02-03 | `scripts/sync-known-deletions.conf`（新規） | `/codegen` + `/commit` | ✅ done | commit 6955706 |
| IMPL-02-03 | `scripts/sync-check.sh` 新設（還流検知スクリプト本体） | SPEC-02-03 | `scripts/sync-check.sh`（新規） | `/dev-flow` | 🔲 todo | — |
| IMPL-02-04 | `skills/sync-check/SKILL.md` 新設（スキルラッパー） | SPEC-02-03, SPEC-02-07 | `skills/sync-check/SKILL.md`（新規） | `/codegen` + `/commit` | 🔲 todo | — |
| IMPL-02-05 | `README.md` に「還流手順」セクション追加（de-git 手順含む） | SPEC-02-04, SPEC-02-01 | `README.md` | `/codegen` + `/commit` | 🔲 todo | — |

### 実装しない SPEC

| SPEC ID | 理由 |
|---|---|
| SPEC-02-05（除外保証） | IMPL-02-01 の whitelist 設計で担保される。追加実装なし |
| SPEC-02-06（配備ツール） | 本 core では実装しない（2026-07-07 確定）。将来必要になれば別 core |
| SPEC-02-07（hooks 非登録） | `settings.json` の hooks を触らないことで担保。追加実装なし |

---

## PR 分割

### PR-A: 設定ファイル新設（IMPL-02-01, IMPL-02-02）

**作業内容**:
- `scripts/sync-whitelist.conf` を新設（rsync include/exclude 形式）
- `scripts/sync-known-deletions.conf` を新設（初期内容: `agents/leliel.md`）

**実行方法**: `/codegen` + `/magi-fast` + `/commit` 直列（軽微な設定ファイル新設のため）

**依存関係**: なし（PR-B の前提）

**検証**:
- ファイルが存在し、コメントと include/exclude 形式が正しいこと
- include 対象（skills/, hooks/*.sh, hooks/lib/, agents/, dotfiles/, scripts/, rules/, commands/, templates/, CLAUDE.md）が全件記載されていること
- exclude 対象（settings.json, CLAUDE.local.md, projects/, memory/, sessions/, hooks/logs/, hooks/queue/, 等）が全件記載されていること
- SPEC-02-02 の内容物・ローカルデータ一覧と突合し、漏れがないこと

> **注意**: PR-A 単体では whitelist の実効性は検証不可。SPEC-02-05 の「settings.json が出力に現れない」保証は PR-B の検証で確認する

---

### PR-B: 還流検知スクリプト + スキルラッパー（IMPL-02-03, IMPL-02-04）

**作業内容**:
- `scripts/sync-check.sh` を新設
  - `sync-whitelist.conf` を読み込み include パスを抽出
  - `~/.claude/` と `~/srcs/Claude-StartUp/` を突合（`diff -rq` ベース）
  - カテゴリ別出力: 要還流（新規）/ 要還流（変更）/ 削除予定（既知）/ 同一（--verbose 時のみ）
  - `sync-known-deletions.conf` に載るファイルを「削除予定（既知）」に分類
  - 還流漏れあり → exit 1 / なし → exit 0
  - 実働環境パス・配布原本パスはデフォルト値を持ち、引数で上書き可能
- `skills/sync-check/SKILL.md` を新設（スキルラッパー）
  - `~/.claude/scripts/sync-check.sh` を呼ぶ手順を記述

**実行方法**: `/dev-flow`（スクリプトは shellcheck 対象 → CI で確認が必要なため）

**依存関係**: PR-A が merge 済みであること（sync-check.sh が whitelist を参照するため）

**検証（正常系）**:
- `shellcheck -S error scripts/sync-check.sh` が通ること
- 実働環境にのみ存在するスキル（code-review 等）が「要還流（新規）」に出ること
- `agents/leliel.md` が「削除予定（既知）」に出ること
- `settings.json` / `CLAUDE.local.md` が出力に現れないこと

**検証（fixture）**:
- 「片側のみ存在するファイル」「両側で差分があるファイル」「whitelist 配下に紛れ込む settings.json」を fixture として用意し、期待通りに分類されること

**検証（異常系）** — SPEC-02-03 fail 基準:
- `sync-whitelist.conf` が存在しない場合: fail（中断）し exit 1 以外が返ること
- 実働環境パスが存在しない場合: fail（中断）し exit 1 以外が返ること

---

### PR-C: README 還流手順（IMPL-02-05）

**作業内容**:
- `README.md` に「還流手順」セクションを追加
  - de-git 手順（SPEC-02-01: `rm -rf ~/.claude/.git/` の一回限り手動操作）
  - `/sync-check` の起動方法と出力の読み方
  - 各カテゴリの対処手順（新規 → cp + PR / 変更 → diff 確認 + PR / 削除予定 → 還流しない）
  - 還流推奨タイミング（開発者判断に委ねる）

**実行方法**: `/codegen` + `/magi-fast` + `/commit` 直列

**依存関係**: PR-A, PR-B が merge 済みであること（README が参照するスキル・スクリプトが存在する必要あり）

**検証**: README に手順が記載されており、スキル名・ファイルパスが正確であること

---

## 依存関係グラフ

```
PR-A（設定ファイル）
  └→ PR-B（sync-check スクリプト + スキル）
       └→ PR-C（README 還流手順）
```

---

## 実装前に決めるべきこと

| # | 事項 | 現状 |
|---|---|---|
| 1 | `sync-check.sh` の比較手段 | 仕様では `diff -rq` または `rsync --dry-run -av --checksum`。PR-B 着手時に選択（shellcheck 通過を優先） |
| 2 | `skills/sync-check/SKILL.md` の実行コマンド | `~/.claude/scripts/sync-check.sh` を直接呼び出す方式で実装 |
| 3 | `--verbose` オプションのデフォルト | SPEC-02-03 準拠: デフォルト非表示、`--verbose` 指定時に「同一」を表示 |
| 4 | whitelist パターン解釈（**PR-B 着手前に確定**） | `sync-whitelist.conf` は rsync include/exclude 形式だが、`diff -rq` で実装する場合は `/***` 展開と exclude 優先順位を `sync-check.sh` 内で解釈する必要がある。実装前に「どのパターンがどのディレクトリに対応するか」を明示する |
| 5 | `sync-check.sh` の初期デプロイ前提（**PR-B 着手前に確定**） | スクリプトは配布原本 `scripts/sync-check.sh` に置き、スキルから `~/.claude/scripts/sync-check.sh` を呼ぶ。**初回のみ手動コピーが必要**（または PR-B merge 後に手順書で案内）。README.md の還流手順（PR-C）にこのコピー手順を含めるか決める |

---

## de-git 実行タイミング（SPEC-02-01）

実装完了後にユーザーが手動で一回だけ実行する操作（PR には含まない）:

```bash
# 前提確認
ls ~/.claude/.git/   # 存在すること

# de-git 実行
rm -rf ~/.claude/.git/

# 事後確認
git -C ~/.claude status 2>&1 | grep "not a git repository"
```

> PR-C merge 後（README に手順が記載された後）に実行推奨。
>
> **リスク受容**: PR-C merge までの間、`~/.claude/.git/` が残り続け `git pull` 事故リスクが継続する。
> このリスクを受容したうえで PR-A → PR-B → PR-C を順次進める。
> 早期に de-git を実行したい場合は PR-A merge 後に実施しても構わない。

---

## 注意

- `scripts/sync-check.sh` は shellcheck 対象（PR-B の検証に含める）
- `~/.claude/settings.json` の hooks セクションは一切変更しない（SPEC-02-07）
- `settings.json` がスクリプト出力に現れないことを PR-B の手動確認で必ず確認する
- de-git（SPEC-02-01）はローカル環境への直接操作であり、PR 作業とは独立している
