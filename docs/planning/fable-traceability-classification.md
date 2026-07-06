# Fable監査結果 トレーサビリティ分類

## 1. 概要

この分類の目的は、Fable監査結果 `docs/audit-2026-07-05` の 01〜17 を、元の A/B/C 分類ではなく、Claude-StartUp の目的に対する「核問題」単位へ再整理することです。後続の要求定義、仕様化、実装計画で、どの目的に対して何が不足しているかを追跡できる形にします。

入力として使った監査結果は以下です。

- `docs/audit-2026-07-05/README.md`
- `docs/audit-2026-07-05/01-magi-agents-missing.md` 〜 `17-cross-project-recall.md`

現状判定は、監査READMEにもある通り、ドキュメントではなく実装を優先しました。今回の確認では、主に以下の実体を読み取り根拠にしています。

- `setup.sh`, `setup/401-ollama.sh`, `setup/410-hooks-distill.sh`, `setup/411-hooks-auto.sh`, `setup/412-hooks-queue.sh`, `setup/500-pcloud.sh`, `setup/700-claude-md-lifecycle.sh`, `setup/800-ollama-models.sh`, `setup/850-codex.sh`
- `settings.json`
- `hooks/*.sh`, `hooks/lib/ollama.sh`
- `skills/*/SKILL.md`, `skills/*/references/*.md`
- `agents/`, `scripts/`, `templates/`
- 開発リポジトリ `/home/ylocal/srcs/Claude-StartUp` の git 状態
- 本番 `~/.claude` の git 状態

`README.md`、`DESIGN.md`、`SKILLS.md` は監査03の通り現状と乖離しているため、目的の言葉を補助的に拾う用途に限定し、現状の正としては扱っていません。

関連するリポジトリ目的は、監査READMEの目的記述と実装上の構成から、主に以下として扱います。

- 新規環境へのワンライナー展開
- Token削減
- 開発フローSKILL
- 会話ログ蒸留による長期記憶
- 1スキル1ローカルLLM
- Codex実装・Claudeオーケストラ
- 個人用 `~/.claude/` 共通設定の再現可能な展開

本ドキュメントは分類・整理のみを目的としており、コード変更、実装変更、既存設定の変更は行っていません。

## 2. 核問題一覧

| 核問題 | 関連Fable項目 | 関連目的 | 分類 | confidence |
|---|---|---|---|---|
| 核問題1: ワンライナー展開後に実行可能状態へ到達する保証が弱い | 02, 05, 08, 09, 10, 12 | 新規環境へのワンライナー展開、Codex実装、1スキル1ローカルLLM、共通設定の再現可能な展開 | 必須 | high |
| 核問題2: MAGI / Codex / ローカルLLM連携の実体・参照・モデル割当がズレている | 01, 02, 03, 06, 08 | 開発フローSKILL、1スキル1ローカルLLM、Codex実装・Claudeオーケストラ | 必須 | high |
| 核問題3: hooks / knowledge-distill / 知識ストアの基盤が二重化・欠落・密結合している | 04, 05, 13 | 会話ログ蒸留による長期記憶、Token削減、共通設定の再現可能な展開 | 必須 | high |
| 核問題4: 第二の脳・プロジェクト横断想起が構想から運用仕様に落ち切っていない | 13, 16, 17 | 会話ログ蒸留による長期記憶、過去経験の横断活用、Obsidian連携 | 将来拡張 | medium |
| 核問題5: 本番 `~/.claude` とリポジトリの正が分裂している | 07, 15 | 共通設定の再現可能な展開、新規環境へのワンライナー展開、開発フローSKILL | 必須 | high |
| 核問題6: ドキュメント・CI・verify による継続保証が不足している | 03, 07, 10, 11, 12 | 目的達成状況の確認、漏れ検出、継続運用、開発フローSKILL | 必須 | high |
| 核問題7: 対応環境のスコープと優先度が未確定である | 09, 12, 14 | 新規環境へのワンライナー展開、Windows/WSL運用、将来拡張 | 要確認 | medium |

注: 関連Fable項目は核問題への関連であり、項目によっては複数の核問題にまたがります。例えば 02 は「ワンライナー展開」と「MAGIモデル割当」の両方、13 は「知識ストア基盤」と「第二の脳構想」の両方に関係します。

## 3. 核問題ごとの詳細

### 核問題1: ワンライナー展開後に実行可能状態へ到達する保証が弱い

#### 関連Fable項目

- 02: `setup/800-ollama-models.sh` とスキルのモデル割当不整合
- 05: `error-detector.sh` が配備されず自動エラー検知が無音で無効
- 08: Codex CLI の自動インストール不足
- 09: setup 内での Ollama サーバー起動・常駐化不足
- 10: セットアップ統合検証、doctor / verify の不足
- 12: セットアップ後の手動ステップ・チェックリスト不足

#### 関連するリポジトリ目的

- 新規環境へのワンライナー展開
- 1スキル1ローカルLLM
- Codex実装・Claudeオーケストラ
- 個人用 `~/.claude/` 共通設定の再現可能な展開

#### 実装確認メモ

- `setup/850-codex.sh` は `command -v codex` の確認と失敗表示のみで、Codex CLI の自動インストール処理はない。
- `setup/401-ollama.sh` はOllamaのインストールまでで、サーバー起動・常駐化は行っていない。
- `setup/800-ollama-models.sh` は `ollama list` が失敗すると `return 0` でモデル取得を正常スキップする。
- `setup/800-ollama-models.sh` のpull対象には、実スキル側で要求される `gemma4:e4b-it-qat` と `deepseek-r1:8b` が含まれず、旧割当の `llama3.1:8b`、`lfm2.5:8b`、`gemma4:12b` が含まれる。
- `settings.json` は `~/.claude/hooks/error-detector.sh` を参照するが、リポジトリの `hooks/error-detector.sh` は存在せず、実体は `skills/self-improvement/scripts/error-detector.sh` にある。`setup/*.sh` に `error-detector` の配備処理も見つからない。
- `setup.sh` には `--verify` や `900-verify` の分岐・モジュールが見つからない。

#### 問題

監査結果では、ワンライナーを実行しても、Codex CLI、Ollamaサーバー、必要モデル、error-detector、手動認証、セットアップ後検証が一貫した「動作可能状態」として保証されていない。setup が成功扱いになっても、MAGI がフォールバック頼みになる、Codex 実装が使えない、自動エラー検知が無音で無効、手動ステップが辿れない、といった状態が残りうる。

これは「導入できたか」ではなく「目的を満たす状態まで到達したか」を確認する境界がない問題である。

#### 要求化の観点

- ワンライナー完了後に最低限どの機能が利用可能であるべきかを定義する。
- 自動化できる導入と、人間が行う認証・OAuth・環境選択を分ける。
- 未達時に setup を fail とするもの、warn とするもの、info とするものを決める。
- Codex、Ollama、モデル、hooks、manual step の完了状態をユーザーが一発で確認できることを要求に含める。

#### 仕様化の観点

- `setup.sh --verify` または `setup/900-verify.sh` のチェック項目を仕様化する。
- Codex CLI は自動インストール対象、Codexログインは手動ステップとして扱う。
- Ollama は未起動時の起動・常駐化、または明示的な失敗・再実行案内を仕様に含める。
- モデルpullはスキルが要求するモデル一覧と一致することを仕様化する。
- README に「ワンライナー実行後の手動ステップ」と「verify」の導線を置く。

#### テスト観点

- 素の新規環境でワンライナー実行後、Codex CLI、Ollama、必要モデル、hooks、knowledge-rag が verify で確認できる。
- Ollama未起動、Codex未認証、モデル不足、error-detector欠落を意図的に作り、verify が検出する。
- 手動ステップ未完了は setup 全体の失敗ではなく、warn / info として明示される。
- `setup/800-ollama-models.sh` がスキル要求モデルをpull対象に含め、不要モデルをpullしない。

#### 分類

必須

#### 人間確認が必要な点

- Codex CLI の認証未完了を setup の最終結果で warn にするか、明示的な手動未完了として別枠表示にするか。
- 大容量Ollamaモデルのpullをデフォルト必須にするか、`SKIP_OLLAMA_MODELS` のような選択肢を公式に用意するか。
- verify の fail / warn の境界。

#### confidence

high

### 核問題2: MAGI / Codex / ローカルLLM連携の実体・参照・モデル割当がズレている

#### 関連Fable項目

- 01: MAGI エージェント定義の参照不整合
- 02: `setup/800-ollama-models.sh` とスキルのモデル割当不整合
- 03: `SKILLS.md` / `DESIGN.md` / `README.md` のドキュメント陳腐化
- 06: スキル内スクリプト参照のパス解決不統一
- 08: Codex CLI の自動インストール不足

#### 関連するリポジトリ目的

- 開発フローSKILL
- 1スキル1ローカルLLM
- Codex実装・Claudeオーケストラ
- MAGIレビューによる品質保証

#### 実装確認メモ

- `agents/` 配下に存在するMAGI系ファイルは `leliel.md` のみで、`melchior`、`balthasar`、`casper`、`metatron`、`sandalphon` の agents 実体はない。
- 一方で各 `skills/{melchior,balthasar,casper,metatron,sandalphon,leliel}/SKILL.md` には `agents/<persona>.md` 参照が残っている。
- 実スキル側のモデル指定は、MELCHIOR `qwen2.5-coder:7b`、BALTHASAR `gemma4:e4b-it-qat`、CASPER はHaiku標準、METATRON `devstral:latest`、SANDALPHON `phi4:latest`、LELIEL `deepseek-r1:8b` である。
- `setup/800-ollama-models.sh` のモデル一覧は上記と一致していない。
- `skills/magi-fast/SKILL.md` と `skills/magi-hard/SKILL.md` に `bash scripts/magi-diff-filter.sh`、`bash scripts/magi-impact-context.sh` の相対参照が残っている。
- `skills/codegen/SKILL.md` はCodex委譲に更新済みだが、Codex CLI の導入は `setup/850-codex.sh` では確認のみである。

#### 問題

MAGI、ローカルLLM、Codex の実体が、参照パス、モデル割当、ドキュメント、setup で同期していない。監査結果では、#203 の agents 削除方針が参照側に残り、LELIELだけ別方式で復活し、モデル割当もスキルと setup で不一致になっている。また、他プロジェクトから実行されるグローバルスキルで相対パス `bash scripts/...` が使われ、レビューが「差分なし」と誤判定する経路がある。

この核問題は、単なるドキュメントの古さではなく、開発フローのレビューゲートが実際に期待通り動くかどうかに直結する。

#### 要求化の観点

- MAGIペルソナ定義の正を `agents/` に置くのか、`skills/*/references/` に一本化するのかを要求として明確化する。
- 各スキルが要求するモデル、setup がpullするモデル、SKILLS.md のモデル表が一致することを要求にする。
- グローバルスキルは任意のプロジェクトcwdから動作することを要求にする。
- Codexが実装・監査・設計レビュー層で使える状態を要求に含める。

#### 仕様化の観点

- `agents/` 参照撤去または復元のどちらかを仕様として固定する。
- モデル割当の単一情報源、または突合CIの仕様を決める。
- 補助スクリプトは `$HOME/.claude/scripts` または `CLAUDE_STARTUP_SCRIPTS` のような明示的解決規約に統一する。
- codex-companion は固定バージョンパスではなく、解決スクリプトまたは最新検出に寄せる。
- ドキュメントは「現状の正」ではなく、実装変更時に同一PRで更新される対象として扱う。

#### テスト観点

- リポジトリ外の任意gitプロジェクトで `/magi-fast` / `/magi-hard` が差分検出、フィルタ、モデル呼び出しまで完走する。
- `grep` またはCIで `bash scripts/`、`codex/1.0.5`、存在しない `agents/` 参照を検出する。
- スキル側モデルと setup 側モデルの突合チェックをCIまたは verify で実施する。
- Codex CLI 未導入時、setupで導入されるか、明示的に未導入として検出される。

#### 分類

必須

#### 人間確認が必要な点

- #203 の方針を完遂し、MAGIペルソナ実体を references に一本化するか、agents を復元するか。
- METATRON の `devstral:latest` を8GB VRAM環境で継続するか、別モデルを検討するか。
- Codex CLI / plugin の動作確認済みバージョンをどこまで固定・記録するか。

#### confidence

high

### 核問題3: hooks / knowledge-distill / 知識ストアの基盤が二重化・欠落・密結合している

#### 関連Fable項目

- 04: knowledge-distill フック登録の二重化と設計競合
- 05: `error-detector.sh` が配備されず自動エラー検知が無音で無効
- 13: 知識ストアの疎結合化

#### 関連するリポジトリ目的

- 会話ログ蒸留による長期記憶
- Token削減
- 個人用 `~/.claude/` 共通設定の再現可能な展開
- Obsidian / knowledge-rag 連携

#### 実装確認メモ

- `settings.json` は `SessionStart` に `knowledge-distill.sh`、`SessionEnd` に `session-end-queue.sh` を登録しており、キュー方式の形になっている。
- `setup/410-hooks-distill.sh` は `SessionEnd` に `knowledge-distill.sh` を追加登録する処理を持ち、`settings.json` のキュー方式と競合する。
- `setup/410-hooks-distill.sh` の `knowledge-distill.sh` ログ出力先は `~/.claude/hooks/knowledge-distill.log` で、リポジトリ `settings.json` の `~/.claude/hooks/logs/knowledge-distill.log` と一致しない。
- `setup/411-hooks-auto.sh`、`setup/412-hooks-queue.sh`、`setup/700-claude-md-lifecycle.sh` も `settings.json` を動的に書き換える実装を持つ。
- `hooks/knowledge-distill.sh`、`hooks/lessons-learned-distill.sh`、`hooks/knowledge-prune.sh`、`hooks/check-queue.sh`、`hooks/knowledge-auto-promote.sh`、`skills/remember/SKILL.md`、`scripts/generate-obsidian-index.sh` は `~/pcloud/obsidian` や `mountpoint -q "$HOME/pcloud"` に依存している。
- `hooks/knowledge-distill.sh` は `knowledge-distill-register.sh` に登録を委譲しており、store + watch への一本化は未実装である。

#### 問題

長期記憶の基盤である hooks と knowledge-distill に、二重登録、配備漏れ、ストレージ密結合が存在する。監査結果では、SessionEndでの直接蒸留とSessionStartでのキュードレインが競合し、本番でも二重登録が実測されている。また、PostToolUse が参照する `error-detector.sh` は新規環境で配備されない。さらに、pCloud / rclone mount 前提が記録層に入り込み、複数WSLコンテナ運用やObsidian連携の安定性を下げている。

この問題は、長期記憶の品質、重複登録、トークン消費、再現可能性のすべてに影響する。

#### 要求化の観点

- 蒸留は1 transcript につき1回だけ処理されることを要求にする。
- hooks の登録元、ログ出力先、配備対象を明確にする。
- 記録層はローカルstoreで完結し、Obsidian / pCloud / `/mnt/c` を直接知らないことを要求にする。
- 配送層と取込層は一方向同期として扱い、双方向同期を要求にしない。
- error-detector の配備と実行コスト上限を要求に含める。

#### 仕様化の観点

- `settings.json` 直書き方式と setup による動的注入のどちらを正とするかを仕様化する。
- SessionEnd は queue push、SessionStart は drain という役割分担を明文化する。
- ログパスは `hooks/logs/` 配下に統一する。
- store / vault / index-en のディレクトリ責務と writer を仕様化する。
- pCloud reason キューを廃止するか、移行期間だけ扱うかを決める。
- knowledge-rag への登録を API 登録で続けるか、documents_dir + watch に一本化するかは、監査結果上も検証後判断とされているため要確認にする。

#### テスト観点

- 1セッション終了、次セッション開始で同じ transcript が一度だけ蒸留・登録される。
- SessionEnd に `knowledge-distill.sh` の直接実行が残っていないことを verify / CI で確認する。
- `settings.json` が参照する hooks 実体がすべて存在し、実行可能である。
- rclone mount なしでも蒸留、RAG登録、自動昇格が動く。
- storeからObsidianへの配送、Obsidianからstore/vaultへの取込が一方向で冪等に動く。

#### 分類

必須

#### 人間確認が必要な点

- `settings.json` の正をリポジトリ直書きにする方針を採用するか。
- knowledge-rag の watch 信頼性を確認し、API登録廃止まで進めるか。
- 既存pCloud / Obsidianデータの初期シードと移行手順をどのタイミングで実施するか。

#### confidence

high

### 核問題4: 第二の脳・プロジェクト横断想起が構想から運用仕様に落ち切っていない

#### 関連Fable項目

- 13: 知識ストアの疎結合化
- 16: Obsidian 第2の脳ワークフロー
- 17: プロジェクト横断の長期記憶活用

#### 関連するリポジトリ目的

- 会話ログ蒸留による長期記憶
- Obsidianを介した知識還流
- プロジェクトAの経験をプロジェクトBで活用する横断想起

#### 実装確認メモ

- `skills/inbox/` は存在しない。
- `hooks/auto-recall.sh` は存在しない。
- 現行の蒸留系 hooks は `~/pcloud/obsidian` への保存と `knowledge-distill-register.sh` による登録に依存しており、13で示された `store/`、`vault/`、`index-en/` の分離構造は未実装である。
- `hooks/knowledge-distill-extract.sh`、`hooks/knowledge-distill.sh`、`hooks/lessons-learned-extract.sh` は transcript 抽出を `.[0:4000]` で切っており、17の「先頭 + 末尾」または経験カード形式は未実装である。

#### 問題

監査結果では、13で知識ストアの基盤方針は決定済みとされているが、16の inbox ワークフローと17の経験カード / auto-recall は、まだ運用仕様・段階導入・ノイズ制御の整理が必要な状態である。長期記憶を「保存できる」だけでなく、「人間ノートとAI調査が循環する」「過去の判断が別プロジェクトで想起される」状態まで持っていくには、要求と仕様を分けて固める必要がある。

#### 要求化の観点

- Obsidian inbox からClaudeが調査し、結果をknowledgeへ還流する一連のユーザーストーリーを要求化する。
- 人間領域のノートはClaudeが直接書き換えないことを要求に含める。
- 経験カードに、状況、やったこと、結果、判断理由、技術タグ、outcome を含めることを要求にする。
- auto-recall は必要なときだけ短く想起し、トークン削減方針を破らないことを要求にする。

#### 仕様化の観点

- `/inbox` の検出、確認、調査、還流、台帳更新の手順を仕様化する。
- `store/vault/inbox`、`store/knowledge`、`_inbox-ledger.md` の責務を明確にする。
- 経験カードの日英出力、`index-en/`、検索クエリ言語、frontmatter の形式を仕様化する。
- auto-recall の発火条件、検索件数、スコア閾値、注入上限、タイムアウト、既出抑止を仕様化する。
- kizami と knowledge-rag の役割分担を明文化する。

#### テスト観点

- Obsidianの inbox にURLを置き、`/inbox` で調査結果がknowledge化され、元メモとリンクされる。
- 同じ結果が `search_knowledge` でヒットする。
- 同一メモが二重処理されず、追記時だけ再処理候補になる。
- プロジェクトAの経験カードが、プロジェクトBの類似タスクで `[RECALL]` または検索結果として出る。
- 非技術的な雑談で auto-recall が発火しない。
- auto-recall が2秒以内に終わり、超過時はサイレントスキップされる。

#### 分類

将来拡張

#### 人間確認が必要な点

- v1を `/inbox` 手動実行に留めるか、SessionStart通知まで含めるか。
- auto-recall をいつ導入するか。まず蒸留カード品質を一定期間評価するか。
- 英語シャドウノート方式をA/B評価後に確定するか、監査結果の決定事項としてそのまま進めるか。

#### confidence

medium

### 核問題5: 本番 `~/.claude` とリポジトリの正が分裂している

#### 関連Fable項目

- 07: リポジトリ衛生
- 15: 本番 `~/.claude` クローンの git 状態正常化とデプロイフロー定義

#### 関連するリポジトリ目的

- 個人用 `~/.claude/` 共通設定の再現可能な展開
- 新規環境へのワンライナー展開
- 開発フローSKILL

#### 実装確認メモ

- 開発リポジトリ `/home/ylocal/srcs/Claude-StartUp` は `main` の `99166b8 feat(flow-common): Phase 1.5 設計レビューを Codex 共通化 (#265)`。
- 開発リポジトリの `git status --short` では、`.codex/`、`2026-07-03-session-summary.md`、`CLAUDE.local.md`、`docs/audit-2026-07-05/`、`scripts/index-investigations.sh` が未追跡だった。
- 本番 `~/.claude` はHEAD `e1dc01f` で、`git status --short` には `MM`、`M`、`D`、`??` が大量に混在していた。agents 5体の削除、`settings.json` の変更、hooks/skills/scripts の未追跡が確認できた。
- 本番 `~/.claude` のリモート遅れ量は今回fetchしていないため、約100PR遅れという情報はFable項目15の監査結果を根拠として扱う。

#### 問題

監査結果では、本番 `~/.claude` が main から大きく遅れつつ、未コミット直編集で最新相当の内容を持つ状態とされている。これにより「リポジトリが正であり、ワンライナーで再現できる」という前提が崩れている。加えて、未追跡ファイル、個人設定、worktree残骸が残っており、どれが意図したローカル差分で、どれがリポジトリに反映すべき変更かを判別しにくい。

#### 要求化の観点

- 本番反映の正規手順を要求として定義する。
- 本番 `~/.claude` の追跡ファイルは直接編集しない、または直接編集時の退避・反映ルールを定義する。
- マシン固有設定、個人メモ、実験スクリプト、正式実装を区別する。
- worktree完了時の清掃を開発フローの要求に含める。

#### 仕様化の観点

- 本番同期は `git -C ~/.claude pull` を基本とするのか、setup再実行を含めるのかを仕様化する。
- `/finished-pr` に本番pull提案やworktree清掃確認を含めるか決める。
- `.gitignore` の対象を、`.codex/`、`CLAUDE.local.md`、個人設定に合わせて整理する。
- 本番だけの実験をどのファイル名・場所に限定するかをドキュメント化する。

#### テスト観点

- 本番 `~/.claude` の `git status --short` が、説明可能なローカル状態ファイルだけになる。
- 本番 HEAD が origin/main と一致する。
- マージ後に本番へ反映する手順がREADME、DESIGN、または `/finished-pr` から辿れる。
- worktree完了後に残骸が残らない。

#### 分類

必須

#### 人間確認が必要な点

- 本番 `~/.claude` にある未コミット差分のうち、main反映済み、未マージ実験、ローカル状態ファイルをどう分けるか。
- 追跡ファイルの本番直編集を完全禁止にするか、緊急時のみ許容するか。
- セッションまとめや調査スクリプトを削除するか、docs配下へ移して追跡するか。

#### confidence

high

### 核問題6: ドキュメント・CI・verify による継続保証が不足している

#### 関連Fable項目

- 03: ドキュメント陳腐化
- 07: リポジトリ衛生
- 10: セットアップ統合検証、doctor / verify の追加
- 11: CI パイプラインの追加
- 12: セットアップ後の手動ステップ・チェックリスト整備

#### 関連するリポジトリ目的

- 目的達成状況の確認
- 目的に対する要求・仕様・実装・テストの漏れ把握
- 開発フローSKILL
- 継続運用と再発防止

#### 実装確認メモ

- `.github/` は存在せず、このリポジトリ自身のGitHub Actions CIは未実装である。
- `templates/security/github-workflows/security-scan.yml` は存在するが、テンプレート配布用であり、このリポジトリの `.github/workflows/` ではない。
- `scripts/test-magi-diff-filter.sh`、`scripts/test-magi-format.sh`、`scripts/test-function-calling.sh` は存在するが、自動実行するCIはない。
- `setup.sh` には `--verify` 分岐がなく、`setup/900-verify.sh` も存在しない。
- 実装確認時点のgit状態では、Fable07で挙げられた未追跡に加えて `docs/audit-2026-07-05/` も未追跡だった。監査入力として扱うか、追跡対象にするかは要確認。

#### 問題

監査結果では、実装とドキュメントのズレ、CI不在、verify不在、手動ステップ導線不足、未追跡ファイル滞留が共通して指摘されている。これは個別バグというより、目的に対する整合性を継続的に保証する仕組みが不足している問題である。

MAGIモデル表、Codex移行、hooks参照、manual step、setup結果などは変化しやすいため、ドキュメント更新だけでは再発防止にならない。機械的に検出できる不整合はCIまたはverifyに寄せる必要がある。

#### 要求化の観点

- リポジトリ目的に関わる整合性を、人間レビューだけに依存しないことを要求にする。
- setup後の実動作検証と、PR時の静的整合性検証を分ける。
- READMEだけでワンライナー、手動ステップ、verifyまで辿れることを要求にする。
- ドキュメントは実装の説明であり、実装と不一致の場合は検出・更新されることを要求にする。

#### 仕様化の観点

- CIでは `bash -n`、shellcheck、既存テスト、モデル突合、hooks実体参照、禁止パスgrepを実行する。
- verifyでは実環境依存の到達性、インストール状態、モデル存在、hooks配備、キュー滞留を確認する。
- README、SKILLS.md、DESIGN.md の更新対象と、変更時の同時更新ルールを定義する。
- 手動ステップと環境変数一覧を一箇所に集約する。

#### テスト観点

- 02 / 05 / 06 型の不整合を含むPRがCIでfailする。
- 01 / 02 / 04 / 05 型の環境不整合をverifyが検出する。
- 既存の `scripts/test-*.sh` がCIで実行される。
- READMEからワンライナー、manual step、verifyに迷わず到達できる。

#### 分類

必須

#### 人間確認が必要な点

- shellcheckの厳格度を初回から warning にするか、error から段階導入するか。
- smoke test でどこまでネットワーク・Ollama・pCloud依存を扱うか。
- どの不整合をCIでfailにし、どの不整合をverifyのwarnにするか。

#### confidence

high

### 核問題7: 対応環境のスコープと優先度が未確定である

#### 関連Fable項目

- 09: setup 内での Ollama サーバー起動・常駐化
- 12: セットアップ後の手動ステップ・チェックリスト整備
- 14: Windows ネイティブ環境対応

#### 関連するリポジトリ目的

- 新規環境へのワンライナー展開
- Windows / WSL / Linux の運用範囲
- 個人用 `~/.claude/` 共通設定の再現可能な展開

#### 実装確認メモ

- `setup.sh`、`setup/`、`hooks/` はbash前提で構成されており、`setup.ps1` は存在しない。
- `hooks/lib/ollama.sh` には、WSL2 NATモードでWindowsホストIPを検出し、`OLLAMA_BASE_URL` または Windowsホスト側Ollamaへ向ける実装がある。
- `.codex/hooks.json` には `commandWindows` があり、Git Bash経由でhookを呼ぶ記述がある。ただし `.codex/` は未追跡で、リポジトリの正式サポート範囲かは要確認である。
- `setup/500-pcloud.sh` はWSL2 systemd と rclone mount を前提にしており、Windowsネイティブのsetup仕様は確認できない。

#### 問題

監査結果では、現状の setup / hooks は WSL/Linux 前提で成立している一方、Windowsホスト側Ollama利用や `.codex/hooks.json` の `commandWindows` など、Windowsとのハイブリッド運用も存在している。Windowsネイティブを「新規環境へのワンライナー展開」の対象に含めるかどうかが明記されていないため、どこまで対応すべきか判断できない。

#### 要求化の観点

- サポート対象環境を明示する。
- Windowsネイティブを非対応、限定対応、正式対応のどれにするか決める。
- WSLからWindowsホスト側Ollamaを使う構成を、正式な想定として扱うかを決める。
- 非対応機能は失敗ではなく warn として表示するのか、setup対象外にするのかを決める。

#### 仕様化の観点

- READMEにサポート環境マトリクスを追加する。
- WSL2推奨、macOS/Linux動作想定、Windowsネイティブ非対応または限定対応、のように明文化する。
- Windows限定対応を採る場合は、Git Bash経由、`setup.ps1`、hooks内Linux依存コマンドのガードを仕様化する。
- Ollama起動判定は WSL内プロセスだけでなく、Windowsホスト側Ollama到達性も考慮する。

#### テスト観点

- WSL2環境でワンライナーが完走する。
- Windowsホスト側Ollama構成で、WSL内にOllamaサーバーが二重起動しない。
- Windowsネイティブ非対応とする場合、READMEとverifyがその前提を明確に示す。
- 限定対応する場合、Git Bash経由でsetupが完走し、非対応機能はwarn表示になる。

#### 分類

要確認

#### 人間確認が必要な点

- Windowsネイティブ対応を今回の目的達成範囲に含めるか。
- Windowsホスト側Ollama利用を標準構成として扱うか、例外構成として扱うか。
- pCloud / Obsidian の Windows側Syncを、13の新アーキテクチャの前提として固定するか。

#### confidence

medium

## 4. 次にやるべきこと

### 目的確定が必要な項目

- 01: MAGIペルソナ定義を references に一本化するか、agents を復元するか。
- 03: Codex実装・Claudeオーケストラを README / DESIGN / SKILLS の中核目的として明文化する範囲。
- 13: knowledge-rag 登録を documents_dir + watch に一本化するか、API登録を残すか。
- 14: Windowsネイティブを非対応、限定対応、正式対応のどれにするか。
- 16 / 17: 第二の脳とauto-recallを、直近の要求に含めるか、13完了後の将来拡張にするか。

### 要求定義に進める項目

- 核問題1: ワンライナー完了状態、手動ステップ、verifyの成功条件。
- 核問題3: hooks登録、蒸留1回保証、知識ストア疎結合化。
- 核問題5: 本番 `~/.claude` と開発リポジトリの役割分担、デプロイフロー。
- 核問題6: CI / verify / ドキュメント更新ルールによる継続保証。

### 仕様化に進める項目

- 02: スキル要求モデル、setup pullモデル、SKILLS.mdモデル表の突合仕様。
- 04: SessionEnd queue push / SessionStart drain のhooks仕様。
- 06: グローバルスキルからのスクリプトパス解決規約。
- 08 / 09 / 10 / 12: Codex導入、Ollama起動、verify、手動ステップのsetup仕様。
- 11: CI の lint / test / consistency ジョブ仕様。
- 13: store / vault / index-en / rsync層の仕様。

### 実装計画に進める項目

- 15: 本番 `~/.claude` の棚卸しと同期正常化を最初に行う。以降の修正が本番に届く前提を作るため。
- 01 / 02 / 06: MAGIレビューの実動作に直結するため、モデル・参照・パス解決を同じ系列で計画する。
- 04 / 05 / 13: hooksと知識ストア基盤を同じ系列で計画する。二重登録解消とローカルstore化は影響範囲が重なるため。
- 08 / 09 / 10 / 12: ワンライナー展開の完了条件を計画する。自動導入と手動確認を分ける。
- 03 / 11 / 07: 継続保証として、ドキュメント現状化、CI追加、リポジトリ衛生を計画する。
- 16 / 17: 13の基盤完了後、第二の脳ワークフローと横断想起を段階導入する。
- 14: サポート環境方針が確定してから、必要に応じてWindows限定対応を計画する。
