# Specification Draft: Core 01 — 対応環境スコープ・優先度の確定

> ステータス: approved（2026-07-08 SPEC-01-03 追補・人間承認済み）
> 対応 requirements: approved 2026-07-07

---

## SPEC-01-01 — README への「対応環境」セクション追加

**対応 REQ:** REQ-01-01, REQ-01-02, REQ-01-07  
**対象:** README.md（リポジトリ root）

### 振る舞い

README.md の冒頭（「Claude Code のインストール」セクションの前）に以下のセクションを追加する:

````markdown
## 対応環境

| 環境 | サポート | 備考 |
|---|---|---|
| WSL2 (Ubuntu) | ✅ サポート対象 | 標準構成 |
| Linux ネイティブ | 未検証 | |
| macOS | 未検証 | |
| Windows ネイティブ (Git Bash 含む) | ❌ 非対応 | bash/systemd 依存のため |

### 標準構成: WindowsホストOllama

WSL2 内で Ollama を起動するのではなく、**Windows ホスト側の Ollama を使用する**ことを標準とする。

セットアップ前に環境変数を設定してください:

```bash
# ~/.bashrc または ~/.bash_profile に追加
export OLLAMA_HOST=http://<WindowsホストのIP>:11434
```

Windows ホスト側で Ollama を起動し、`OLLAMA_HOST` への疎通確認は `setup/900-verify.sh` で実施します。
````

### 境界条件

- 既存の「前提: Claude Code のインストール」セクションは変更しない（追加のみ）
- WindowsホストIPは環境依存のため固定値を書かない（`<WindowsホストのIP>` のまま）
- `OLLAMA_HOST` のプロトコル（`http://`）を含めた形式で例示する（SPEC-03.3-03 と整合）

---

## SPEC-01-02 — setup/900-verify.sh への WSL2 環境チェック追加

**対応 REQ:** REQ-01-01, REQ-01-07  
**対象:** setup/900-verify.sh（core-03.3 SPEC-03.3-04 で新設するスクリプトへの追加）

### 振る舞い

SPEC-03.3-04 のチェック項目リストの先頭に以下のチェックを追加する:

| # | チェック対象 | 成功出力 | 失敗判定 | 失敗時出力 |
|---|---|---|---|---|
| 0 | WSL2 環境確認（`$WSL_DISTRO_NAME` が設定されているか） | `[OK]  WSL2 環境` | warn | `[WARN] WSL2 環境が検出できません — このツールは WSL2 (Linux) 専用です。Windowsネイティブ環境では動作保証しません` |

- WSL2 検出: `[ -n "$WSL_DISTRO_NAME" ]` で判定する
- warn 扱い（非ゼロ終了にしない）: OLLAMA_HOST 疎通不可のみが fail のため、環境不一致は warn にとどめる

### 境界条件

| 条件 | 出力 | 終了 |
|---|---|---|
| WSL2 環境（$WSL_DISTRO_NAME が設定されている） | [OK]  WSL2 環境 | 継続 |
| WSL2 以外（$WSL_DISTRO_NAME が未設定） | [WARN] WSL2 環境が検出できません | 継続 |

### 依存

SPEC-03.3-04（setup/900-verify.sh 新設）に対する**追加仕様**。
impl-plan では core-03.3 の 900-verify.sh 実装と同一 PR・同一ファイルで対応する。

---

## SPEC-01-03 — DESIGN.md への pCloud 集約設計の明記

**対応 REQ:** REQ-01-03, REQ-01-04, REQ-01-05, REQ-01-06  
**対象:** DESIGN.md（リポジトリ root）

### 振る舞い

DESIGN.md に「データ集約・転送設計」セクションを追加する。記述する内容:

1. **pCloud が最終集約場所**: 以下のデータが pCloud に集約される:
   - セッションログ（ローカル: `~/.local/share/knowledge-rag/sessions/`。詳細: SPEC-03.2-03）
   - 蒸留済み経験カード（ローカル: `~/.local/share/knowledge-rag/store/distilled/`、日英両方。詳細: SPEC-04-02/03）
   - 調査結果（リポジトリ内: `investigations/`。pcloud-sync.sh で pCloud Obsidian Vault へ転送）
   - lessons-learned（ローカル: `~/.local/share/knowledge-rag/lessons-learned/`。詳細: SPEC-03.2-05）
   - Obsidian Vault → pCloud が正。rclone FUSE マウント経由でアクセス
   - knowledge-rag DB → **各環境ローカル独立**（pCloud Obsidian Vault が正のソースであり、DB は各環境で再構築可能なキャッシュ。新規追記はpCloud経由で他環境にも伝播する）
2. **不変条件 — pCloud への書き込み経路は `pcloud-sync.sh` のみ**: rclone FUSE マウント経由でのファイル書き込みは禁止する。書き込みは必ず `scripts/pcloud-sync.sh`（`rclone copy`）経由で行う。FUSE マウントは読み取り専用用途（Obsidian Vault 参照）に限定する
3. **一括転送方式**: 各 WSL コンテナはファイルをまずローカルに保存し、`scripts/pcloud-sync.sh`（新規）が `rclone copy` で pCloud へ一括転送する
   - `pcloud-sync.sh` は **FUSE マウントに依存しない**（マウント脱落問題の回避: REQ-01-05 解決）
   - `rclone copy <ローカルパス> pcloud:<転送先パス>` を使用する
   - 実行タイミング（cadence）は未確定（UND-03.2-03 参照）
4. **rclone FUSE マウント（Obsidian Vault 読み取り用）**: `setup/500-pcloud.sh` が担当する WSL2 systemd サービス方式。ファイル転送（pcloud-sync.sh）とは独立した系統として明記する
5. **knowledge-rag DB 再構築**: 各環境で DB が空または古い場合は、pCloud Obsidian Vault の内容から再インデックスすることで最新化できることを明記する

### 境界条件

- DESIGN.md の既存セクションを変更しない（追記のみ）
- `pcloud-sync.sh` が rclone copy を使用する前提で、FUSE マウント状態に関わらず転送が成功することをテスト可能

---

## 未確定事項

未確定事項はありません。

（解決済み記録）
- ~~REQ-01-05~~: pcloud-sync.sh が `rclone copy` を使用するため FUSE マウント依存を排除。マウント脱落問題を設計レベルで回避（2026-07-08 確定）
- ~~REQ-01-06~~: knowledge-rag DB は各環境ローカル独立。pCloud Obsidian Vault が正のソース → DB は再構築可能なキャッシュとして扱う（2026-07-08 確定）
