# 初回還流棚卸し記録 — 2026-07-11

> core-02 受け入れ条件「初回の還流棚卸しが実施され、MM ファイルの取捨判断が記録されている」の充足記録
> 監査 A-001 解消確認: この記録をもって A-001 を「解消」に更新（traceability-audit.md 参照）
> TEST-02-03-11（実環境での実行確認）の実施記録を兼ねる

## 実施概要

| 項目 | 内容 |
|---|---|
| 実施日 | 2026-07-11 |
| 実施者 | ユーザー（手動実行・取捨判断）|
| 実施方法 | `bash scripts/sync-check.sh`（実環境 `~/.claude/` vs 配布原本 `~/srcs/Claude-StartUp/`） |
| 結果概要 | **新規 21件・変更 4件・exit 1** |

---

## sync-check 実行結果

```
=== 要還流（新規）: 実働環境にのみ存在 ===
  commands/Claude.md
  commands/dev.md
  hooks/error-detector.sh
  hooks/lean-ctx-redirect.sh
  hooks/lean-ctx-rewrite.sh
  hooks/lessons-learned-stop.sh
  hooks/test-sessionstart-compact.sh
  rules/lean-ctx.md
  scripts/magi-split-diff.sh
  skills/balthasar/references/output-format.md
  skills/casper/references/output-format.md
  skills/code-review/
  skills/codegen/codegen/
  skills/codegen/references/references/
  skills/investigate/
  skills/lean-ctx/
  skills/melchior/references/output-format.md
  skills/metatron/references/output-format.md
  skills/ollama-run.sh
  skills/sandalphon/references/output-format.md
  skills/skill-creator/

=== 要還流（変更）: 両側に存在するが差分あり ===
  CLAUDE.md
  dotfiles/ccstatusline-settings.json
  skills/magi-hard/SKILL.md
  skills/pr-review-respond/SKILL.md

exit 1（要還流あり）
```

> agents/leliel.md は現時点で両側同一のため出力に現れない（削除予定分類は core-03.1 で repo 側から削除され live のみに残った時点で発動する）

---

## 取捨判断（ユーザー確定 2026-07-11）

| 対象 | 判断 | 理由・注記 |
|---|---|---|
| `CLAUDE.md`（変更） | **還流しない** | repo 側が新。repo→live 再配備が正方向。live 固有の @RTK.md／lean-ctx マーカーは lean-ctx 還流時に再検討 |
| `dotfiles/ccstatusline-settings.json`（変更） | **保留** | core-03.2 で判断（蒸留進捗表示が蒸留パイプライン改修と密結合） |
| `skills/magi-hard/SKILL.md`（変更） | **還流しない** | 配備漏れ。repo→live 更新で解消 |
| `skills/pr-review-respond/SKILL.md`（変更） | **還流しない** | 配備漏れ。repo→live 更新で解消 |
| `skills/code-review/`（新規） | **還流する** | — |
| `skills/investigate/`（新規） | **還流する** | — |
| `skills/skill-creator/`（新規） | **還流する** | — |
| `skills/ollama-run.sh`（新規） | **還流する** | 置き場所は還流 PR 時に判断 |
| `commands/Claude.md`（新規） | **還流する** | — |
| `commands/dev.md`（新規） | **還流する** | — |
| `scripts/magi-split-diff.sh`（新規） | **還流する** | — |
| `skills/balthasar/references/output-format.md`（新規） | **還流する** | — |
| `skills/casper/references/output-format.md`（新規） | **還流する** | — |
| `skills/melchior/references/output-format.md`（新規） | **還流する** | — |
| `skills/metatron/references/output-format.md`（新規） | **還流する** | — |
| `skills/sandalphon/references/output-format.md`（新規） | **還流する** | — |
| `skills/lean-ctx/`（新規） | **還流する** | lean-ctx 一式をセットで1PR |
| `hooks/lean-ctx-redirect.sh`（新規） | **還流する** | lean-ctx セット |
| `hooks/lean-ctx-rewrite.sh`（新規） | **還流する** | lean-ctx セット |
| `rules/lean-ctx.md`（新規） | **還流する** | lean-ctx セット |
| `hooks/error-detector.sh`（新規） | **還流する** | 監査項目05関連の注記付き |
| `hooks/lessons-learned-stop.sh`（新規） | **還流する** | core-03.2 SPEC-03.2-05 で改修予定の旧実装である旨注記 |
| `hooks/test-sessionstart-compact.sh`（新規） | **還流しない** | ローカル実験物。live 側削除候補 |
| `skills/codegen/codegen/`（新規） | **還流しない** | 入れ子の事故コピー。live 側削除候補 |
| `skills/codegen/references/references/`（新規） | **還流しない** | 入れ子の事故コピー。live 側削除候補 |

> **注記**: `requirements` の MM ファイルに挙がっていた `skills/pr-review/SKILL.md` は、2026-07-11 実測で両側同一（差分なし）のため取捨判断不要（受け入れ条件の対象としては充足済み扱い）

---

## 注記

- 「還流する」は判断の記録であり、実際の還流 PR は今後の運用作業として実施する
- live 側の削除候補（事故コピー・実験 hook）の実削除は今回対象外。実施は還流運用の中で
- `ollama-run.sh` の置き場所（`scripts/` vs `skills/` vs 別途）は還流 PR 作成時に確定する

---

## 判断変更（2026-07-12）

PR-R1 着手時に出自確認を行った結果、以下4件の判断を「還流する→還流しない」に変更する。

| 対象 | 変更後判断 | 理由 |
|---|---|---|
| `commands/Claude.md` | **還流しない** | agmsg 導入物（外部プロジェクト）。本リポジトリの管理対象外 |
| `commands/dev.md` | **還流しない** | agmsg 導入物（外部プロジェクト）。本リポジトリの管理対象外 |
| `skills/skill-creator/SKILL.md` | **還流しない** | Anthropic 公式プラグイン導入物。本リポジトリで管理すべき自作物ではない |
| `skills/code-review/SKILL.md` | **還流しない** | MAGI スキル群に置換済みの不要スタブ。還流より live 側削除が適切 |

### live 側削除候補への追加

以下を live 側削除候補に追加する（還流・実施記録 PR 内で実施）:

- `~/.claude/skills/code-review/` — MAGI 置換済みスタブ（agmsg・skill-creator は live では現役のため削除しない）

### 教訓

今後の棚卸しでは、還流判断を行う前に **出自（自作 / 導入物 / 公式プラグイン）を確認**する。
導入物・公式プラグインの導入物は本リポジトリで管理する必要がないため、還流対象から除外する。

### PR-R2 追加判断（2026-07-12）

| 対象 | 変更後判断 | 理由 |
|---|---|---|
| `skills/ollama-run.sh` | **還流しない（スキップ）** | `scripts/ollama-run.sh` として repo 既存（同一内容の重複コピー）。hooks は `../scripts/ollama-run.sh` を参照しており `scripts/` が正規の場所 |

### PR-R3 全件スキップ（2026-07-12）

当初「lean-ctx セット」として還流予定だった以下4件を全件スキップに変更する。

| 対象 | 変更後判断 | 理由 |
|---|---|---|
| `skills/lean-ctx/SKILL.md` | **還流しない** | `lean-ctx onboard`（`npm install -g lean-ctx-bin` 後に実行）が生成する外部ツール生成物 |
| `hooks/lean-ctx-redirect.sh` | **還流しない** | 同上 |
| `hooks/lean-ctx-rewrite.sh` | **還流しない** | 同上 |
| `rules/lean-ctx.md` | **還流しない** | 同上 |

新規環境では `lean-ctx onboard` を実行すれば全て再現される。本リポジトリで管理する必要なし。

> 注意: `lean-ctx onboard` は `npm install -g lean-ctx-bin` が済んでいる前提。ワンライナー setup がこれを含まない限り新環境では再現できない。lean-ctx CLI のインストール（`npm install -g lean-ctx-bin`）+ `lean-ctx onboard` 実行を setup / 手動チェックリストに含めるかは **core-03.3 で検討する**。

---

## 実施記録（2026-07-12）

### 還流 PR

| PR | 内容 | 状態 |
|---|---|---|
| #285 | PR-R1: `skills/investigate/SKILL.md`（$HOME化済み）+ PR-R2: MAGI output-format.md ×5 + `scripts/magi-split-diff.sh` + PR-R4: `hooks/error-detector.sh` + `hooks/lessons-learned-stop.sh`（レガシー注記付き）+ core-02 README test-plan 修正 + 本記録 | **マージ済み（2026-07-12）** |

### live 側クリーンアップ

| 対象 | 状態 |
|---|---|
| `~/.claude/skills/codegen/codegen/`（事故コピー） | 削除済み（本 PR 前に実施） |
| `~/.claude/skills/codegen/references/references/`（事故コピー） | 削除済み（本 PR 前に実施） |
| `~/.claude/hooks/test-sessionstart-compact.sh`（実験物） | 削除済み（本 PR 前に実施） |
| `~/.claude/skills/code-review/`（MAGI 置換済みスタブ） | 削除済み（本 PR 前に実施） |

### 配備漏れ解消

| 対象 | 状態 |
|---|---|
| `skills/magi-hard/SKILL.md` → live | 上書きコピー済み |
| `skills/pr-review-respond/SKILL.md` → live | 上書きコピー済み |
| `CLAUDE.md` 新セクション → live 手動マージ | 実施済み |

### 最終 sync-check 結果（PR #285 マージ後、2026-07-12 実施）

```
=== 要還流（新規）: 実働環境にのみ存在 ===
  commands/Claude.md
  commands/dev.md
  hooks/lean-ctx-redirect.sh
  hooks/lean-ctx-rewrite.sh
  rules/lean-ctx.md
  skills/lean-ctx/
  skills/ollama-run.sh
  skills/skill-creator/

=== 要還流（変更）: 両側に存在するが差分あり ===
  CLAUDE.md
  dotfiles/ccstatusline-settings.json
```

**判定: 全件が還流しない・保留の確定済み項目。追加作業なし。**

| 残差項目 | 区分 | 根拠 |
|---|---|---|
| `commands/Claude.md`, `commands/dev.md` | 還流しない | agmsg 導入物 |
| `hooks/lean-ctx-redirect.sh`, `hooks/lean-ctx-rewrite.sh`, `rules/lean-ctx.md`, `skills/lean-ctx/` | 還流しない | `lean-ctx onboard` 生成物 |
| `skills/ollama-run.sh` | 還流しない（スキップ） | `scripts/ollama-run.sh` として repo 既存 |
| `skills/skill-creator/` | 還流しない | Anthropic 公式プラグイン導入物 |
| `CLAUDE.md` | 差分残存（期待通り） | live 固有行（`@RTK.md`・lean-ctx ブロック）を保持しているため |
| `dotfiles/ccstatusline-settings.json` | 保留 | core-03.2 で判断 |

> 注: 本記録は実施時点のスナップショット。以後の live 側変更（MAGI モデル割当調整・ollama-check.sh 等、core-03.1 関連の先行作業）は本棚卸しの対象外とし、core-03.1 実装および次回の /sync-check 運用で扱う。
