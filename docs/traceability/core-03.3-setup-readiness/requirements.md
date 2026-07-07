# Requirements: Core 03.3 — ワンライナー展開後の実行可能状態保証

> 人間確認済み: 2026-07-07

## 背景

ワンライナー実行後に、Codex CLI、OLLAMA_HOST 疎通、hooks、手動認証、verify が一貫した
動作可能状態として保証されていない。setup が成功扱いでも、MAGI がフォールバック頼みになる、
Codex 実装が使えない、自動エラー検知が無効になる可能性がある。

関連リポジトリ目的: 新規環境へのワンライナー展開、1スキル1ローカルLLM、Codex実装・Claudeオーケストラ、共通設定の再現可能な展開

関連Fable項目: 02, 05, 08, 09, 10, 12（05 は core-03.2 とも重複、02 は core-03.1 とも重複）

## 適用前提（他 core で確定済み）

- REQ-01-02: WSL2 環境では **Windows ホスト Ollama** が前提（OLLAMA_HOST=\<WinIP\>:11434）→ WSL2 内 `ollama serve` 不要
- REQ-03.1-05: `setup/800-ollama-models.sh` は削除または無効化（WSL2内 pull 不要。core-03.1 担当）
- REQ-03.2-04: `~/.claude/hooks/error-detector.sh` への配備（core-03.2 担当）。core-03.3 は verify 組み込みを担当

## 問題

| ID | 問題 |
|---|---|
| PROB-03.3-01 | `setup/850-codex.sh` が `command -v codex` の確認と失敗表示のみ。Codex CLI の自動インストール処理がない |
| PROB-03.3-02 | `setup/401-ollama.sh` がローカルインストールまでで止まり、OLLAMA_HOST（Windows ホスト）への疎通確認をしない。Windows ホスト Ollama が起動しているかを検知できない |
| PROB-03.3-03 | `~/.claude/hooks/error-detector.sh` の存在・実行可能性を setup 完了フローで確認しない（配備自体は REQ-03.2-04） |
| PROB-03.3-04 | `setup.sh` に `--verify` / `setup/900-verify.sh` がなく、setup 後の統合状態（Codex・Ollama・hooks）確認手段がない |
| PROB-03.3-05 | README にワンライナー後の手動ステップ（rclone 認証・Codex ログイン・knowledge-rag API 設定等）のチェックリストがない |
| PROB-03.3-06 | `setup/800-ollama-models.sh` 削除後（REQ-03.1-05）、必要モデル（deepseek-r1:8b 等）の確認・pull 手段がなくなる |

## 確定した要求

| # | 要求 | 根拠 |
|---|---|---|
| REQ-03.3-01 | `setup/850-codex.sh` で Codex CLI を自動インストールする。認証（`codex login`）は手動ステップとして README に明示する | PROB-03.3-01 / Fable 08 / 2026-07-07 確定 |
| REQ-03.3-02 | `setup/401-ollama.sh` の WSL2 内 Ollama インストール処理を削除し、OLLAMA_HOST への疎通確認に置き換える。疎通失敗時は warn を出す | PROB-03.3-02 / Fable 09 / REQ-01-02 / 2026-07-07 確定 |
| REQ-03.3-03 | `setup/900-verify.sh` を新設し、以下を一括確認する。fail = OLLAMA_HOST 疎通不可のみ。warn = Codex 未認証・error-detector 欠落・必要モデル不足。info = rclone 未設定等 | PROB-03.3-03, 04, 06 / Fable 05, 10, 02 / 2026-07-07 確定 |
| REQ-03.3-04 | README に「ワンライナー後の手動ステップ一覧」と「`setup/900-verify.sh` 実行案内」を記載する（rclone 認証・Codex ログイン・knowledge-rag API 設定・Ollama モデル pull） | PROB-03.3-05, 06 / Fable 12 / 2026-07-07 確定 |

### verify チェック項目と fail/warn/info 境界（REQ-03.3-03 詳細）

| チェック項目 | 判定 | 根拠 |
|---|---|---|
| OLLAMA_HOST への疎通（curl/ping） | fail（非ゼロ終了） | MAGI が全面動作不能になるため |
| Codex CLI のインストール済み確認 | warn | 手動 install で回復可能 |
| `codex login` 済み確認 | warn | 手動認証で回復可能 |
| `~/.claude/hooks/error-detector.sh` 存在・実行可能 | warn | core-03.2 REQ-03.2-04 の受け入れ確認 |
| 必要モデル（deepseek-r1:8b 等）の存在確認 | warn | 手動 pull で回復可能。pull 自体は verify の範囲外 |
| rclone 設定・pCloud マウント | info | 記録層は rclone 不要（REQ-03.2-03） |

## 受け入れ条件

- 素の新規環境でワンライナー実行後、Codex CLI がインストールされている（`command -v codex` が成功する）
- `setup/401-ollama.sh` が OLLAMA_HOST への疎通確認を行い、失敗時に warn を出す（WSL2 内 Ollama インストールは行わない）
- `setup/900-verify.sh` が存在し、実行すると Codex・Ollama・hooks・モデルの状態を一括表示する
- OLLAMA_HOST 疎通失敗時のみ verify が非ゼロ終了する
- Codex 未認証・error-detector 欠落・モデル不足は warn として表示し、verify は継続する
- README にワンライナー後の手動ステップ一覧と verify 実行案内がある

## 対象外

- `setup/800-ollama-models.sh` の削除 → REQ-03.1-05（core-03.1 担当）
- `error-detector.sh` の `hooks/` への配備 → REQ-03.2-04（core-03.2 担当）
- verify での必要モデル自動 pull（大容量のためデフォルト off。README 手動案内のみ）
- knowledge-rag API 設定の自動化 → 手動ステップとして README に明示するのみ
- verify のテスト実装（新規環境での動作確認）→ test フェーズ（Step 8）
- CI での verify 自動実行 → core-03.4（継続保証）が担当

## 依存関係

- core-01 REQ-01-02（WindowsホストOllama が前提）→ approved ✅（setup/401-ollama.sh 疎通確認に変更する根拠）
- core-03.1 REQ-03.1-05（setup/800-ollama-models.sh 削除）→ approved ✅（削除後の代替手段として verify での warn を位置付け）
- core-03.2 REQ-03.2-04（error-detector.sh 配備）→ approved ✅（verify の確認対象として組み込む前提）
- core-03.4（CI・verify の継続保証）→ verify 自動実行は core-03.4 が担当

## 人間確認事項（全件解決済み）

| 確認事項 | 決定 | 日付 |
|---|---|---|
| Codex CLI の自動インストール | 自動インストール。認証は手動ステップとして README に明示 | 2026-07-07 |
| setup/401-ollama.sh の役割 | WSL2内インストール削除、OLLAMA_HOST 疎通確認のみに変更 | 2026-07-07 |
| verify の fail / warn 境界 | fail = OLLAMA_HOST 疎通不可のみ。warn = Codex 未認証・hooks 欠落・モデル不足 | 2026-07-07 |
| 必要モデルの pull 方式 | verify で warn 表示。pull は README 手動案内のみ（自動 pull なし） | 2026-07-07 |
