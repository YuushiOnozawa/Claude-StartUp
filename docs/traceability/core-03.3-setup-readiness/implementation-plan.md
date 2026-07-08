# Implementation Plan: Core 03.3 — ワンライナー展開後の実行可能状態保証

> ステータス: approved（2026-07-08 Codex レビュー対応済み。人間承認済み）
> 対応 specification: approved（2026-07-08）

## 前提確認

| 項目 | 現状 |
|---|---|
| `setup/850-codex.sh` | `command -v codex` の確認と fail 表示のみ。`npm install -g @openai/codex` の自動実行なし（修正対象） |
| `setup/401-ollama.sh` | zstd インストール + `curl ... install.sh | sh` による WSL2内 Ollama インストール。OLLAMA_HOST 疎通確認なし（変更対象） |
| `setup/900-verify.sh` | 存在しない（新設対象） |
| `setup/setup.sh` の verify 呼び出し | なし（900-verify.sh 新設後に追加対象） |
| README.md のワンライナー後手動ステップ | 存在しない（追記対象） |
| Codex 認証確認コマンド | 未確定（UND-03.3-01: impl フェーズで実機確認） |
| 必要 Ollama モデル一覧 | 未確定（UND-03.3-02: core-03.1 impl-plan 確定後に照合） |

---

## 実装項目一覧

| IMPL ID | 内容 | 対応 SPEC | 変更ファイル | 実行方法 |
|---|---|---|---|---|
| IMPL-03.3-01 | `setup/401-ollama.sh`: WSL2内インストール削除 + OLLAMA_HOST 疎通確認追加 | SPEC-03.3-03 | `setup/401-ollama.sh` | `/dev-flow` |
| IMPL-03.3-02 | `setup/850-codex.sh`: `npm install -g @openai/codex` 自動インストールロジック追加 | SPEC-03.3-01 | `setup/850-codex.sh` | `/dev-flow` |
| IMPL-03.3-03 | `setup/900-verify.sh` 新設（6チェック項目） + `setup.sh` に `bash setup/900-verify.sh` 呼び出し追加 | SPEC-03.3-04 | `setup/900-verify.sh`（新規）・`setup/setup.sh` | `/dev-flow` |
| IMPL-03.3-04 | `README.md`: ワンライナー後手動ステップ・verify 実行案内の追記 | SPEC-03.3-02, SPEC-03.3-05 | `README.md` | `/codegen` + `/commit`（IMPL-03.3-03 と同一 PR） |

---

## PR 分割

### PR-A: setup/401-ollama.sh OLLAMA_HOST 疎通確認化（IMPL-03.3-01）

> **着手前確認（blocker）:**
> - `setup/401-ollama.sh` の削除対象行の正確な範囲を確認する
>   **確認コマンド:** `grep -n "zstd\|install\.sh\|ollama serve" setup/401-ollama.sh`

**作業内容**:
- `setup/401-ollama.sh` の変更:
  - zstd インストールブロックを削除する
  - `curl ... install.sh | sh` による Ollama インストールブロックを削除する
  - `ollama serve` 等のサーバー起動・常駐化処理を削除する（存在する場合）
  - `OLLAMA_HOST` 未設定時: `warn "OLLAMA_HOST が未設定です。Windows ホスト Ollama を使う場合は OLLAMA_HOST=http://<WinIP>:11434 を設定してください"` を出力し疎通確認をスキップ
  - `OLLAMA_HOST` 設定済み時: `curl -s --max-time 5 "${OLLAMA_HOST}/api/version" > /dev/null 2>&1` で疎通確認
    - 成功: `ok "OLLAMA_HOST 疎通確認 OK ($OLLAMA_HOST)"`
    - 失敗: `warn "OLLAMA_HOST ($OLLAMA_HOST) への疎通が失敗しました。Windows ホスト Ollama が起動しているか確認してください"`
  - 疎通失敗時も setup を中断しない（非ゼロ終了しない）

**実行方法**: `/dev-flow`（WSL2環境の setup スクリプト変更のため）

**依存関係**: なし（PR-B と並行可）

**検証**:
```bash
# 削除確認: WSL2内インストール記述がなくなること
grep -q "install\.sh" setup/401-ollama.sh \
  && echo "FAIL: install.sh 記述が残存" || echo "OK: install.sh 削除確認"
grep -q "zstd" setup/401-ollama.sh \
  && echo "FAIL: zstd 記述が残存" || echo "OK: zstd 削除確認"

# OLLAMA_HOST 未設定時の warn 出力確認
OLLAMA_HOST="" bash setup/401-ollama.sh 2>&1 | grep -q "OLLAMA_HOST が未設定" \
  && echo "OK: warn 出力確認" || echo "FAIL: warn が出力されない"

# OLLAMA_HOST 設定済み + 疎通失敗時の warn 出力確認（到達不能IP使用）
OLLAMA_HOST="http://192.0.2.1:11434" bash setup/401-ollama.sh 2>&1 | grep -q "疎通が失敗" \
  && echo "OK: 疎通失敗 warn 確認" || echo "FAIL: 疎通失敗 warn が出力されない"

# 疎通失敗でも exit 0 で継続すること（中断禁止）
OLLAMA_HOST="http://192.0.2.1:11434" bash setup/401-ollama.sh > /dev/null 2>&1; \
  test $? -eq 0 && echo "OK: exit 0 確認" || echo "FAIL: 非ゼロ終了（中断禁止）"
```

---

### PR-B: setup/850-codex.sh 自動インストール追加（IMPL-03.3-02）

**作業内容**:
- `setup/850-codex.sh` の変更:
  - `command -v codex` が失敗した場合のインストール試行ブロックを追加:
    1. `command -v npm` の有無を確認
    2. npm なし: `fail "codex CLI → npm が必要です"` を出力し `MISSING_CMDS+=("codex")` に追加、処理継続
    3. npm あり: `npm install -g @openai/codex` を実行
       - 成功: `ok "codex CLI ($(codex --version))"`
       - 失敗: `fail "codex CLI → npm install -g @openai/codex を手動で実行してください"` + `MISSING_CMDS+=("codex")`
  - `command -v codex` が成功している場合は現状通りスキップ（冪等）

**実行方法**: `/dev-flow`

**依存関係**: なし（PR-A と並行可）

**検証**:
```bash
# インストールロジックが存在すること
grep -q "npm install -g @openai/codex" setup/850-codex.sh \
  && echo "OK: インストールロジック確認" || echo "FAIL: インストールロジックがない"

# npm チェックが存在すること
grep -q "command -v npm" setup/850-codex.sh \
  && echo "OK: npm チェック確認" || echo "FAIL: npm チェックがない"

# MISSING_CMDS 追加が存在すること
grep -q 'MISSING_CMDS.*codex' setup/850-codex.sh \
  && echo "OK: MISSING_CMDS 追加確認" || echo "FAIL: MISSING_CMDS 追加がない"

# 冪等性確認: codex 導入済み環境で npm install が呼ばれないこと（stub で機械検証）
_stub_dir=$(mktemp -d)
_npm_log="$_stub_dir/npm_called"
printf '#!/bin/bash\ntouch "%s"\necho "npm stub called" >&2\n' "$_npm_log" > "$_stub_dir/npm"
printf '#!/bin/bash\necho "stub 0.0.0"\n' > "$_stub_dir/codex"
chmod +x "$_stub_dir/npm" "$_stub_dir/codex"
PATH="$_stub_dir:$PATH" bash setup/850-codex.sh > /dev/null 2>&1
test ! -f "$_npm_log" \
  && echo "OK: npm 未呼び出し（冪等性確認）" || echo "FAIL: npm が呼ばれた（冪等性違反）"
rm -rf "$_stub_dir"

# SPEC-03.3-02: 850-codex.sh に codex 認証チェックが存在しないこと（verify が担当）
grep -q "codex login\|auth.status\|auth_status\|codex.*auth" setup/850-codex.sh \
  && echo "FAIL: 850-codex.sh に認証チェックが混入（verify が担当）" || echo "OK: auth-check 不在確認"
```

---

### PR-C: setup/900-verify.sh 新設 + README 更新（IMPL-03.3-03, IMPL-03.3-04）
> **単一の関心事**: 「セットアップ後の疎通確認とユーザーガイダンスの提供」。900-verify.sh（スクリプト）と README（ガイダンス）は同一コンテキストで完結するため同一 PR とする。

> **着手前確認（blocker）:**
> - **UND-03.3-01**: Codex 認証確認コマンドを実機確認する
>   **確認コマンド:** `codex --help 2>&1 | grep -i "auth\|login\|status"`
>   代替案: `test -f ~/.codex/auth.json`（ファイル存在確認）
> - **UND-03.3-02**: 必要 Ollama モデル一覧を core-03.1 impl-plan から取得して確定する
>   **確認:** core-03.1 impl-plan（IMPL-03.1-01〜07）の MAGI 要求モデル名を列挙
> - setup.sh への挿入位置確認:
>   **確認コマンド:** `tail -20 setup/setup.sh`

**作業内容**:
- `setup/900-verify.sh` を新規作成（スタンドアロン実行専用）:
  - `ok`/`fail`/`warn`/`info` 関数を自前定義（source ガード不要）
  - OLLAMA_HOST デフォルト: `OLLAMA_HOST="${OLLAMA_HOST:-http://localhost:11434}"`
  - チェック項目（順序通り）:
    1. `curl -s --max-time 5 "$OLLAMA_HOST/api/version" > /dev/null 2>&1` → **fail** 判定
    2. `command -v codex > /dev/null 2>&1` → warn 判定
    3. Codex 認証確認（UND-03.3-01 確定後: `codex auth status` または `test -f ~/.codex/auth.json`）→ warn 判定
    4. `test -x ~/.claude/hooks/error-detector.sh` → warn 判定
    5. `curl -s "$OLLAMA_HOST/api/tags"` から必要モデル在否確認（UND-03.3-02 確定後）→ warn 判定（不足モデル名を列挙）
    6. `rclone listremotes 2>/dev/null | grep -qi pcloud` → info 判定
  - fail 1件以上: exit 1。warn/info のみ: exit 0
- `setup/setup.sh` の変更:
  - 挿入行は TBD（blocker #6 解決後に確定: `bash "$(dirname "$0")/900-verify.sh"` または `bash "$(dirname "$0")/900-verify.sh" || true`）
  - 挿入位置: 最終 source 行の後（blocker #4: `tail -20 setup/setup.sh` で確認）
- `README.md` の変更:
  - ワンライナー手順直後に「ワンライナー後の手動ステップ」セクションを追記（SPEC-03.3-05 の内容準拠）
  - 「setup 後の状態確認」セクションを追記（`bash setup/900-verify.sh` の案内）
  - 既存ワンライナーセクションは変更しない（追記のみ）

**実行方法**: `/dev-flow`（新規ファイル追加 + setup.sh・README.md 変更のため）

**依存関係**:
- UND-03.3-01 / UND-03.3-02 / UND-03.3-03 確認完了後（blocker）
- PR-A・PR-B より後が推奨（verify が401/850 の成果物を検証するため）
- 技術的には独立（900-verify.sh のコードは 401/850 に依存しない）

**検証**:
```bash
# ファイルが存在し実行可能であること
test -x setup/900-verify.sh \
  && echo "OK: 実行可能" || echo "FAIL: 存在しないか実行不可"

# setup.sh から bash 呼び出しが存在すること
grep -q "900-verify.sh" setup/setup.sh \
  && echo "OK: setup.sh 呼び出し確認" || echo "FAIL: setup.sh に呼び出しがない"

# OLLAMA_HOST 疎通失敗時に [FAIL] 出力 + exit 1 になること（到達不能IP使用）
OLLAMA_HOST="http://192.0.2.1:11434" bash setup/900-verify.sh 2>&1 | grep -q "\[FAIL\]" \
  && echo "OK: [FAIL] 出力確認" || echo "FAIL: [FAIL] 出力なし"
OLLAMA_HOST="http://192.0.2.1:11434" bash setup/900-verify.sh > /dev/null 2>&1; \
  test $? -ne 0 && echo "OK: exit 1 確認" || echo "FAIL: exit 0（FAIL時は非ゼロが必要）"

# error-detector.sh が存在しない場合に [WARN] 出力になること（OLLAMA_HOST 疎通済み環境で確認）
_bak_ts=$(date +%s)
mv ~/.claude/hooks/error-detector.sh ~/.claude/hooks/error-detector.sh.bak.$_bak_ts 2>/dev/null || true
bash setup/900-verify.sh 2>&1 | grep -q "\[WARN\].*error-detector" \
  && echo "OK: error-detector warn 確認" || echo "FAIL: error-detector warn なし"
mv ~/.claude/hooks/error-detector.sh.bak.$_bak_ts ~/.claude/hooks/error-detector.sh 2>/dev/null || true

# README 追記のみ確認: 削除行がゼロであること（既存ワンライナーセクションを変更しない）
_deleted_lines=$(git diff HEAD -- README.md | grep -c '^-[^-]' 2>/dev/null || echo 0)
test "$_deleted_lines" -eq 0 \
  && echo "OK: 削除行なし（追記のみ確認）" || echo "FAIL: ${_deleted_lines} 行削除されている（追記のみ要件違反）"

# SPEC-03.3-05 の4手動ステップが存在すること
grep -q "ワンライナー後の手動ステップ" README.md \
  && echo "OK: 手動ステップセクション" || echo "FAIL: セクションがない"
grep -q "codex login" README.md \
  && echo "OK: codex login" || echo "FAIL: codex login がない"
grep -q "rclone config" README.md \
  && echo "OK: rclone config" || echo "FAIL: rclone config がない"
grep -q "knowledge-rag" README.md \
  && echo "OK: knowledge-rag 設定案内" || echo "FAIL: knowledge-rag 案内がない"
grep -q "ollama pull" README.md \
  && echo "OK: ollama pull 案内" || echo "FAIL: ollama pull 案内がない"
grep -q "900-verify.sh" README.md \
  && echo "OK: verify 案内" || echo "FAIL: 900-verify.sh 案内がない"
```

---

## 依存関係グラフ

```
[UND-03.3-01: Codex認証確認コマンド実機確認] ← PR-C blocker
[UND-03.3-02: 必要モデル一覧確定（core-03.1 impl-plan から）] ← PR-C blocker
[blocker #6: setup.sh 失敗時挙動（|| true かエラー伝播か）] ← PR-C blocker

PR-A（401-ollama.sh OLLAMA_HOST疎通確認化）╌╌→ PR-C（900-verify.sh 新設 + README更新）
PR-B（850-codex.sh 自動インストール追加）╌╌→ PR-C（900-verify.sh 新設 + README更新）

凡例: ╌╌→ 推奨順（技術的にコード依存なし。ただし PR-C の完全検証は PR-A・PR-B 成果物が前提）
```

---

## 実装前に決めるべきこと

| # | 事項 | 現状 | blocker |
|---|---|---|---|
| 1 | **UND-03.3-01**: Codex 認証確認コマンド | 未確定。`codex --help 2>&1 \| grep -i auth` で確認。なければ `test -f ~/.codex/auth.json` に代替 | **PR-C blocker**（チェック項目3の実装） |
| 2 | **UND-03.3-02**: 必要 Ollama モデル一覧 | 未確定。core-03.1 impl-plan 承認後に MAGI 要求モデル名を照合して確定 | **PR-C blocker**（チェック項目5の実装） |
| 3 | **UND-03.3-03**: `rclone listremotes` の代替手段 | 失敗でも info 判定のため許容範囲。実機確認推奨 | **non-blocking**（PR-C 着手前の確認推奨） |
| 4 | setup/900-verify.sh の setup.sh 内挿入位置 | 最終 source 行の後を想定。確認: `tail -20 setup/setup.sh` | **PR-C blocker** |
| 5 | setup/401-ollama.sh の削除対象行の正確な範囲 | `grep -n "zstd\|install\.sh" setup/401-ollama.sh` で確認 | **PR-A blocker** |
| 6 | setup.sh が 900-verify.sh の exit 1 で全体を止めるかどうか | 900-verify.sh が fail 時 exit 1 を返す。setup.sh 側の扱いを決める（`|| true` でスルーか、呼び出し元がエラー処理するか） | **PR-C blocker** |

---

## 手動操作（PR 外）

| 操作 | タイミング | 内容 |
|---|---|---|
| UND-03.3-01 実機確認 | PR-C 着手前 | `codex --help 2>&1 \| grep -i "auth\|login\|status"` を実行。結果に応じて実装方針を確定 |
| UND-03.3-02 モデル一覧確定 | core-03.1 impl-plan 承認後・PR-C 着手前 | core-03.1 impl-plan の MAGI モデル定義を参照し、verify チェック項目5の比較対象リストを確定 |
| 900-verify.sh 全項目スタブテスト | PR-C deploy 後 | チェック項目ごとにスタブで確認（環境非依存）: `command -v codex` は stub codex で warn 確認、`error-detector.sh` は一時リネームで warn 確認、`rclone listremotes` は info 出力確認。OLLAMA_HOST fail は `192.0.2.1` で確認（上記検証に含む） |
| Windows Ollama 起動時の疎通確認 | PR-C deploy 後（任意） | OLLAMA_HOST が実際に疎通できる状態で `bash setup/900-verify.sh` を実行し、チェック項目1が `[OK]` になることを目視確認 |

---

## 注意

- **OLLAMA_HOST デフォルト値の役割分担**: `setup/401-ollama.sh` は OLLAMA_HOST 未設定時に warn してスキップする（SPEC-03.3-03 規定）。`setup/900-verify.sh` は OLLAMA_HOST 未設定時に `http://localhost:11434` をデフォルト適用して疎通確認を試みる（SPEC-03.3-04 規定）。両者の動作は意図的に異なるため混在させないこと
- `setup/401-ollama.sh` の変更は **WSL2内 Ollama インストール全体の廃止** を意味する。core-01 REQ-01-02（Windows ホスト Ollama 前提）と整合していることを PR 作成前に確認する
- `setup/900-verify.sh` は setup.sh から `bash`（subprocess）で呼び出す（source ではない。SPEC-03.3-04 規定）
- 900-verify.sh の継続的自動実行（CI 組み込み）は core-03.4 の担当。本 core では手動実行手段の提供のみ
- PR-C は README.md も含むため、ワンライナーセクションの前後の文脈を壊さないこと
