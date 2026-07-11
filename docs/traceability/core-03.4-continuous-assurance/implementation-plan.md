# Implementation Plan: Core 03.4 — ドキュメント・CI・verify による継続保証

> ステータス: approved（2026-07-08 Codex レビュー対応済み）
> 対応 specification: approved 2026-07-08

---

## 変更対象ファイル

| ファイル | 変更種別 | 対応 SPEC |
|---|---|---|
| `.gitignore` | 追記 | SPEC-03.4-01 |
| `.github/pull_request_template.md` | 新規 | SPEC-03.4-02 |
| `.github/workflows/ci.yml` | 新規 | SPEC-03.4-04 |
| `skills/finished-pr/references/phases.md` | 変更（Phase 6.5 追加） | SPEC-03.4-03 |

---

## 実装前に決めるべきこと

**blockers: なし。**

SPEC-03.4 の全 SPEC に未確定事項なし（specification.md の「未確定事項」セクションがすべて解決済み）。

---

## 作業単位と PR 分割

### PR-A: `.gitignore` に4エントリ追加

**対応 SPEC:** SPEC-03.4-01  
**対応 IMPL:** IMPL-03.4-01  
**変更ファイル:** `.gitignore`（1ファイル追記のみ）  
**実行方法:** `/codegen` + `/magi-fast` + `/commit`（軽微な単発変更）

#### IMPL-03.4-01: `.gitignore` 追記

現在の `.gitignore` 末尾（`*.pyc` の後）に以下を追記する:

```
# Codex CLI 設定（マシン固有）
.codex/

# ローカル固有設定（個人・マシン固有）
CLAUDE.local.md

# 一時的な監査ドキュメント
docs/audit-*/

# ローカル調査スクリプト
scripts/index-investigations.sh
```

#### 検証手順

```bash
# 4エントリの存在確認
grep -q "^\.codex/" .gitignore          && echo "OK: .codex/" || echo "FAIL: .codex/ missing"
grep -q "^CLAUDE\.local\.md" .gitignore && echo "OK: CLAUDE.local.md" || echo "FAIL"
grep -q "^docs/audit-\*/" .gitignore    && echo "OK: docs/audit-*/" || echo "FAIL"
grep -q "^scripts/index-investigations\.sh" .gitignore && echo "OK: scripts/index-investigations.sh" || echo "FAIL"

# 追記のみ確認（削除行なし）
_del=$(git diff HEAD -- .gitignore | grep -c '^-[^-]' 2>/dev/null || echo 0)
test "$_del" -eq 0 && echo "OK: 削除行なし（追記のみ確認）" || echo "FAIL: ${_del} 行削除されている"

# git status から消えるか（4件すべて非表示になること）
git status --short | grep -E "^\?\? (\.codex|CLAUDE\.local\.md|scripts/index-investigations\.sh)" \
  && echo "FAIL: まだ git status に表示されている" || echo "OK: .codex・CLAUDE.local.md・index-investigations.sh 非表示確認"
# docs/audit-*/ はローカルに存在しない場合は確認スキップ可（パターン追加の確認は grep で済む）
```

---

### PR-B1: `.github/pull_request_template.md` 新設

**対応 SPEC:** SPEC-03.4-02  
**対応 IMPL:** IMPL-03.4-02  
**変更ファイル:** `.github/pull_request_template.md`（新規）  
**実行方法:** `/codegen` + `/magi-fast` + `/commit`（軽微な単発変更）  
**依存:** PR-A に依存しない（独立）

#### IMPL-03.4-02: `.github/pull_request_template.md` 新設

`.github/` ディレクトリを新設し、以下の内容でファイルを配置する:

```markdown
## ドキュメント更新チェック

実装変更を含む PR のみ記入してください:

- [ ] `README.md` — 使い方・セットアップ手順に変更があれば更新済み
- [ ] `DESIGN.md` — アーキテクチャ・設計に変更があれば更新済み
- [ ] `SKILLS.md` — スキル一覧に変更があれば更新済み
- [ ] 上記いずれも変更不要（ドキュメント影響なし）
```

#### 検証手順

```bash
# PR テンプレート確認
test -f .github/pull_request_template.md && echo "OK: ファイル存在" || echo "FAIL"
grep -q "README\.md" .github/pull_request_template.md && echo "OK: README チェック" || echo "FAIL"
grep -q "DESIGN\.md" .github/pull_request_template.md && echo "OK: DESIGN チェック" || echo "FAIL"
grep -q "SKILLS\.md"  .github/pull_request_template.md && echo "OK: SKILLS チェック"  || echo "FAIL"
grep -q "変更不要"    .github/pull_request_template.md && echo "OK: 変更不要チェック" || echo "FAIL"
```

---

### PR-B2: `.github/workflows/ci.yml` 新設

**対応 SPEC:** SPEC-03.4-04  
**対応 IMPL:** IMPL-03.4-03  
**変更ファイル:** `.github/workflows/ci.yml`（新規）  
**実行方法:** `/codegen` + `/magi-fast` + `/commit`（軽微な単発変更）  
**依存:** PR-B1 に依存しない（独立）。PR-B1 → PR-B2 の順が推奨（`.github/` ディレクトリが先に存在するとわかりやすい）

#### IMPL-03.4-03: `.github/workflows/ci.yml` 新設

トリガー: `push` on `main`、`pull_request`（全ブランチ）

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  shellcheck:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install shellcheck
        run: sudo apt-get install -y shellcheck
      - name: Run shellcheck
        run: |
          find . -name "*.sh" \
            -not -path "./.git/*" \
            -not -path "./worktree/*" \
            | xargs shellcheck -S error

  smoke-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run smoke tests
        run: |
          bash scripts/test-magi-diff-filter.sh
          bash scripts/test-magi-format.sh
```

除外:
- `scripts/test-function-calling.sh`: Ollama 依存（requirements.md 確定済み）
- `setup/900-verify.sh`: OLLAMA_HOST 依存（requirements.md 確定済み）

#### 検証手順

```bash
# ci.yml 存在・トリガー・ジョブ確認
test -f .github/workflows/ci.yml && echo "OK: ci.yml 存在" || echo "FAIL"
grep -q "push"         .github/workflows/ci.yml && echo "OK: push トリガー" || echo "FAIL"
grep -q "pull_request" .github/workflows/ci.yml && echo "OK: PR トリガー"   || echo "FAIL"
grep -q "Install shellcheck" .github/workflows/ci.yml && echo "OK: shellcheck インストールステップ" || echo "FAIL"
grep -q "shellcheck"   .github/workflows/ci.yml && echo "OK: shellcheck job" || echo "FAIL"
grep -q "\-S error"    .github/workflows/ci.yml && echo "OK: -S error フラグ" || echo "FAIL"
grep -q "test-magi-diff-filter\.sh" .github/workflows/ci.yml && echo "OK: smoke filter" || echo "FAIL"
grep -q "test-magi-format\.sh"      .github/workflows/ci.yml && echo "OK: smoke format" || echo "FAIL"

# 除外確認
grep -q "test-function-calling\.sh" .github/workflows/ci.yml \
  && echo "FAIL: function-calling が含まれている（除外すべき）" || echo "OK: function-calling 除外確認"
grep -q "900-verify\.sh" .github/workflows/ci.yml \
  && echo "FAIL: verify が含まれている（除外すべき）" || echo "OK: verify 除外確認"
```

---

### PR-C: `/finished-pr` に Phase 6.5: WORKFILES 追加

**対応 SPEC:** SPEC-03.4-03  
**対応 IMPL:** IMPL-03.4-04  
**変更ファイル:** `skills/finished-pr/references/phases.md`（1ファイル変更）  
**実行方法:** `/codegen` + `/magi-fast` + `/commit`（軽微な単発変更）  
**依存:** PR-A, PR-B と独立

#### IMPL-03.4-04: Phase 6.5: WORKFILES 追加

`skills/finished-pr/references/phases.md` の Phase 6（WORKTREE）の後、Phase 7（DONE）の前に以下を追加する:

```markdown
## Phase 6.5: WORKFILES

> 検出コマンドでリポジトリ root の未追跡作業ファイルを列挙し、存在する場合に削除する。

```bash
REPO=$(git rev-parse --show-toplevel)
WORKFILES=$(git -C "$REPO" ls-files --others --exclude-standard \
  | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}-.+\.md$' || true)
```

対象ファイルが存在する場合: Phase 2（CONFIRM）のサマリーに「削除対象作業ファイル」として表示する。

ユーザーが「続行」を選択後:

```bash
while IFS= read -r f; do
  if rm -f "$REPO/$f"; then
    echo "✓ 作業ファイル削除: $f"
  else
    echo "⚠️  作業ファイルの削除に失敗: $f（手動で削除してください）"
    WORKFILES_FAILED="${WORKFILES_FAILED} $f"
  fi
done <<< "$WORKFILES"
```

対象ファイルが存在しない場合: スキップ（メッセージなし）。

削除失敗時は処理継続し、Phase 7（DONE）の完了報告に「⚠️ 手動削除が必要なファイル: $WORKFILES_FAILED」として明記する。
```

**Phase 2（CONFIRM）サマリーへの追記:**

```
[WORKFILES が非空の場合]
- **削除対象作業ファイル**:
  <リスト>
```

**Phase 7（DONE）完了報告への追記:**

```
[WORKFILES_FAILED が非空の場合] - ⚠️ 手動削除が必要なファイル: $WORKFILES_FAILED
[WORKFILES_FAILED が空かつ WORKFILES が非空の場合] - 作業ファイル削除: <ファイル名>
[WORKFILES が空の場合] （WORKFILES フェーズ行なし）
```

**デプロイ:**

PR マージ後:
```bash
cp skills/finished-pr/references/phases.md ~/.claude/skills/finished-pr/references/phases.md
```

#### 検証手順

```bash
# Phase 6.5 存在確認
grep -q "Phase 6\.5" skills/finished-pr/references/phases.md && echo "OK: Phase 6.5 存在" || echo "FAIL"
grep -q "WORKFILES"  skills/finished-pr/references/phases.md && echo "OK: WORKFILES 存在" || echo "FAIL"

# 検出コマンドの存在確認
grep -q "ls-files.*--others.*--exclude-standard" skills/finished-pr/references/phases.md \
  && echo "OK: 検出コマンド存在" || echo "FAIL"

# Phase 順序確認（6.5 が Phase 7 の前に来ること）
_p65=$(grep -n "Phase 6\.5" skills/finished-pr/references/phases.md | cut -d: -f1 | head -1)
_p7=$(grep -n "^## Phase 7" skills/finished-pr/references/phases.md | cut -d: -f1 | head -1)
test -n "$_p65" && test -n "$_p7" && test "$_p65" -lt "$_p7" \
  && echo "OK: Phase 6.5（L${_p65}）< Phase 7（L${_p7}）" || echo "FAIL: 順序異常または存在せず"

# デプロイ確認
diff skills/finished-pr/references/phases.md ~/.claude/skills/finished-pr/references/phases.md \
  > /dev/null 2>&1 && echo "OK: ~/.claude へデプロイ済み" || echo "FAIL: CWD と ~/.claude が不一致"
```

---

## PR 依存関係グラフ

```
PR-A (.gitignore)
  ╌╌→ PR-B1 (PR テンプレート)
        ╌╌→ PR-B2 (CI)
PR-C (finished-pr)
```

- `╌╌→` 推奨順（独立だが先行 PR 完了後が望ましい）
- PR-A, PR-B1, PR-B2, PR-C はすべて技術的に独立。上記は作業の読みやすさのための推奨順
- PR-C は他すべてと完全独立。任意の順で実施可

---

## SPEC → IMPL 対応表

| SPEC ID | IMPL ID | PR | 備考 |
|---|---|---|---|
| SPEC-03.4-01（.gitignore 4エントリ追加） | IMPL-03.4-01 | PR-A | |
| SPEC-03.4-02（PR テンプレート新設） | IMPL-03.4-02 | PR-B1 | |
| SPEC-03.4-03（finished-pr Phase 6.5 追加） | IMPL-03.4-04 | PR-C | デプロイコマンド必須 |
| SPEC-03.4-04（GitHub Actions CI 新設） | IMPL-03.4-03 | PR-B2 | |

## 注意

- `.github/` ディレクトリが未存在のため PR-B1 では `mkdir -p .github/` が必要、PR-B2 では `mkdir -p .github/workflows/` が必要
- `skills/finished-pr/references/phases.md` は CWD が正。直接 `~/.claude/` は変更しない（CLAUDE.local.md ルール）。PR マージ後に `cp` でデプロイする
- `test-function-calling.sh` と `setup/900-verify.sh` は CI から明示的に除外（OLLAMA_HOST 依存）
- Codex レビュー確認（2026-07-08）: 実装本文の `-S error` と検証の `grep -q "\-S error"` は一致している（false positive）
