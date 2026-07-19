# Implementation Plan: Core 03.2 — hooks / knowledge-distill / 知識ストアの二重化・欠落・密結合

> ステータス: approved（2026-07-08 人間承認済み）
> 対応 specification: approved（2026-07-08 SPEC-03.2-05 追補）

## 前提確認

| 項目 | 現状 |
|---|---|
| `setup/410` の SessionEnd 登録 | `knowledge-distill.sh` を SessionEnd に直接登録（二重実行あり。修正対象） |
| `setup/410` の log path | `hooks/knowledge-distill.log`（`hooks/logs/` と不一致。修正対象） |
| `knowledge-distill.sh` の OUTPUT_DIR | `$HOME/pcloud/obsidian/sessions`（pCloud FUSE 前提。変更対象） |
| `hooks/error-detector.sh` | `~/.claude/hooks/` にのみ存在。リポジトリ未追加・setup スクリプトなし（追加対象） |
| `hooks/lessons-learned-distill.sh` | `~/pcloud/obsidian/lessons-learned/` へ FUSE 直書き（レガシー。変更対象） |
| `scripts/pcloud-sync.sh` | 未存在（新設が必要。SPEC-01-03 定義。本 core の実装方針を下記参照） |
| `CLAUDE.md` の lessons-learned 登録 | `mcp__knowledge-rag__add_document` 直接呼び出し（実装フェーズで変更対象） |

---

## 実装項目一覧

| IMPL ID | 内容 | 対応 SPEC | 変更ファイル | 実行方法 |
|---|---|---|---|---|
| IMPL-03.2-01 | `setup/410` の SessionEnd 削除 + SessionStart 追加 + ログパス修正 + `mkdir -p` | SPEC-03.2-01, SPEC-03.2-02 | `setup/410*.sh` | `/dev-flow` |
| IMPL-03.2-02 | `knowledge-distill.sh` 記録層/配送層分離（pCloud 非依存化 + LOCAL_STAGING_DIR + pcloud コールバック削除） | SPEC-03.2-03 | `hooks/knowledge-distill.sh` | `/dev-flow` |
| IMPL-03.2-03 | `hooks/error-detector.sh` を repo に追加 + `setup/413-hooks-error-detector.sh` 新設（`setup.sh` は `setup/*.sh` を glob 自動読み込みするため source 追加は不要。実装時に判明・PR-C 注記参照） | SPEC-03.2-04 | `hooks/error-detector.sh`（新規）・`setup/413-hooks-error-detector.sh`（新規） | `/dev-flow` |
| IMPL-03.2-04 | `lessons-learned-distill.sh` の OUTPUT_DIR をローカルに変更 + pCloud FUSE 直書き廃止（pCloud 転送は pcloud-sync.sh に委任） | SPEC-03.2-05 | `hooks/lessons-learned-distill.sh` | `/dev-flow` |
| IMPL-03.2-05 | `CLAUDE.md` の `lessons-learned` 登録手順を `mcp__knowledge-rag__add_document` 直接呼び出し → ローカルファイル保存に変更 | SPEC-03.2-05 | `CLAUDE.md` | `/codegen` + `/commit`（IMPL-03.2-04 と同一 PR） |

---

## PR 分割

### PR-A: setup/410 SessionEnd→SessionStart 移行 + ログパス修正（IMPL-03.2-01）

> **✅ 完了（2026-07-16）**: [PR #313](https://github.com/YuushiOnozawa/Claude-StartUp/pull/313) merge 済み・live デプロイ検証 4 項目 OK。
> - 実装ファイル: `setup/410-hooks-distill.sh`, `setup/412-hooks-queue.sh`, `scripts/test-setup-hooks-registration.sh`（新規、fixture HOME で 20 テスト）
> - blocker #1 の結論: session-end-queue.sh はどの setup からも未登録だったため、412 に SessionEnd 登録を追加
> - レビュー由来のスコープ追加: settings.json `{}` 初期化（新規環境対応、触る 2 ファイルのみ）、jq を単一 atomic 更新に統合、正規化は「対象 hook 全除去 → 正規コマンド 1 件追加」方式（重複収束）、settings.json symlink ガード
> - 既存慣行由来のハードニング残件は [#315](https://github.com/YuushiOnozawa/Claude-StartUp/issues/315)、magi-fast 誤検知の改善は [#314](https://github.com/YuushiOnozawa/Claude-StartUp/issues/314) に分離

> **着手前確認（blocker）:**
> - `session-end-queue.sh` の SessionEnd 登録が現行どのスクリプトで行われているかを確認する（UND 未確定事項 #2）
>   **確認コマンド:** `grep -rn "session-end-queue" setup/`
> - `setup/410*.sh` の正確なファイル名を確認する
>   **確認コマンド:** `ls setup/410*`

**作業内容**:
- `setup/410*.sh` の変更:
  - `knowledge-distill.sh` を SessionEnd に追加する jq ブロックを削除する
  - 既存 SessionEnd から `knowledge-distill.sh` を除去するクリーンアップ処理を追加する（べき等）
  - `knowledge-distill.sh` を SessionStart に登録する jq ブロックを追加する（ログパス修正済みコマンド文字列）
  - `~/.claude/hooks/logs/` の `mkdir -p` を追加する
- 登録コマンド文字列: `"bash ${HOME}/.claude/hooks/knowledge-distill.sh 2>> ${HOME}/.claude/hooks/logs/knowledge-distill.log"`
- `session-end-queue.sh` の SessionEnd 登録が未登録の場合: 同 PR で登録スクリプトを追加/修正する

**実行方法**: `/dev-flow`（`settings.json` を動的書き換えする setup スクリプトのため）

**依存関係**: `session-end-queue.sh` 登録元の確認完了後（blocker #1）

**検証**:
```bash
# PR-A をデプロイしてから setup/410*.sh を実行した後

# SessionEnd に knowledge-distill.sh が残っていないこと（exit 1 なら fail）
test "$(jq '[.hooks.SessionEnd[].hooks[].command] | map(select(contains("knowledge-distill"))) | length' \
  ~/.claude/settings.json)" -eq 0 && echo "OK" || echo "FAIL: SessionEnd に knowledge-distill.sh が残存"

# SessionStart に knowledge-distill.sh が 1 件のみあること（重複なし）
test "$(jq '[.hooks.SessionStart[].hooks[].command] | map(select(contains("knowledge-distill"))) | length' \
  ~/.claude/settings.json)" -eq 1 && echo "OK" || echo "FAIL: SessionStart の knowledge-distill.sh 件数が 1 でない"

# SessionEnd に session-end-queue.sh が 1 件のみあること
test "$(jq '[.hooks.SessionEnd[].hooks[].command] | map(select(contains("session-end-queue"))) | length' \
  ~/.claude/settings.json)" -eq 1 && echo "OK" || echo "FAIL: session-end-queue.sh の件数が 1 でない"

# hooks/logs/ ディレクトリが存在すること
test -d ~/.claude/hooks/logs/ && echo "OK" || echo "FAIL: hooks/logs/ が存在しない"
```

---

### PR-B: knowledge-distill.sh 記録層/配送層分離（IMPL-03.2-02）

> **✅ 完了（2026-07-16）**: [PR #317](https://github.com/YuushiOnozawa/Claude-StartUp/pull/317) merge 済み・live デプロイ検証 OK（pcloud コールバック/mountpoint 不在・LOCAL_STAGING_DIR 設定・repo/live 同一）。
> - 実装ファイル: `hooks/knowledge-distill.sh`, `scripts/test-knowledge-distill-local.sh`（新規、13 テスト）
> - 仕様改訂（人間承認済み・spec に注記反映）: drain は pending/ollama とも Ollama 起動時のみ（dead-letter 防止）
> - レビュー由来の追加: raw 生成の retry スキップ撤廃（PR-A 後は全実行が drain 経由のため）、同一 transcript の重複キュー投入抑止、移行失敗の log_warn
> - **リリース条件**: pCloud への転送は `scripts/pcloud-sync.sh`（core-01 impl）実装まで停止し、ローカル staging（`~/.local/share/knowledge-rag/sessions/`）に蓄積される
> - 交通整理: 同領域の PR #249（Raw 即書き出し構想）はクローズ（core-03.2 README の外部先行変更に記録）
> - 下記の「検証」「既存 pcloud キューアイテムの移行」の一部コマンドはキューの旧レイアウト（`pcloud/pending/` サブディレクトリ）前提で誤り。実レイアウトは flat dir + アイテム JSON の `reason` フィールド。正しい検証は `scripts/test-knowledge-distill-local.sh` および以下:
>   ```bash
>   # pcloud reason のアイテムが残っていないこと
>   for f in ~/.claude/hooks/queue/knowledge-distill/*.json; do [ -f "$f" ] && jq -r .reason "$f"; done | grep -c pcloud  # 0 なら OK
>   # pcloud コールバック・mountpoint 確認の不在
>   grep -q 'queue_drain.*pcloud' ~/.claude/hooks/knowledge-distill.sh || echo OK
>   grep -q 'mountpoint -q' ~/.claude/hooks/knowledge-distill.sh || echo OK
>   ```

> **配送方針（2026-07-08 確定）: hooks はローカル保存のみ。pCloud 転送は `scripts/pcloud-sync.sh`（core-01 impl で新設）に委任。FUSE 直書き禁止（SPEC-01-03 不変条件）。**

**作業内容**（上記 blocker 解決後）:
- `hooks/knowledge-distill.sh` の変更:
  - 冒頭の pCloud マウント確認ブロック削除（L94-104）
  - drain 条件から pCloud mount 条件を除去（`pending` は常時・`ollama` は Ollama 起動時のみ）
  - `OUTPUT_DIR` を `$HOME/.local/share/knowledge-rag/sessions` に変更
  - `mkdir -p "$OUTPUT_DIR"` を LOCAL_STAGING_DIR に対して実行
  - `pcloud` キューアイテムを `pending` に移行するコールバックを追加し、移行完了後に `queue_drain "knowledge-distill" "pcloud"` コールバック自体を削除する（pcloud reason の完全廃止）
  - pCloud 配送処理は追加しない（`scripts/pcloud-sync.sh`（core-01 impl）に委任）

**実行方法**: `/dev-flow`（hooks の中枢ファイル）

**依存関係**: PR-A が merge 済みであること
- 根拠: `knowledge-distill.sh` は SessionStart で実行される（PR-A 後）。PR-B の変更後スクリプトが新セッションから動作するよう、先に登録変更を確定させる

**検証**（SPEC-03.2-03）:
```bash
# pCloud 未マウント環境であることを確認（前提条件）
! mountpoint -q ~/pcloud && echo "OK: unmounted" || echo "SKIP: pcloud マウット済み。テスト前にアンマウントする"

# テスト用 transcript を実在ファイルで生成
TEST_JSONL=$(mktemp /tmp/test-distill-XXXXXX.jsonl)
echo '{"role":"user","content":"テスト"}' > "$TEST_JSONL"

# 手動実行
echo "{\"transcript_path\":\"$TEST_JSONL\",\"cwd\":\"/tmp\"}" \
  | bash ~/.claude/hooks/knowledge-distill.sh

# LOCAL_STAGING_DIR にファイルが存在すること
find ~/.local/share/knowledge-rag/sessions/ -newer "$TEST_JSONL" -name "*.md" | grep -q . \
  && echo "OK: ローカル保存確認" || echo "FAIL: ローカルファイルが作成されない"

# pcloud キューへの push がないこと
test "$(ls ~/.claude/hooks/queue/knowledge-distill/pcloud/pending/ 2>/dev/null | wc -l)" -eq 0 \
  && echo "OK: pcloud キュー空" || echo "FAIL: pcloud キューにアイテムが残存"

# pcloud reason コールバックが残っていないこと（IMPL-03.2-02 対応）
grep -q 'queue_drain.*pcloud' ~/.claude/hooks/knowledge-distill.sh \
  && echo "FAIL: pcloud コールバックが残存" || echo "OK: pcloud コールバック削除確認"

# クリーンアップ
rm -f "$TEST_JSONL"
```

**既存 pcloud キューアイテムの移行（手動）**:
```bash
# 移行前: 件数確認
ls ~/.claude/hooks/queue/knowledge-distill/pcloud/pending/ 2>/dev/null | wc -l

# 移行コマンド（knowledge-distill.sh の移行コールバックが行う。または手動）
mv ~/.claude/hooks/queue/knowledge-distill/pcloud/pending/* \
   ~/.claude/hooks/queue/knowledge-distill/pending/ 2>/dev/null || true
```

---

### PR-C: error-detector.sh リポジトリ追加 + setup/413（IMPL-03.2-03）

> **✅ 完了（2026-07-17）**: [PR #322](https://github.com/YuushiOnozawa/Claude-StartUp/pull/322) merge 済み・live 検証 OK（配置・実行権限・PostToolUse 正規登録 1 件）。
> - 実装ファイル: `setup/413-hooks-error-detector.sh`（新規）, `scripts/test-setup-hooks-registration.sh`（+12 テスト = 32 件）, `skills/self-improvement/SKILL.md`（正本参照修正）
> - スコープ注記: 「repo 追加」は core-02 還流（PR-R4 = f9986f6）で先行完了。「setup.sh への source 追加」は glob 自動検出のため不要（本計画の記載は旧前提）
> - 正本宣言: `hooks/error-detector.sh` が正本（skills/self-improvement/scripts/ 配下は複製）
> - 判定補足: 本 PR の magi-fast は gate 修繕（#319 echo 対策 / #320 No findings 寛容化 / #321 completion OR 緩和）後、初の全 persona parse ok。HIGH 1 件は検証の上、人間判断で不採用

**作業内容**:
- `~/.claude/hooks/error-detector.sh` の内容を `hooks/error-detector.sh` として `git add`
- `setup/413-hooks-error-detector.sh` を新設:
  - `hooks/error-detector.sh` → `~/.claude/hooks/error-detector.sh` へコピー + `chmod +x`
  - PostToolUse に `error-detector.sh` を jq 動的注入で登録（contains で重複排除）
- `setup/setup.sh` に `413` の source 行を追加（`410-412` source 行の直後）

> **matcher 方針（SPEC-03.2-04 確定済み）**: matcher は使用しない。スクリプト内 TOOL_NAME フィルタのみで Bash コマンドを絞り込む。

**実行方法**: `/dev-flow`（新規ファイル追加 + setup.sh 変更のため）

**依存関係**: なし（PR-A/B と独立して並行可）

**検証**:
```bash
# repo にファイルが存在すること
git ls-files hooks/error-detector.sh | grep -q . \
  && echo "OK" || echo "FAIL: hooks/error-detector.sh が repo に存在しない"

# setup 実行後: 実行権限があること
test -x ~/.claude/hooks/error-detector.sh \
  && echo "OK: 実行権限あり" || echo "FAIL: 実行権限なし"

# PostToolUse に登録が 1 件のみあること
test "$(jq '[.hooks.PostToolUse[].hooks[].command] | map(select(contains("error-detector"))) | length' \
  ~/.claude/settings.json)" -eq 1 && echo "OK" || echo "FAIL: PostToolUse の error-detector 件数が 1 でない"
```

---

### PR-D: lessons-learned ローカル化 + CLAUDE.md 変更（IMPL-03.2-04, IMPL-03.2-05）

> **✅ 完了（2026-07-19）**: [PR #324](https://github.com/YuushiOnozawa/Claude-StartUp/pull/324) merge 済み・live 検証 OK（setup.sh 配備で repo/live 同一・`mountpoint` 参照消滅・テスト 12 PASS）。
> - 実装ファイル: `hooks/lessons-learned-distill.sh`, `CLAUDE.md`, `scripts/test-lessons-learned-local.sh`（新規、fixture HOME で 12 テスト）
> - 仕様明確化（Codex 設計レビュー指摘・人間確認済み 2026-07-19）: **手動保存はローカル記録のみ**（knowledge-rag 登録経路は追加しない）。distill.sh の登録は transcript 由来の自動抽出分のみが対象。specification.md の SPEC-03.2-05 に注記を追記
> - drain ゲートは PR-B と同旨で「Ollama 起動時のみ」に変更（dead-letter 防止）。pcloud reason の既存キューアイテムは `queue_drain "" `（全 reason）が処理するため移行処理は不要
> - **下記の「CLAUDE.md デプロイ手順」の全文 `cp` は不採用**: `~/.claude/CLAUDE.md` は repo 版と分岐している（lean-ctx・RTK import 等グローバル専用セクションあり）ため、該当セクションのみの手動編集で反映した（バックアップ作成・旧文言消滅/新文言存在を検証済み）
> - **下記「検証」の `filepath/content` JSON を渡すコマンドは実態と不一致**（hook は SessionEnd の transcript_path を処理する）。正しい検証は `scripts/test-lessons-learned-local.sh`
> - magi-fast: 3 persona 全 parse ok。HIGH 1 件（テストの mktemp ガード）は repo 慣行（既存テスト群と同一パターン）と統一済みのため人間判断で不採用

**作業内容**:
- `hooks/lessons-learned-distill.sh` の変更:
  - `~/pcloud/obsidian/lessons-learned/` への書き込みを `$HOME/.local/share/knowledge-rag/lessons-learned/` に変更
  - pCloud FUSE マウント確認ブロックを削除（ローカル書き込みは常時実行）
  - pCloud 配送処理は追加しない（`scripts/pcloud-sync.sh`（core-01 impl）に委任）
- `CLAUDE.md` の変更（リポジトリ root）:
  - `lessons-learned` 登録手順: `mcp__knowledge-rag__add_document` 直接呼び出し → `$HOME/.local/share/knowledge-rag/lessons-learned/YYYY-MM-DD-HHMMSS-<要約>.md` にファイル保存
  - knowledge-rag 登録は `lessons-learned-distill.sh` が担う旨を明記

> **CLAUDE.md デプロイ手順**（PR-D merge 後に手動実行）:
> blocker #5（デプロイ方法）が解消後、以下いずれかの確定手順で実施する:
>
> ```bash
> # バックアップ
> cp ~/.claude/CLAUDE.md ~/.claude/CLAUDE.md.bak.$(date +%Y%m%d%H%M%S)
>
> # 差分確認（意図した変更のみであることを確認）
> diff -u ~/.claude/CLAUDE.md CLAUDE.md
>
> # デプロイ（setup.sh 経由でなく手動コピーの場合）
> cp CLAUDE.md ~/.claude/CLAUDE.md
>
> # 内容検証: 旧文言が消えていること
> grep -n "mcp__knowledge-rag__add_document" ~/.claude/CLAUDE.md \
>   && echo "FAIL: 旧文言が残存" || echo "OK: 旧文言削除確認"
>
> # 内容検証: 新文言が存在すること
> grep -q "lessons-learned/.*\.md.*ローカル保存" ~/.claude/CLAUDE.md \
>   && echo "OK: 新文言確認" || echo "FAIL: 新文言が見つからない"
>
> # rollback（誤デプロイ時）
> # cp ~/.claude/CLAUDE.md.bak.YYYYMMDDHHMMSS ~/.claude/CLAUDE.md
> ```

**実行方法**: `/dev-flow`（hooks ファイル + CLAUDE.md 変更のため）

**依存関係**: PR-B merge 済みが推奨（技術的にはブロックされない）
- 根拠: sessions と lessons-learned が同じ `~/.local/share/knowledge-rag/` 親を使うため、PR-B の動作確認後に進めることでパス設計の整合を確認できる

**検証**:
```bash
# pCloud 未マウント環境であることを確認
! mountpoint -q ~/pcloud && echo "OK: unmounted" || echo "SKIP: アンマウント後に実施"

# テスト用 lessons-learned ファイルを一意な名前で作成
TEST_LL_FILE=$(date +%Y%m%d%H%M%S)-test-codex.md
mkdir -p ~/.local/share/knowledge-rag/lessons-learned/

echo '{"filepath":"lessons-learned/'"$TEST_LL_FILE"'","content":"テスト"}' \
  | bash ~/.claude/hooks/lessons-learned-distill.sh

# ローカル保存されていること
test -f ~/.local/share/knowledge-rag/lessons-learned/"$TEST_LL_FILE" \
  && echo "OK: ローカル保存確認" || echo "FAIL: ローカルファイルが存在しない"

# pCloud への直接書き込みが発生していないこと
test ! -e ~/pcloud/obsidian/lessons-learned/"$TEST_LL_FILE" \
  && echo "OK: pCloud への直接書き込みなし" || echo "FAIL: pCloud に直接書き込みが発生"
```

---

## 依存関係グラフ

```
[session-end-queue.sh 登録元確認] ← blocker
  └→ PR-A（setup/410 SessionEnd→SessionStart 移行 + ログパス修正）
       └→ PR-B（knowledge-distill.sh 記録層/配送層分離）
            ╌╌→ PR-D（lessons-learned ローカル化）← 推奨順（技術的には独立）

PR-C（error-detector.sh）← 独立（PR-A/B/D と並行可）

凡例: └→ 必須依存 / ╌╌→ 推奨順（独立可）
```

---

## 実装前に決めるべきこと

| # | 事項 | 現状 | blocker |
|---|---|---|---|
| 1 | `session-end-queue.sh` の SessionEnd 登録スクリプト確認（PR-A 着手前） | `grep -rn "session-end-queue" setup/` で確認 | **PR-A blocker** |
| 2 | setup/410 の正確なファイル名（PR-A 着手前） | `ls setup/410*` で確認 | **PR-A blocker** |
| 3 | ~~PostToolUse の `matcher` 可否~~ | **確定済み**: matcher なし。TOOL_NAME フィルタのみ（SPEC-03.2-04 確定）| 解消済み |
| 4 | **UND-03.2-03 (pcloud-sync cadence)** | 未確定。定期実行（cron）か手動実行か。core-01 impl-plan で確定する | core-01 impl-plan で確定 |
| 5 | CLAUDE.md のデプロイ方法（PR-D 着手前） | setup.sh が CLAUDE.md を配備するか、手動コピーか確認: `grep -n "CLAUDE.md" setup/setup.sh` | PR-D blocker |

---

## 手動操作（PR 外）

| 操作 | タイミング | 内容 |
|---|---|---|
| 既存 pcloud キューアイテムの pending 移行 | PR-B deploy 後 | 上記 PR-B 検証内の移行コマンド参照 |
| `knowledge-auto-promote.sh` の LOCAL_STAGING_DIR パスでの動作確認 | PR-B deploy 後 | `OUTPUT_FILE` が `~/.local/share/knowledge-rag/sessions/` 配下になることを確認 |
| CLAUDE.md デプロイ | PR-D merge 後 | `cp CLAUDE.md ~/.claude/CLAUDE.md`（または setup.sh 経由） |

---

## 注意

- `knowledge-distill.sh` はすべてのセッション知識の入口。PR-B は `/dev-flow`（magi-hard レビュー）を必ず通す
- `setup/410` の idempotency を壊さないこと（contains 確認の jq パターンを維持）
- `~/.claude/settings.json` はリポジトリで管理しない（core-02 REQ-02-05）。jq 動的注入方式を維持する
- `error-detector.sh` は git add 前に `~/.claude/hooks/error-detector.sh` の内容をユーザーに確認してからコミットする（本体をリポジトリに収録するため）
