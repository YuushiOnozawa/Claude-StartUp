# Specification Draft: Core 03.3 — ワンライナー展開後の実行可能状態保証

> ステータス: approved（2026-07-08）
> 対応 requirements: approved 2026-07-07

---

## SPEC-03.3-01 — Codex CLI 自動インストール

**対応 REQ:** REQ-03.3-01  
**自動化対象:** setup/850-codex.sh（現状: command -v codex の確認と fail 表示のみ）

### 振る舞い

1. `command -v codex` が失敗した場合、`npm install -g @openai/codex` を実行する
2. npm が未インストールの場合は `fail "codex CLI → npm が必要です"` を出力して処理を継続する（setup 中断しない）
3. インストール成功時: `ok "codex CLI (<バージョン>)"` を出力する
4. インストール失敗時: `fail "codex CLI → npm install -g @openai/codex を手動で実行してください"` を出力し、`MISSING_CMDS+=("codex")` に追加する
5. `command -v codex` が成功している場合は現状通りスキップ（冪等）

### 境界条件

| 条件 | 出力 | 終了 |
|---|---|---|
| codex 導入済み | ok "codex CLI (\<ver\>)" | 継続 |
| codex 未導入 + npm あり + install 成功 | ok "codex CLI (\<ver\>)" | 継続 |
| codex 未導入 + npm あり + install 失敗 | fail (MISSING_CMDS 追加) | 継続 |
| codex 未導入 + npm なし | fail (npm 必要) | 継続 |

---

## SPEC-03.3-02 — Codex 認証の手動ステップ明示

**対応 REQ:** REQ-03.3-01  
**対象:** README.md / setup/850-codex.sh コメント

### 振る舞い

1. setup/850-codex.sh は `codex login` 状態を確認しない（verify が担当: SPEC-03.3-04）
2. README の「ワンライナー後の手動ステップ」セクションに `codex login` を記載する（SPEC-03.3-05 で規定）

---

## SPEC-03.3-03 — 401-ollama.sh: OLLAMA_HOST 疎通確認への変更

**対応 REQ:** REQ-03.3-02  
**自動化対象:** setup/401-ollama.sh（現状: zstd + WSL2内 Ollama インストール）

### OLLAMA_HOST 値形式

`OLLAMA_HOST` は `http://<WinIP>:11434` 形式（`http://` プレフィックスを含む）とする。
未設定時のデフォルトは `http://localhost:11434`。

### 振る舞い

1. WSL2内 Ollama インストール処理（zstd インストール・`curl ... install.sh | sh`）を削除する
2. `OLLAMA_HOST` 環境変数が未設定の場合:
   - warn: `"OLLAMA_HOST が未設定です。Windows ホスト Ollama を使う場合は OLLAMA_HOST=http://<WinIP>:11434 を設定してください"`
   - 疎通確認はスキップして処理を継続する
3. `OLLAMA_HOST` が設定されている場合:
   - `curl -s --max-time 5 "${OLLAMA_HOST}/api/version" > /dev/null 2>&1` で疎通確認する
   - 成功: `ok "OLLAMA_HOST 疎通確認 OK ($OLLAMA_HOST)"`
   - 失敗: warn `"OLLAMA_HOST ($OLLAMA_HOST) への疎通が失敗しました。Windows ホスト Ollama が起動しているか確認してください"`
4. 疎通失敗でも setup を中断しない（非ゼロ終了しない）

### 境界条件

| 条件 | 出力 | 終了 |
|---|---|---|
| OLLAMA_HOST 未設定 | warn | 継続 |
| OLLAMA_HOST 設定済み + 疎通成功 | ok | 継続 |
| OLLAMA_HOST 設定済み + 疎通失敗（5秒タイムアウト含む） | warn | 継続 |

### 対象外

- WSL2内 `ollama serve` の起動・常駐化（Windows ホストが前提: REQ-01-02）
- OLLAMA_HOST の自動検出（Windows IP は環境依存のため手動設定）

---

## SPEC-03.3-04 — setup/900-verify.sh の新設

**対応 REQ:** REQ-03.3-03  
**自動化対象:** 新規ファイル setup/900-verify.sh

### 実行方式

`900-verify.sh` は **スタンドアロン実行専用** スクリプトとする（`bash setup/900-verify.sh` で直接呼び出す）。
既存の setup モジュール（850-codex.sh 等）と異なり、source ガードを持たず、`ok`/`fail`/`warn` 関数を自前定義する。
setup.sh からは source ではなく `bash setup/900-verify.sh` として呼び出す。

### チェック項目・判定・出力

OLLAMA_HOST の値形式は SPEC-03.3-03 で規定した `http://<WinIP>:11434` 形式を前提とする。

| # | チェック対象 | 成功出力 | 失敗判定 | 失敗時出力 |
|---|---|---|---|---|
| 1 | OLLAMA_HOST 疎通（`curl -s --max-time 5 "$OLLAMA_HOST/api/version"`） | `[OK]  OLLAMA_HOST 疎通` | **fail** | `[FAIL] OLLAMA_HOST ($OLLAMA_HOST) 疎通不可 — Windows Ollama を確認` |
| 2 | Codex CLI インストール（`command -v codex`） | `[OK]  codex CLI` | warn | `[WARN] codex CLI 未インストール — npm install -g @openai/codex` |
| 3 | Codex 認証済み（UND-03.3-01 参照） | `[OK]  codex 認証済み` | warn | `[WARN] codex 未認証 — codex login を実行してください` |
| 4 | `~/.claude/hooks/error-detector.sh` 存在・実行可能 | `[OK]  error-detector.sh` | warn | `[WARN] ~/.claude/hooks/error-detector.sh が存在しないか実行不可` |
| 5 | 必要モデルの存在（UND-03.3-02 参照、`curl $OLLAMA_HOST/api/tags` で確認） | `[OK]  必要モデル確認済み` | warn | `[WARN] 不足モデル: <モデル名> — ollama pull <モデル名> を実行してください` |
| 6 | rclone 設定（`rclone listremotes` で pCloud 確認、UND-03.3-03 参照） | `[OK]  rclone pCloud 設定済み` | info | `[INFO] rclone pCloud 未設定 — 手動設定: README 参照` |

### 終了コード

- fail 判定が 1 件以上あった場合: 非ゼロ終了（exit 1）
- warn / info のみの場合: ゼロ終了（exit 0）

---

## SPEC-03.3-05 — README の「ワンライナー後の手動ステップ」追記

**対応 REQ:** REQ-03.3-04  
**対象:** README.md（リポジトリ root）

### 追記する内容

README.md のワンライナー手順直後に以下のセクションを追加する:

````markdown
### ワンライナー後の手動ステップ

setup 完了後、以下を順に実施してください:

1. **Codex ログイン**: `codex login`（ChatGPT アカウントでの認証が必要）
2. **rclone 設定**（pCloud を使う場合）: `rclone config` — pCloud リモートを追加
3. **knowledge-rag API 設定**: `~/.local/share/knowledge-rag/config.json` に API キーを記載
4. **Ollama モデル pull**（必要に応じて）: `ollama pull deepseek-r1:8b`

### setup 後の状態確認

```bash
bash setup/900-verify.sh
```

OLLAMA_HOST 疎通・Codex 認証・error-detector・必要モデルの状態を一括表示します。
````

### 境界条件

- 既存のワンライナーセクションを変更しない（追記のみ）
- 手動ステップの順序は `codex login` を最初に置く（他のステップに依存しないため）
- rclone 設定を手動ステップ 2 番目に明示する（REQ-03.3-04 で明示が要求されている）

---

## 未確定事項

| # | 事項 | 影響範囲 | 対応方針 |
|---|---|---|---|
| UND-03.3-01 | Codex 認証確認コマンド（`codex auth status` 相当）の存在 | SPEC-03.3-04 チェック項目3 | impl-plan フェーズで `codex --help` / 実機確認。存在しなければ `~/.codex/auth.json` の存在確認に代替 |
| UND-03.3-02 | 必要モデル一覧の確定（deepseek-r1:8b 以外に必要なモデルは？） | SPEC-03.3-04 チェック項目5 | core-03.1 impl-plan 確定後に照合して確定 |
| UND-03.3-03 | rclone の確認コマンド（`rclone listremotes` が使えない場合の代替） | SPEC-03.3-04 チェック項目6 | 実機確認。`rclone listremotes 2>/dev/null` は失敗しても info なので許容範囲 |
