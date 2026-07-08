# Specification Draft: Core 03.4 — ドキュメント・CI・verify による継続保証

> ステータス: approved（2026-07-08）
> 対応 requirements: approved 2026-07-07

---

## SPEC-03.4-01 — .gitignore への追加

**対応 REQ:** REQ-03.4-02  
**自動化対象:** `.gitignore`（リポジトリ root）

### 振る舞い

`.gitignore` に以下の4エントリを追加する（既存エントリの後に追記）:

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

### 境界条件

- 追加後、`git status` に上記ファイルが表示されない
- 既存エントリへの変更なし（追記のみ）
- `docs/audit-*/` とパターン化することで将来の audit ディレクトリにも対応する

---

## SPEC-03.4-02 — PR テンプレートのドキュメント更新チェックリスト

**対応 REQ:** REQ-03.4-01  
**自動化対象:** `.github/pull_request_template.md`（新規ファイル）

### 振る舞い

`.github/pull_request_template.md` を新設する。PR 作成時に GitHub が自動でテンプレートを挿入する。

テンプレートの必須チェック項目:

```markdown
## ドキュメント更新チェック

実装変更を含む PR のみ記入してください:

- [ ] `README.md` — 使い方・セットアップ手順に変更があれば更新済み
- [ ] `DESIGN.md` — アーキテクチャ・設計に変更があれば更新済み
- [ ] `SKILLS.md` — スキル一覧に変更があれば更新済み
- [ ] 上記いずれも変更不要（ドキュメント影響なし）
```

### 境界条件

- `.github/` ディレクトリが存在しない場合: ディレクトリを新設してファイルを配置する
- チェックリストは強制ではない（CI で未チェックを fail にしない）。人間の目視確認を促す方式
- ドキュメントのみの PR（コード変更なし）でも表示されるが、「変更不要」チェックで対応可

### 対象外

- チェックリスト未記入 / 全未チェックを CI で自動検出・fail にする（自動化は将来拡張）

---

## SPEC-03.4-03 — /finished-pr スキルへの作業ファイル削除ステップ追加

**対応 REQ:** REQ-03.4-03  
**対象:** `~/.claude/skills/finished-pr/references/phases.md`

### 現状確認

finished-pr は既に以下を持つ:
- Phase 4: BRANCH — ローカル・リモートブランチ削除 ✅
- Phase 6: WORKTREE — worktree 削除（使用時のみ） ✅

**不足している部分:** セッション中に生成された一時的な「作業ファイル」の削除（例: `YYYY-MM-DD-session-summary.md` 等）

### 作業ファイルの定義

「作業ファイル」とは、以下の条件を**すべて満たす**ファイルを指す:

- repo root（`~/srcs/Claude-StartUp/`）直下に存在する
- ファイル名が `YYYY-MM-DD-*.md` パターンに一致する（例: `2026-07-03-session-summary.md`）
- `.gitignore` の対象外（未追跡ファイル）

検出コマンド: `git -C "$REPO" ls-files --others --exclude-standard | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}-.+\.md$'`

### 追加する振る舞い

Phase 7（DONE）の前に **Phase 6.5: WORKFILES** を追加する:

1. 上記検出コマンドで対象ファイルを列挙する
2. 対象ファイルが存在する場合: Phase 2（CONFIRM）のサマリーに「削除対象作業ファイル」として表示する
3. ユーザーが「続行」を選択後: 対象ファイルを削除する
4. 対象ファイルが存在しない場合: スキップ（メッセージなし）

### 境界条件

| 条件 | 動作 |
|---|---|
| 削除対象ファイルあり + 削除成功 | `✓ 作業ファイル削除: <ファイル名>` |
| 削除対象ファイルなし | スキップ（メッセージなし） |
| 削除失敗 | `⚠️ 作業ファイルの削除に失敗: <ファイル名>（手動で削除してください）` → Phase 7（DONE）で未完として報告 |

削除失敗時も処理は継続する。Phase 7 の完了報告に「⚠️ 手動削除が必要なファイル」として明記する（phases.md の WORKTREE_REMOVED=false パターンと同様）。

---

## SPEC-03.4-04 — GitHub Actions CI 新設

**対応 REQ:** REQ-03.4-04  
**自動化対象:** `.github/workflows/ci.yml`（新規ファイル）

### トリガー

- `push` on `main` ブランチ
- `pull_request` (全ブランチ)

### ジョブ構成

#### job: shellcheck

```yaml
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
```

- `-S error` により error レベルのみ fail。warning / info は無視
- worktree/ 以下はスキップ

#### job: smoke-test

```yaml
runs-on: ubuntu-latest
steps:
  - uses: actions/checkout@v4
  - name: Run smoke tests
    run: |
      bash scripts/test-magi-diff-filter.sh
      bash scripts/test-magi-format.sh
```

- `scripts/test-function-calling.sh` は Ollama 依存のため **スキップ**（requirements.md で確定済み）
- `setup/900-verify.sh` は OLLAMA_HOST 依存のため **スキップ**

### 境界条件

| 条件 | 判定 |
|---|---|
| shellcheck が error を検出 | CI fail |
| shellcheck が warning のみ | CI 継続（pass） |
| smoke test が非ゼロ終了 | CI fail |
| smoke test が正常終了 | CI pass |
| OLLAMA_HOST 依存のテスト | スキップ（明示的に除外） |

### 対象外

- `setup/900-verify.sh` の CI 自動実行（OLLAMA_HOST 依存: REQ-03.4-04 対象外と明記）
- ドキュメント整合の自動チェック（将来拡張）

---

## 未確定事項

未確定事項はありません。

（解決済み記録）
- ~~UND-03.4-01~~: 作業ファイルパターン → SPEC-03.4-03 本文で `YYYY-MM-DD-*.md`（repo root、未追跡）と定義して確定
- ~~UND-03.4-02~~: `test-function-calling.sh` の CI 実行可否 → requirements.md で「Ollama 依存テストはスキップ」と確定済み
- ~~UND-03.4-03~~: `DESIGN.md` / `SKILLS.md` の存在 → 両ファイル存在確認済み（2026-07-08）
