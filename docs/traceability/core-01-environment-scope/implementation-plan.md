# Implementation Plan: Core 01 — 対応環境スコープ・優先度の確定

> ステータス: approved（2026-07-08 Codex レビュー対応済み）
> 対応 specification: approved 2026-07-08

---

## 変更対象ファイル

| ファイル | 変更種別 | 対応 SPEC |
|---|---|---|
| `README.md` | 追記（対応環境セクション） | SPEC-01-01 |
| `setup/900-verify.sh` | 追記（WSL2 チェック先頭追加） | SPEC-01-02 |
| `DESIGN.md` | 追記（データ集約・転送設計セクション） | SPEC-01-03 |

---

## 実装前に決めるべきこと

**blockers:**

なし。SPEC-01 の全 SPEC に blockers なし。

**非 blocker（実装時に記録・明示する事項）:**

- **UND-03.2-03**: `pcloud-sync.sh` の実行タイミング（cron vs 手動）は未確定。`DESIGN.md` への追記では「実行タイミングは未確定」と明記するにとどめる（core-02 impl-plan で解決予定）

**core 間依存（PR 順序の制約）:**

- **SPEC-01-02 は core-03.3 PR-C に依存**: `setup/900-verify.sh` は core-03.3 PR-C で新設される。SPEC-01-02 の WSL2 チェックを同一 PR・同一ファイルに追加するため、PR-B（SPEC-01-02）は core-03.3 PR-C と同一 PR として扱う（下記参照）

---

## 作業単位と PR 分割

### PR-A: `README.md` 対応環境セクション追加

**対応 SPEC:** SPEC-01-01  
**対応 IMPL:** IMPL-01-01  
**変更ファイル:** `README.md`（追記のみ）  
**実行方法:** `/codegen` + `/magi-fast` + `/commit`（軽微な単発変更）  
**依存:** なし（独立）

#### IMPL-01-01: `README.md` 冒頭への「対応環境」セクション追加

「前提: Claude Code のインストール」セクションの**前**に以下を追加する:

```markdown
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
```

#### 検証手順

```bash
# 必須記述の存在確認
grep -q "## 対応環境" README.md && echo "OK: セクション存在" || echo "FAIL"
grep -q "WSL2" README.md && echo "OK: WSL2 記載" || echo "FAIL"
grep -q "非対応" README.md && echo "OK: Windows非対応記載" || echo "FAIL"
grep -q "OLLAMA_HOST" README.md && echo "OK: OLLAMA_HOST 記載" || echo "FAIL"
grep -q "WindowsホストのIP\|Windowsホスト.*IP" README.md && echo "OK: WindowsホストIP例示" || echo "FAIL"

# 追記のみ確認（削除行なし）
_del=$(git diff HEAD -- README.md | grep -c '^-[^-]' 2>/dev/null || echo 0)
test "$_del" -eq 0 && echo "OK: 削除行なし（追記のみ確認）" || echo "FAIL: ${_del} 行削除されている"

# セクション位置確認（「前提: Claude Code のインストール」より前）
_env=$(grep -n "## 対応環境" README.md | head -1 | cut -d: -f1)
_prereq=$(grep -n "前提.*Claude Code\|Claude Code.*インストール" README.md | head -1 | cut -d: -f1)
test -n "$_env" && test -n "$_prereq" && test "$_env" -lt "$_prereq" \
  && echo "OK: 対応環境（L${_env}）が前提（L${_prereq}）より前" || echo "FAIL: 位置確認"
```

---

### PR-B: `setup/900-verify.sh` へ WSL2 チェック追加

> **⚠️ この PR は core-03.3 PR-C と同一 PR として実施する**

**対応 SPEC:** SPEC-01-02  
**対応 IMPL:** IMPL-01-02  
**変更ファイル:** `setup/900-verify.sh`（SPEC-03.3-04 が新設するファイルへの追記）  
**実行方法:** core-03.3 PR-C の `/dev-flow` 実装時に同時対応  
**依存:** `└→ core-03.3 PR-C`（900-verify.sh が新設されてから実装）

#### IMPL-01-02: WSL2 環境チェックを `setup/900-verify.sh` の先頭に追加

SPEC-03.3-04 の6チェック項目の**先頭（チェック #0）** に以下を追加する:

```bash
# チェック #0: WSL2 環境確認
if [ -n "$WSL_DISTRO_NAME" ]; then
  echo "[OK]  WSL2 環境"
else
  echo "[WARN] WSL2 環境が検出できません — このツールは WSL2 (Linux) 専用です。Windowsネイティブ環境では動作保証しません"
fi
```

判定:
- warn 扱い（スクリプトを非ゼロ終了にしない）
- fail（exit 1）にする条件は OLLAMA_HOST 疎通不可のみ（SPEC-03.3-04 に準拠）

#### 検証手順

```bash
# WSL2 チェックの存在確認
grep -q "WSL_DISTRO_NAME" setup/900-verify.sh && echo "OK: WSL2 チェック存在" || echo "FAIL"
grep -q "WSL2 環境" setup/900-verify.sh && echo "OK: WSL2 環境メッセージ存在" || echo "FAIL"
grep -q "WARN.*WSL2\|WSL2.*WARN" setup/900-verify.sh && echo "OK: WSL2 WARN 記載" || echo "FAIL"

# WSL2 チェックが全チェック中の最初であることを確認（他チェックパターンより先）
_wsl_line=$(grep -n "WSL_DISTRO_NAME" setup/900-verify.sh | head -1 | cut -d: -f1)
_first_other=$(grep -n "OLLAMA_HOST\|codex.*auth\|error-detector\|ollama.*list" setup/900-verify.sh | head -1 | cut -d: -f1)
test -n "$_wsl_line" && test -n "$_first_other" && test "$_wsl_line" -lt "$_first_other" \
  && echo "OK: WSL2（L${_wsl_line}）が他全チェック（L${_first_other}）より先（先頭チェック確認）" || echo "FAIL: WSL2 が先頭でない"

# warn 扱い確認（WSL2 チェックで exit 1 しないこと）
_wsl_block_start=$_wsl_line
sed -n "${_wsl_block_start},$((${_wsl_block_start}+10))p" setup/900-verify.sh \
  | grep "exit 1" && echo "FAIL: WSL2 チェックに exit 1 が含まれている" || echo "OK: exit 1 なし（warn 扱い確認）"
```

---

### PR-C: `DESIGN.md` にデータ集約・転送設計セクション追加

**対応 SPEC:** SPEC-01-03  
**対応 IMPL:** IMPL-01-03  
**変更ファイル:** `DESIGN.md`（追記のみ）  
**実行方法:** `/codegen` + `/magi-fast` + `/commit`（軽微な単発変更）  
**依存:** なし（独立）

#### IMPL-01-03: `DESIGN.md` へ「データ集約・転送設計」セクション追加

DESIGN.md の末尾に以下のセクションを追加する:

```markdown
## データ集約・転送設計

### pCloud が最終集約場所

以下のデータが pCloud Obsidian Vault に集約される:

| データ種別 | ローカル保存先 | pCloud 転送 |
|---|---|---|
| セッションログ | `~/.local/share/knowledge-rag/sessions/` | pcloud-sync.sh 経由（SPEC-03.2-03） |
| 蒸留済み経験カード（日英） | `~/.local/share/knowledge-rag/store/distilled/` | pcloud-sync.sh 経由（SPEC-04-02/03） |
| 調査結果 | `investigations/`（リポジトリ内） | pcloud-sync.sh 経由で pCloud Obsidian Vault へ |
| lessons-learned | `~/.local/share/knowledge-rag/lessons-learned/` | pcloud-sync.sh 経由（SPEC-03.2-05） |

**knowledge-rag DB は各環境ローカル独立**: pCloud Obsidian Vault が正のソースであり、DB は各環境で再構築可能なキャッシュ。新規追記は pCloud 経由で他環境にも伝播する。

### 不変条件 — pCloud への書き込み経路は `pcloud-sync.sh` のみ

rclone FUSE マウント経由でのファイル書き込みは**禁止**する。

- 書き込み: 必ず `scripts/pcloud-sync.sh`（`rclone copy`）経由
- 読み取り: rclone FUSE マウント経由（Obsidian Vault 参照）—`setup/500-pcloud.sh` が担当する WSL2 systemd サービス方式

`pcloud-sync.sh` は FUSE マウントに依存しないため、マウント脱落問題（REQ-01-05）を設計レベルで回避する。

### 一括転送方式

各 WSL コンテナはファイルをまずローカルに保存し、`scripts/pcloud-sync.sh`（`rclone copy <ローカルパス> pcloud:<転送先パス>`）が pCloud へ一括転送する。

実行タイミング（cadence）は未確定（UND-03.2-03 — core-02 impl-plan で解決予定）。

### knowledge-rag DB 再構築

各環境で DB が空または古い場合は、pCloud Obsidian Vault の内容から再インデックスすることで最新化できる。
```

#### 検証手順

```bash
# データ集約・転送設計セクションの存在確認
grep -q "データ集約.*転送設計\|データ集約" DESIGN.md && echo "OK: セクション存在" || echo "FAIL"
grep -q "pcloud-sync\.sh" DESIGN.md && echo "OK: pcloud-sync.sh 記載" || echo "FAIL"
grep -q "rclone copy" DESIGN.md && echo "OK: rclone copy 記載" || echo "FAIL"
grep -q "禁止\|FUSE.*禁止" DESIGN.md && echo "OK: FUSE書き込み禁止記載" || echo "FAIL"
grep -q "各環境ローカル独立\|ローカル独立" DESIGN.md && echo "OK: DB ローカル独立記載" || echo "FAIL"
grep -q "不変条件" DESIGN.md && echo "OK: 不変条件記載" || echo "FAIL"

# 追記のみ確認（削除行なし）
_del=$(git diff HEAD -- DESIGN.md | grep -c '^-[^-]' 2>/dev/null || echo 0)
test "$_del" -eq 0 && echo "OK: 削除行なし（追記のみ確認）" || echo "FAIL: ${_del} 行削除されている"
```

---

## PR 依存関係グラフ

```
PR-A (README.md)     [独立]
PR-C (DESIGN.md)     [独立]

core-03.3 PR-C       [900-verify.sh 新設]
  └→ PR-B（WSL2 チェック — core-03.3 PR-C に同一 PR として組み込む）
```

- PR-A と PR-C は**完全独立**。任意の順で実施可（core-03.3 PR-C とも独立）
- PR-B は独立した PR ではなく、core-03.3 PR-C の実装スコープに含める
  - core-03.3 PR-C: `setup/900-verify.sh` 新設 + `setup.sh` 呼び出し追加 + `README.md` 追記 + **SPEC-01-02 の WSL2 チェック追加**

---

## SPEC → IMPL 対応表

| SPEC ID | IMPL ID | PR | 備考 |
|---|---|---|---|
| SPEC-01-01（README 対応環境セクション） | IMPL-01-01 | PR-A | |
| SPEC-01-02（900-verify.sh WSL2 チェック） | IMPL-01-02 | core-03.3 PR-C | core-03.3 PR-C と同一 PR |
| SPEC-01-03（DESIGN.md pCloud 集約設計） | IMPL-01-03 | PR-C | |

## 注意

- SPEC-01-02 の実装先は core-01 の PR ではなく **core-03.3 PR-C**。core-03.3 PR-C のレビュー時に SPEC-01-02 の検証手順も合わせて実施すること
- `pcloud-sync.sh` の実行タイミング（UND-03.2-03）は DESIGN.md での「未確定」記載にとどめる（blocker ではない）
- README.md と DESIGN.md はともに追記のみ。既存セクションを変更しない
