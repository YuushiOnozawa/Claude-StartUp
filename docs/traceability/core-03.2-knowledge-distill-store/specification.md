# Specification: Core 03.2 — hooks / knowledge-distill / 知識ストアの二重化・欠落・密結合

> ステータス: approved（2026-07-08 SPEC-03.2-05 追補・人間承認済み）
> 対応 requirements: approved（2026-07-07）

## 現状確認（2026-07-07）

| 項目 | 現状 |
|---|---|
| `setup/410` の SessionEnd 登録 | `knowledge-distill.sh` を SessionEnd に直接登録（queue push と二重実行） |
| `setup/410` の log path | `2>> hooks/knowledge-distill.log`（`hooks/logs/` 不一致） |
| `setup/411` / `setup/412` | `knowledge-prune.sh`（SessionStart）・`check-queue.sh`（UserPromptSubmit）登録。log path は正しく `hooks/logs/` |
| `session-end-queue.sh` | SessionEnd queue push のみ担う。setup の明示的な登録スクリプトは確認対象（IMPL で確認） |
| `knowledge-distill.sh` OUTPUT_DIR | `$HOME/pcloud/obsidian/sessions`（pCloud マウント前提） |
| `knowledge-distill.sh` drain 条件 | pCloud mount が前提条件に混在（L23 `mountpoint -q "$HOME/pcloud"` で drain を囲む） |
| `knowledge-distill.sh` pCloud ガード | pCloud 未マウント → pcloud キューへ push して exit 0（記録・登録もスキップ） |
| `knowledge-distill-extract.sh`・`knowledge-distill-raw.sh` | OUTPUT_DIR を引数で受け取る（本体変更不要） |
| `knowledge-auto-promote.sh` | pCloud 未マウント → exit 0 でスキップ（元々 graceful。配送層に位置付ける） |
| `check-queue.sh` | UserPromptSubmit 時に pCloud マウント確認 + queue 件数に応じて `knowledge-distill.sh` を起動。本 SPEC の対象外 |
| `lib/logging.sh` | `HOOK_LOG_DIR="${HOME}/.claude/hooks/logs"` を正しく定義済み |
| `hooks/error-detector.sh` | `~/.claude/hooks/` にのみ存在。リポジトリ `hooks/` に未追加・setup スクリプトなし |

---

## SPEC-03.2-01: `setup/410` の SessionEnd 登録を queue push 参照のみに変更し、SessionStart へ移行する

> REQ-03.2-01 対応

### 振る舞い

**`setup/410` の変更:**

| 操作 | 内容 |
|---|---|
| 削除 | `knowledge-distill.sh` を SessionEnd に追加する jq ブロックを削除する |
| 追加 | 既存の SessionEnd エントリから `knowledge-distill.sh` を除去するクリーンアップ処理を追加する（べき等性） |
| 追加 | `knowledge-distill.sh` を SessionStart に登録する jq ブロックを追加する（`setup/411` の `knowledge-prune.sh` 登録と同形式） |

SessionStart 登録コマンド形式（SPEC-03.2-02 のログパス修正と同時適用）:

```bash
"bash ${HOME}/.claude/hooks/knowledge-distill.sh 2>> ${HOME}/.claude/hooks/logs/knowledge-distill.log"
```

**`session-end-queue.sh` の SessionEnd 登録保証:**

`session-end-queue.sh` が SessionEnd に未登録の場合、`setup/412`（または確認済みの既存スクリプト）が jq 動的注入で登録する。
登録責務の確認は実装前（impl-plan 着手前）に行い、SPEC-03.2-01 の変更と一本化する。

> `settings.json` は runtime 文書（core-02 REQ-02-05 approved）。本変更は jq 動的注入で行い、リポジトリの `settings.json` を直接編集しない。

### 事後条件

- `settings.json` の SessionEnd に `knowledge-distill.sh` の直接実行エントリが存在しない
- `settings.json` の SessionStart に `knowledge-distill.sh` のエントリが存在する（重複なし）
- `settings.json` の SessionEnd に `session-end-queue.sh` のエントリが存在する（重複なし）
- 1 セッション分の transcript に対して `knowledge-distill.sh` は次セッション開始時に 1 回だけ実行される

### 検証方法（重複なし確認）

```bash
# SessionEnd に knowledge-distill.sh が残っていないこと
jq '.hooks.SessionEnd[].hooks[].command' ~/.claude/settings.json | grep knowledge-distill
# → 0 matches であること

# SessionStart に knowledge-distill.sh が 1 件のみあること
jq '.hooks.SessionStart[].hooks[].command' ~/.claude/settings.json | grep knowledge-distill
# → 1 行のみであること

# queue アイテム数でのセッション重複確認（手動）
ls ~/.claude/hooks/queue/knowledge-distill/pending/ | wc -l
# → 同一 transcript_path のアイテムが 2件以上ない
```

### fail / warn / info

| 状態 | 判定 |
|---|---|
| setup 実行後に SessionEnd に `knowledge-distill.sh` が残っている | fail |
| setup 実行後に SessionStart に `knowledge-distill.sh` が存在しない | fail |
| setup 実行後に SessionEnd に `session-end-queue.sh` が存在しない | fail |
| SessionStart または SessionEnd に同一コマンドが重複登録されている | fail |

### 境界条件

- 既存環境で SessionEnd に `knowledge-distill.sh` が登録済みの場合、クリーンアップ処理が実行される
- `setup/410` の idempotency：再実行しても重複登録しない（contains 確認の jq パターン維持）
- SPEC-03.2-02（log path 修正）は同一変更内に含める

---

## SPEC-03.2-02: hook ログ出力先を `hooks/logs/` 配下に統一する

> REQ-03.2-02 対応

### 振る舞い

`setup/410` 内の `knowledge-distill.sh` 登録コマンドのログリダイレクトパスを修正する:

| 変更前 | 変更後 |
|---|---|
| `2>> ${HOME}/.claude/hooks/knowledge-distill.log` | `2>> ${HOME}/.claude/hooks/logs/knowledge-distill.log` |

> SPEC-03.2-01 で SessionEnd → SessionStart への移行と同時に行うため、修正は新規の SessionStart 登録コマンド文字列に反映させる。

`setup/410` は `~/.claude/hooks/logs/` ディレクトリを `mkdir -p` で保証する処理を追加する（`lib/logging.sh` が実行時に mkdir するが、外部リダイレクトは hook 起動前にシェルが開くため、setup 段階での保証が必要）。

> 変更対象は `setup/410` が生成する登録コマンド文字列のみ。`knowledge-distill.sh` の内部ログ（`lib/logging.sh` 経由）・他 hook の登録コマンドは変更しない。

### 事後条件

- `setup/410` が生成するコマンド文字列に `hooks/knowledge-distill.log`（logs/ なし）が含まれない
- `~/.claude/hooks/logs/` が setup 後に存在する（`mkdir -p` で保証）
- `knowledge-distill.sh` が出力するすべてのログが `~/.claude/hooks/logs/` 配下に書き出される

### fail / warn / info

| 状態 | 判定 |
|---|---|
| `setup/410` のコマンド文字列に `hooks/knowledge-distill.log`（logs/ なし）が含まれる | fail |
| setup 実行後に `~/.claude/hooks/logs/` が存在しない | fail |

### 境界条件

- `lib/logging.sh` が `HOOK_LOG_DIR` を定義し `mkdir -p` を実行するため、実行時には問題が出ないが、外部リダイレクト（`2>>`）はシェルがスクリプト起動前に開く。setup の `mkdir -p` でカバーする
- `knowledge-distill.sh` 自体の内部ログは変更前から正しいパスに書いている

---

## SPEC-03.2-03: 記録層を pCloud 非依存にし、pCloud 同期を配送層として分離する

> REQ-03.2-03 対応

### 用語定義

| 層 | 役割 | pCloud 依存 |
|---|---|---|
| 記録層 | transcript → 蒸留 → ローカル保存 → knowledge-rag 登録 | なし（常に実行） |
| 配送層 | ローカル保存済みファイル → pCloud/Obsidian へコピー（auto-promote 含む） | あり（マウント時のみ） |

### ローカルステージングパス

```
LOCAL_STAGING_DIR="$HOME/.local/share/knowledge-rag/sessions"
```

### `knowledge-distill.sh` の変更

| 変更箇所 | 変更内容 |
|---|---|
| 冒頭の pCloud マウント確認ブロック（L94-104: queue push して exit 0） | 削除する（pCloud 未マウントでも記録・登録を継続する） |
| drain 条件（L23: `mountpoint -q "$HOME/pcloud"` で drain を囲む） | pCloud mount 条件を除去する。`pending` は常時 drain、`ollama` は Ollama 起動時のみ drain |
| `OUTPUT_DIR` の定義 | `$HOME/pcloud/obsidian/sessions` → `$HOME/.local/share/knowledge-rag/sessions` |
| `mkdir -p "$OUTPUT_DIR"` | LOCAL_STAGING_DIR に対して実行（pCloud 依存なし） |
| pCloud 配送処理 | **なし**（2026-07-08 確定）。ローカル保存完了で `knowledge-distill.sh` の責務は終わる。pCloud への転送は `scripts/pcloud-sync.sh`（core-01 impl で新設）が一括担当する。FUSE 直書き禁止（SPEC-01-03 不変条件優先） |
| `pcloud` キューへの push | 削除する（pcloud-sync.sh に委任するため不要） |

### `pcloud` キューの移行方針

既存の `pcloud` reason アイテムは `pending` として再処理する:

- `knowledge-distill.sh` の `queue_drain "knowledge-distill" "pcloud"` コールバックを変更し、`pcloud` → `pending` へアイテムを移動する
- 移行完了後は `pcloud` reason のコールバックを削除する
- 移行手順（手動確認）は impl-plan に記載する

### `knowledge-auto-promote.sh` の扱い（配送層）

`knowledge-auto-promote.sh` は **配送層** として扱う:
- `KNOWLEDGE_DIR="$HOME/pcloud/obsidian/knowledge"`（変更なし）
- pCloud 未マウント時: 既存の exit 0 スキップ維持（配送スキップ = fail でない）
- 呼び出し元（`knowledge-distill.sh`）の `OUTPUT_FILE` が LOCAL_STAGING_DIR 配下のパスになることを前提に動作確認のみ行う（スクリプト本体変更なし）

### `check-queue.sh` について

`check-queue.sh`（UserPromptSubmit hook）の pCloud マウント依存は本 SPEC の対象外。
UserPromptSubmit 経由の drain の pCloud 条件解除は後続課題とし、本 core では変更しない。

### 事後条件

- rclone/pCloud 未マウントの環境で `knowledge-distill.sh` が正常実行・終了する
- `~/.local/share/knowledge-rag/sessions/${DATE}-${TRANSCRIPT_BASE}-${PROJECT}.md` に蒸留済みファイルが保存される
- `~/.local/share/knowledge-rag/sessions/${DATE}-${TRANSCRIPT_BASE}-${PROJECT}-raw.md`（raw log）が保存される
- knowledge-rag へ登録される（LLM バイナリが利用可能な場合）
- pCloud への転送は `scripts/pcloud-sync.sh`（core-01 impl）が担当する。`knowledge-distill.sh` はローカル保存のみで完結する
- pCloud 未マウット・マウット問わず `pcloud` キューへの push なしで exit 0
- `pending`・`ollama` キューの drain は pCloud マウント状態によらず実行される

### 検証方法

```bash
# pCloud 未マウント環境での smoke test
# 事前: rclone が未起動であることを確認
mountpoint -q ~/pcloud && echo "mounted" || echo "not mounted"

# 手動実行（テスト用 transcript を入力）
echo '{"transcript_path":"/path/to/test.jsonl","cwd":"/tmp"}' \
  | bash ~/.claude/hooks/knowledge-distill.sh

# 確認: LOCAL_STAGING_DIR にファイルが存在する
ls ~/.local/share/knowledge-rag/sessions/

# 確認: knowledge-rag 登録の成功（STRICT=1 で確認）
echo '{"transcript_path":"/path/to/test.jsonl","cwd":"/tmp"}' \
  | KRAG_DISTILL_STRICT=1 bash ~/.claude/hooks/knowledge-distill.sh

# 確認: pcloud キューへの push がないこと
ls ~/.claude/hooks/queue/knowledge-distill/pcloud/ 2>/dev/null | wc -l
# → 0
```

### fail / warn / info

| 状態 | 判定 |
|---|---|
| rclone 未起動で `knowledge-distill.sh` が exit 0 以外で終了する | fail |
| LOCAL_STAGING_DIR にファイルが作成されない（知識あり・Ollama OK の場合） | fail |
| pCloud 未マウントでも `~/pcloud/` 配下に書き込もうとする | fail |
| `pending`・`ollama` drain が pCloud 未マウント時に実行されない | fail |
| pCloud 転送 | pcloud-sync.sh（core-01 impl）が担当。knowledge-distill.sh は判定しない |

### 境界条件

- `knowledge-distill-extract.sh`・`knowledge-distill-raw.sh` はパスを引数で受けるため本体変更不要
- `KRAG_DISTILL_RETRY=1` 時の `pcloud` キュー drain コールバックは、移行方針（pending 再処理）適用後に削除する
- `check-queue.sh` の pCloud 依存は変更しない（UserPromptSubmit drain は後続課題）
- `knowledge-auto-promote.sh` の本体変更なし（呼び出し元の OUTPUT_FILE パスが変わることの動作確認のみ）

---

## SPEC-03.2-04: `error-detector.sh` をリポジトリに追加し、setup で配備・登録する

> REQ-03.2-04 対応

### 振る舞い

**リポジトリへの追加:**

| 操作 | 内容 |
|---|---|
| 追加 | `~/.claude/hooks/error-detector.sh` の内容を `hooks/error-detector.sh` として `git add` する |
| 新設 | `setup/413-hooks-error-detector.sh` を独立ファイルとして新設する |

> コピー元: `~/.claude/hooks/error-detector.sh`（現在リポジトリに存在しない唯一の原本）

**`setup/413-hooks-error-detector.sh` の動作:**

1. `hooks/error-detector.sh` を `~/.claude/hooks/error-detector.sh` にコピーし `chmod +x`
2. `settings.json` の PostToolUse に `error-detector.sh` を jq 動的注入で登録する（contains 確認で重複排除）

登録コマンド形式（matcher なし — スクリプト内 TOOL_NAME フィルタに委ねる）:

```bash
"bash ${HOME}/.claude/hooks/error-detector.sh"
```

PostToolUse 登録形式（matcher なし）:

```json
.hooks.PostToolUse //= [] |
if (.hooks.PostToolUse | map(.hooks[]?.command // "") | any(contains("error-detector.sh"))) then .
else .hooks.PostToolUse += [{"hooks": [{"type": "command", "command": $cmd}]}]
end
```

> matcher の使用可否は未確定のため、本 SPEC ではスクリプト内の TOOL_NAME フィルタのみで Bash コマンドを絞り込む実装とする。matcher の導入可否は未確定事項 #1 を参照。

**`setup.sh` への組み込み:**

`setup.sh` が `setup/413-hooks-error-detector.sh` を source する行を追加する。

### 事後条件

- `hooks/error-detector.sh` がリポジトリに存在する（`git ls-files hooks/error-detector.sh` でヒット）
- `setup.sh` 実行後に `~/.claude/hooks/error-detector.sh` が存在し、実行権限がある（`-x` フラグ）
- `settings.json` の PostToolUse に `error-detector.sh` のエントリが存在する
- Bash コマンドエラー発生時に `error-detector.sh` が呼ばれ、`.learnings/ERRORS.md` への記録を促す

### fail / warn / info

| 状態 | 判定 |
|---|---|
| `hooks/error-detector.sh` がリポジトリに存在しない | fail |
| setup 実行後に `~/.claude/hooks/error-detector.sh` が存在しない | fail |
| setup 実行後に `~/.claude/hooks/error-detector.sh` が実行可能でない（`-x` なし） | fail |
| setup 実行後に PostToolUse に `error-detector.sh` が登録されていない | fail |

### 境界条件

- git add 前に `~/.claude/hooks/error-detector.sh` の内容を確認してからコミットする
- `setup/413` は `setup/411`・`setup/412` と同形式（idempotency のための contains 確認）
- `setup.sh` が `413` を source する行の追加は、既存の `410-412` の source 行の直後に置く

---

## SPEC-03.2-05: lessons-learned パイプラインをローカルファイル保存に変更する

> REQ-03.2-03 対応（sessions と同一設計に統一）
> 追補: 2026-07-08（core-04 scope 整理により追加）

### 背景

現行実装 `hooks/lessons-learned-distill.sh` は `~/pcloud/obsidian/lessons-learned/` へ rclone FUSE 直書きしている（レガシー挙動）。
SPEC-03.2-03 で確立した「記録層 = ローカル / 配送層 = pcloud-sync.sh」原則に沿って lessons-learned も統一する。

また、`CLAUDE.md` は「`mcp__knowledge-rag__add_document` を直接呼ぶ」運用を定義しているが、
これも同一フローに統一する（knowledge-rag 登録は記録完了後の後処理として継続）。

### 振る舞い

#### ローカルステージングパス

```
LESSONS_LOCAL_DIR="$HOME/.local/share/knowledge-rag/lessons-learned"
```

sessions の LOCAL_STAGING_DIR と同じ `~/.local/share/knowledge-rag/` 配下に揃える。

#### `hooks/lessons-learned-distill.sh` の変更

| 変更箇所 | 変更内容 |
|---|---|
| `~/pcloud/obsidian/lessons-learned/` への書き込み | `$HOME/.local/share/knowledge-rag/lessons-learned/` への書き込みに変更 |
| pCloud FUSE マウント確認ブロック | 削除（ローカル書き込みは常時実行） |
| knowledge-rag 登録 | 記録完了後に継続（変更なし） |
| pCloud 配送処理 | **なし**（2026-07-08 確定）。ローカル保存完了で責務終了。pCloud 転送は `scripts/pcloud-sync.sh`（core-01 impl）に委任 |

#### `CLAUDE.md` の `mcp__knowledge-rag__add_document` 直接呼び出しの廃止

実装フェーズで `CLAUDE.md` の `lessons-learned` 登録手順を以下に変更する:
- 変更前: `mcp__knowledge-rag__add_document` を直接呼ぶ
- 変更後: `filepath: lessons-learned/YYYY-MM-DD-HHMMSS-<要約>.md` でファイルを `$HOME/.local/share/knowledge-rag/lessons-learned/` に保存し、knowledge-rag 登録は `lessons-learned-distill.sh` が担う

### 事後条件

- `~/.local/share/knowledge-rag/lessons-learned/` にファイルが保存される
- pCloud 未マウントでも `lessons-learned-distill.sh` が exit 0 で完了する
- `~/pcloud/obsidian/lessons-learned/` への直接書き込みが発生しない

### fail / warn / info

| 状態 | 判定 |
|---|---|
| pCloud 未マウントで `lessons-learned-distill.sh` が exit 0 以外で終了する | fail |
| LESSONS_LOCAL_DIR にファイルが作成されない | fail |
| pCloud 転送 | pcloud-sync.sh（core-01 impl）が担当。lessons-learned-distill.sh は判定しない |

### 境界条件

- `hooks/lessons-learned-distill.sh` の変更のみ。呼び出し元（setup 登録）は変更しない
- `CLAUDE.md` の変更は実装 PR に含める（`~/.claude/CLAUDE.md` の変更対象であり、デプロイ確認手順を impl-plan に記載する）

---

## 自動化対象と手動確認対象

| 操作 | 区分 | SPEC |
|---|---|---|
| `setup/410` SessionEnd 登録削除 + SessionStart 追加 | 自動（実装 PR） | SPEC-03.2-01 |
| `setup/410` 既存 SessionEnd クリーンアップ | 自動（実装 PR） | SPEC-03.2-01 |
| `session-end-queue.sh` の SessionEnd 登録確認・追加（impl 前に確認） | 自動（実装 PR） | SPEC-03.2-01 |
| `setup/410` log path 修正（`hooks/logs/` に統一） + `mkdir -p` 追加 | 自動（実装 PR） | SPEC-03.2-02 |
| `knowledge-distill.sh` OUTPUT_DIR をローカルに変更 | 自動（実装 PR） | SPEC-03.2-03 |
| `knowledge-distill.sh` drain 条件から pCloud mount 除去 | 自動（実装 PR） | SPEC-03.2-03 |
| pCloud 配送処理の分離（記録完了後のコピー + warn） | 自動（実装 PR） | SPEC-03.2-03 |
| `pcloud` キューアイテムを `pending` へ移行するコールバック | 自動（実装 PR） | SPEC-03.2-03 |
| `hooks/error-detector.sh` のリポジトリ追加（git add） | 自動（実装 PR） | SPEC-03.2-04 |
| `setup/413-hooks-error-detector.sh` 新設 | 自動（実装 PR） | SPEC-03.2-04 |
| `setup.sh` への 413 source 追加 | 自動（実装 PR） | SPEC-03.2-04 |
| rclone 未起動環境での smoke test | 手動 | SPEC-03.2-03 検証 |
| 既存 pcloud キューアイテムの移行確認 | 手動 | SPEC-03.2-03 境界条件 |
| `knowledge-auto-promote.sh` の LOCAL_STAGING_DIR パスでの動作確認 | 手動 | SPEC-03.2-03 境界条件 |
| `hooks/lessons-learned-distill.sh` の OUTPUT_DIR をローカルに変更 | 自動（実装 PR） | SPEC-03.2-05 |
| `hooks/lessons-learned-distill.sh` の pCloud マウント確認ブロック削除 | 自動（実装 PR） | SPEC-03.2-05 |
| pCloud 配送処理の追加（rclone copy + warn） | 自動（実装 PR） | SPEC-03.2-05 |
| `CLAUDE.md` の lessons-learned 登録手順変更（直接呼び出し → ローカル保存） | 自動（実装 PR） | SPEC-03.2-05 |
| pCloud 未マウント環境での lessons-learned smoke test | 手動 | SPEC-03.2-05 事後条件 |

---

## 未確定事項

| # | 事項 | 状態 |
|---|---|---|
| 1 | PostToolUse 登録で settings.json スキーマが `matcher` を許容するか。可能なら `matcher: "Bash"` を使う | impl-plan 着手前に確認 |
| 2 | `session-end-queue.sh` の SessionEnd 登録が現在どの setup スクリプトで行われているか | impl-plan 着手前に確認 |
| 3 | `pcloud-sync.sh` の実行タイミング（cadence）。sessions / lessons-learned / store/distilled/ の転送遅延が knowledge-rag 検索反映に影響する。定期実行（cron）か手動実行かを確定する | 実装前に確定（core-01 または core-03.2 で決定） |
