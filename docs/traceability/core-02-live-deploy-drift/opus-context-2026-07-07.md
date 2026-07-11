# Core-02 再検討コンテキスト（Opus 引き継ぎ用）

作成: 2026-07-07 / traceability-flow Step 3 作業中に前提変更が発覚したため上位モデルへ引き継ぎ

---

## 1. このリポジトリの目的（最重要前提）

`~/srcs/Claude-StartUp` は「個人用 Claude Code 環境の管理・展開リポジトリ」。

**根本目的**: 新規マシン（WSL2/Linux）で同一の Claude Code 環境を自動セットアップ・完遂できること。

**環境スコープ（core-01 で 2026-07-07 確定）**:
- サポート対象 = WSL2（Linux）のみ。Windowsネイティブは対象外
- WindowsホストOllama（`OLLAMA_HOST=<WinIP>:11434`）を標準構成
- 共有データの最終集約場所 = pCloud。各WSLコンテナはまずローカル保存 → 一括転送

---

## 2. Core-02 の元の問題定義（Fable 監査から）

Fable 監査（docs/audit-2026-07-05/）が指摘した問題：

> **Fable 15**: 本番 `~/.claude` クローンの git 状態正常化とデプロイフロー定義  
> **Fable 07**: リポジトリ衛生

**監査の観察事実**:
- 本番 `~/.claude` は HEAD `e1dc01f`（#158）で約76PR遅れ
- `git status --short` に MM・M・D・?? が大量混在
- agents 5体の削除、settings.json の変更、hooks/skills の大量未追跡ファイル

**監査が暗黙的に前提にしていた考え方**: 「`~/.claude/` はリポジトリの正コピーであるべき」

---

## 3. 前提の変更（2026-07-07 ユーザー確認）

**ユーザーの発言**:
> 必要なのは、リポジトリを使って他の新規環境で同じ環境が構築できることであり、
> この環境の~/.claude/が、リポジトリとイコールである必要性はなく、
> また~/.claude/は、リポジトリの開発作業を進めるために最適化されていればよい。

**つまり**:
- `~/.claude/` がリポジトリと diverge していること自体は問題ではない
- 現在の `~/.claude/` は開発最適化された環境であり、意図的に ahead
- 真の目的は「新規マシンで setup.sh を実行したら動作可能状態に到達できること」

---

## 4. Step 3 で確認した実態

### 4.1 ~/.claude の現状（git status 分類済み）

**[問題なし] 未追跡（`??`）の大量ファイル**  
skills/traceability-*/, lean-ctx/, compact-prep/ 等の新スキル群、hooks の新規ファイル群。
これらは本番先行実装（リポジトリにまだ未マージのものも含む）。开発環境として ahead なのは正常。

**[問題なし] ` M`（本番が古い版）の多数ファイル**  
本番が旧版のまま。新規環境では setup.sh が最新を入れるので問題なし。

**[要注意] `MM` CLAUDE.md、skills/pr-review/SKILL.md**  
本番とリポジトリの両方に変更あり。ただし本番の変更が有益かもしれない。

**[問題なし] agents/ の削除・追加**  
- 5体削除 = PR #203（#158より後）の先行手動適用。意図的。
- agents/leliel.md 追加 = PR #234 の先行手動適用。ただし設計不整合あり（後述）。

**[配慮不要] settings.json の大差分**  
setup スクリプト（410/411/412/700/250）と Claude Code 自動追記の複合産物。
deploy.sh の対象外にすることで確定。

### 4.2 agents/leliel.md の設計不整合（core-03.1 に記録済み）

- PR #203 の理由：「agents/xxx.md があると Agent ツール直接呼び出しでスキルのOllama-firstフローがバイパスされる」→ 5体削除
- PR #234 で agents/leliel.md を `model: haiku` で追加 → 設計矛盾
- magi-hard は実際には `/leliel` スキル経由で呼ぶため agents/leliel.md は使われていない
- CASPER 以外は deepseek-r1:8b で統一が方針（2026-07-07 確定）
- → agents/leliel.md 削除は **core-03.1** の作業範囲

---

## 5. Step 3 途中で合意した内容（前提変更前）

| 項目 | 合意内容 | 前提変更後の有効性 |
|---|---|---|
| de-git（~/.claude を git 管理から外す） | 合意済み | **再検討が必要** |
| deploy.sh（rsync ホワイトリスト方式）| 合意済み | **再検討が必要** |
| settings.json は deploy.sh 対象外 | 合意済み | **維持（新規環境でも setup スクリプトが管理）** |
| agents/ は deploy.sh 対象 | 合意済み | **維持（ただし leliel.md 削除後）** |
| /finished-pr に deploy.sh 促しを追加 | 要求として記述済み | **再検討が必要** |

---

## 6. 現在の未解決問題（Opus に問いたいこと）

**Q1**: 前提変更後、Fable 07/15 の観察事実の中に「新規環境再現性」という目的に対して**本当に問題になるもの**は何か？

候補として考えられる残存問題：

A. **開発中の変更が新規環境 setup に反映される経路の明確化**  
   （repo に PR を出してマージすれば次の setup.sh 実行で反映される、という流れを明文化するだけで十分か？）

B. **worktree 残骸問題**  
   （/finished-pr 後の cleanup は別途定義が必要か？）

C. **リポジトリの .gitignore 整合**  
   （CLAUDE.local.md, .codex/ 等が未追跡のまま → .gitignore に追加すべきか）

D. **「この問題はほぼ core-03.3 に吸収される」**  
   （core-03.3 = ワンライナー展開後の実行可能状態保証 = 新規環境再現性 そのもの）

**Q2**: core-02 は独立した核問題として維持すべきか、それとも core-03.3 に統合すべきか？

---

## 7. 関連ドキュメント

- 全体ボード: `docs/traceability/README.md`
- core-02 フォルダ: `docs/traceability/core-02-live-deploy-drift/`
  - `requirements.md` — 前提変更前に書いた内容（要見直し）
  - `traceability-map.md`
- core-03.3: `docs/traceability/core-03.3-setup-readiness/`
- 分類元: `docs/planning/fable-traceability-classification.md`（核問題5 の詳細は L321〜L378）
- Fable 監査: `docs/audit-2026-07-05/`（Fable 07: audit-07.md、Fable 15: audit-15.md）
- 共通ルール: `skills/traceability-common/references/rules.md`
