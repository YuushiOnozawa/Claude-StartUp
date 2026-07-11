# Specification: Core 02 — 実働環境で生まれた開発内容の還流経路が未定義

> ステータス: approved（2026-07-07 人間確認済み）
> 補足追記 2026-07-11: SPEC-02-03 処理アルゴリズム・終了コード表を実装確定内容で明確化（design-review DR-02-02/03・audit A-004 反映。ユーザー承認済み）

## 現状確認（2026-07-07）

- `~/.claude/.git/` は存在する（de-git 未実施）
- 実働環境にのみ存在するスキル: `code-review`, `investigate`, `lean-ctx`, `skill-creator`（還流漏れの実例）
- 配布原本にのみ存在するスキル: なし
- `~/.claude/.git/` は `git pull` 事故リスクあり

## SPEC-02-01: de-git — ~/.claude から git 管理を除去する

> REQ-02-01 対応

### 振る舞い

| 項目 | 内容 |
|---|---|
| 操作 | `rm -rf ~/.claude/.git/` を一度だけ手動実行する |
| 事前条件 | `~/.claude/.git/` が存在する |
| 事後条件 | `~/.claude/.git/` が存在しない / `git -C ~/.claude status` が "not a git repository" を返す |
| ファイル影響 | `~/.claude/.git/` 以外のファイルは変更しない。全スキル・フック・設定はそのまま残る |
| 実行タイミング | 一回限りの手動操作（新規環境には `.git/` が存在しないため不要） |

### fail / warn / info

| 状態 | 判定 | 備考 |
|---|---|---|
| de-git 後に `~/.claude/.git/` が存在する | fail | 手順失敗 |
| `~/.claude/` 配下の対象ファイルが消えた | fail | rm の対象に誤りあり |
| de-git 完了 | success | `git -C ~/.claude status` で確認 |

### 境界条件

- CLAUDE.local.md の「~/.claude/ 既存ファイルへの直接編集禁止」は `.git/` ディレクトリの削除には適用されない（`.git/` はファイルではなくgit内部データ）
- de-git 後も `~/.claude/.claudeignore`、`.gitignore` 等のドットファイルはそのまま残す

---

## SPEC-02-02: ホワイトリスト定義ファイル

> REQ-02-02, REQ-02-05, REQ-02-06 対応

### 定義ファイル

- パス: `scripts/sync-whitelist.conf`（配布原本に収録）
- 形式: rsync の `--include-from` / `--exclude-from` 形式。`+` で include、`-` で exclude、`#` でコメント

### 内容物（還流検知・配備の対象）

```
# 内容物（配布原本に収載されるべきもの）
+ /skills/***
+ /hooks/*.sh
+ /hooks/lib/***
+ /agents/***
+ /dotfiles/***
+ /scripts/***
+ /rules/***
+ /commands/***
+ /templates/***
+ /CLAUDE.md
```

### ローカルデータ（対象外）

```
# ローカルデータ（対象外）
- /settings.json
- /settings.local.json
- /CLAUDE.local.md
- /projects/***
- /paste-cache/***
- /hooks/logs/***
- /hooks/queue/***
- /tasks/***
- /memory/***
- /sessions/***
- /history.jsonl
- /shell-snapshots/***
- /session-env/***
- /telemetry/***
- /backups/***
- /file-history/***
- /cache/***
- /plans/***
- /.git/***
- /*.bak
# 上記以外はすべて除外（デフォルト除外）
- /***
```

### 境界条件

- `hooks/logs/`・`hooks/queue/` は除外。`hooks/*.sh` と `hooks/lib/` のみ含める
- `memory/` は REQ-02-06 の「等」に含まれるローカルデータとして明示除外
- `agents/leliel.md` は include 対象だが、還流検知で「削除予定」として扱う（SPEC-02-03 参照）

---

## SPEC-02-03: 還流検知スクリプト

> REQ-02-03, REQ-02-08 対応

### 入出力

| 項目 | 内容 |
|---|---|
| 入力 | 実働環境パス（デフォルト: `~/.claude/`）・配布原本パス（デフォルト: `~/srcs/Claude-StartUp/`）・`sync-whitelist.conf` |
| 出力 | 標準出力にカテゴリ別ファイル一覧 |
| 起動方法 | 手動スキル呼び出しのみ（hooks からの自動起動なし） |

### 出力フォーマット

```
=== 要還流（新規）: 実働環境にのみ存在 ===
  skills/code-review/
  skills/investigate/
  skills/lean-ctx/
  skills/skill-creator/

=== 要還流（変更）: 両側に存在するが差分あり ===
  CLAUDE.md

=== 削除予定（既知）: 還流しない ===
  agents/leliel.md  [core-03.1 REQ-03.1-02 で削除予定]

=== 同一 ===
  （--verbose 指定時のみ表示）
```

### 処理アルゴリズム

1. `sync-whitelist.conf` の `+ ` プレフィックス行のみを読み、include パスとして処理する。`- ` exclude 行はスクリプトが参照しない（exclude 行は rsync 配備ツール（SPEC-02-06）用の文書として存在）
2. 各 include パスについて `diff -rq` で比較する
3. **比較は実働環境 → 配布原本の一方向のみ**: 実働環境に存在するファイルが配布原本に存在しない場合のみ「要還流（新規）」として出力する。配布原本にのみ存在するファイルは出力しない
4. カテゴリ（新規/変更/同一）に分類して出力
5. `known-deletions.conf`（後述）に載っているファイルは「削除予定（既知）」カテゴリで別出力する。**適用範囲: 実働環境のみに存在する（新規）ファイルにのみ適用**。両側に存在して差分があるファイルは known-deletions に記載されていても「要還流（変更）」として出力する（監査 A-004）

### 既知削除予定リスト

- 管理ファイル: `scripts/sync-known-deletions.conf`（配布原本に収録）
- 形式: 1行1ファイルのパスリスト（`~/.claude/` からの相対パス）
- 初期内容: `agents/leliel.md`（core-03.1 REQ-03.1-02 で削除予定）

### fail / warn / info（スクリプト実行時）

| 状態 | 判定 | 終了コード |
|---|---|---|
| `sync-whitelist.conf` が存在しない | fail（中断） | exit 2 |
| 実働環境パスが存在しない | fail（中断） | exit 2 |
| 「要還流（新規）」または「要還流（変更）」が1件以上ある | warn（還流漏れあり） | exit 1 |
| 「要還流」が0件 | success | exit 0 |

> `exit 2` を設定エラー専用とし、`exit 1`（要還流あり）と区別する

### スキル名

**`/sync-check`**（2026-07-07 確定）

---

## SPEC-02-04: 還流手順の文書化とスキル化

> REQ-02-04 対応

### README への記載内容

配布原本の README.md に「還流手順」セクションを追加する。記載内容:

1. 還流検知の起動方法（スキル名）と出力の読み方
2. 「要還流（新規）」の対処: 配布原本でブランチ作成 → `cp -r ~/.claude/<path> ~/srcs/Claude-StartUp/<path>` → PR 作成
3. 「要還流（変更）」の対処: `diff ~/.claude/<path> ~/srcs/Claude-StartUp/<path>` で確認 → 有益な変更のみ PR へ
4. 「削除予定（既知）」の対処: 還流しない（対応 core の impl で削除される）
5. 還流推奨タイミング: 任意（開発者の判断に委ねる。REQ-02-08）

### スキル化の範囲（本 core の範囲）

- 還流検知スクリプト（SPEC-02-03）のスキルラッパーを作成する
- 還流 PR の自動作成は **対象外**（PR 化は手動。PR 内容が毎回異なるため）

---

## SPEC-02-05: settings.json とローカルデータの除外保証

> REQ-02-05, REQ-02-06 対応

- `sync-whitelist.conf` に settings.json・ローカルデータが exclude として明示される（SPEC-02-02）
- 還流検知スクリプトの出力に settings.json が現れない
- 配備ツール（任意、SPEC-02-06）実行後も settings.json が変化しない

---

## SPEC-02-06: 配備ツールの実装指針（任意）

> REQ-02-07 対応

### 実装する場合の仕様

| 項目 | 内容 |
|---|---|
| 方式 | `rsync -av --checksum --include-from=sync-whitelist.conf --exclude='*' ~/.claude/ ~/srcs/Claude-StartUp/` に相当 |
| 使用ホワイトリスト | SPEC-02-02 と同一の `sync-whitelist.conf` |
| 実行前確認 | dry-run 出力をユーザーに提示し、確認を取ってから実行 |
| settings.json | 変更しない（whitelist に含まれないため） |
| 実行方向 | 配布原本 → 実働環境（新規環境セットアップ等に使用） |

### 実装判断

- **本 core では実装しない**（2026-07-07 確定）
- 还流方向（実働環境 → 配布原本）が先決。配備ツールは後回し
- 将来実装が必要になった場合は別 core または別 PR として扱う

---

## SPEC-02-07: 手動スキルのみの保証

> REQ-02-08 対応

- 還流検知スクリプトは `~/.claude/settings.json` の `hooks` セクションに登録しない
- `SessionStart`・`SessionEnd`・`PostToolUse` からの自動起動を行わない
- ユーザーが明示的にスキルを呼んだときのみ動作する

---

## 確定した仕様上の決定（2026-07-07）

| # | 事項 | 決定 |
|---|---|---|
| 1 | 還流検知スキルの名前 | `/sync-check` |
| 2 | de-git の新規環境での扱い | 新規環境には `.git/` がないため不要。現環境のみ手動一回実行（SPEC-02-01） |
| 3 | 配備ツールを本 core で実装するか | **実装しない**。還流方向（実働→配布）を先決とする |
| 4 | `sync-whitelist.conf` の形式 | rsync include/exclude 形式（impl 時に詳細確定） |

## 未確定事項

なし（全件 2026-07-07 確定）

---

## 自動化対象と手動確認対象

| 操作 | 区分 | 備考 |
|---|---|---|
| de-git（rm -rf ~/.claude/.git/） | 手動一回限り | 現環境への操作 |
| 還流検知の実行 | 手動スキル | REQ-02-08 |
| 「要還流」ファイルの PR 化 | 手動 | ファイル内容の判断が必要 |
| 「削除予定（既知）」の確認 | 自動（検知時に表示） | |
| 配備ツール（任意）の実行 | 手動（dry-run 確認後） | |
