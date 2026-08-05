# ERRORS.md — 再発防止ログ

### ERR-20260710-001
**Summary:** `/finished-pr` で worktree 削除後、CWD が不在になり後続の git コマンドが全滅した

**Details:** `/finished-pr` スキルで `git worktree remove` を実行しようとしたところ、`getcwd: cannot access parent directories: No such file or directory` が発生し後続の git コマンドが全て失敗した。原因は Bash セッションの CWD が worktree ディレクトリ内（または git pull によってクリーンアップされた worktree パス）を指していたため、ディレクトリ削除後に CWD が不在となり shell が getcwd に失敗したこと。

**Suggested Action:** `git worktree remove` / ブランチ削除 / prune 実行前に必ず `cd /home/ylocal/srcs/Claude-StartUp`（リポジトリルート）を先頭に置く（`cd /home/ylocal/srcs/Claude-StartUp && git worktree remove "$WORKTREE_PATH"`）。finished-pr の Phase 3〜6 の git コマンドは全て `git -C /home/ylocal/srcs/Claude-StartUp <cmd>` 形式か、または `cd <repo_root>` を冒頭に入れてから実行する。

**Source:** /finished-pr スキル実行
**Related Files:** skills/finished-pr/SKILL.md
**Tags:** worktree, git, cwd
**Pattern-Key:** worktree-remove-cwd-getcwd-error
**Recurrence-Count:** 1
**Status:** pending
**Knowledge-Status:** pending

### ERR-20260713-001
**Summary:** RTK フックが複合コマンドを分割実行し、gh/git 前段で定義したシェル変数が消える

**Details:** `S=<path>; gh pr diff 303 > "$S/file"` のように、変数代入と gh/git コマンドを同一 Bash 呼び出しで組み合わせると、gh/git 実行行で `$S` が空文字になり `/file: No such file or directory` で失敗する。git add + grep の複合でも再現した。原因は RTK フックが gh/git コマンドをリライトする際、複合コマンドが分割実行され前段の変数代入・シェル状態が引き継がれないため（Issue #250 の RTK リライト系と同族）。

**Suggested Action:** gh/git を含む Bash 呼び出しでは、シェル変数を使わずリテラル絶対パスを書く。変数が必要な場合は gh/git を含まない呼び出しに分離する。gh/git コマンドとリダイレクト先パスは同一呼び出し内でリテラル展開して書き、状態の受け渡しはファイル（scratchpad の state file）経由で行う。

**Source:** Issue #250（RTK リライト系）
**Related Files:**
**Tags:** rtk, gh, git, shell
**Pattern-Key:** rtk-hook-compound-command-var-loss
**Recurrence-Count:** 1
**Status:** pending
**Knowledge-Status:** pending

### ERR-20260713-002
**Summary:** granite3.3/phi4 が MAGI レビューの completion marker を出力せず review_incomplete になる

**Details:** magi-hard v2 E2E（PR #303）で METATRON(granite3.3:8b) と SANDALPHON(phi4:latest) がレビュー本文は正常出力したが、最終非空行の completion marker を省略。sink 契約により chunk failure → execution_status=failed → review_incomplete となった。原因は marker 指示が `---TASK_DATA_START---` の直前（trusted prefix 末尾）にあり、granite/phi4 は本文終端に指示を反映しない傾向があるため（qwen2.5-coder/gemma4 は遵守）。

**Suggested Action:** fail-open 設計どおり parser が fallback finding 化し LGTM 禁止になることを確認済み（設計は正常動作）。モデル別の marker 遵守率改善（system 側への指示複製・few-shot 例示の追加）を Issue 化して対応する。

**Source:** PR #303（magi-hard v2 E2E）
**Related Files:**
**Tags:** magi, completion-marker, granite, phi4
**Pattern-Key:** magi-completion-marker-model-noncompliance
**Recurrence-Count:** 1
**Status:** pending
**Knowledge-Status:** pending

### ERR-20260713-003
**Summary:** poster build が実 review-plan の anchor 形を拒否した（テスト fixture のスキーマ乖離）

**Details:** magi-hard v2 E2E で poster build が "invalid review anchor" で exit 2 になった。テストは side="RIGHT"・head_sha 埋め込み済みの anchor を持つ合成 review-plan で green だったが、実際の magi-aggregate merge 出力は inline anchor の side/start_line/start_side/head_sha が全て null（poster が投稿時に side=RIGHT と commit_id を補う契約）、PR-scope は全 null の dict だった。原因はテスト fixture を手書き合成し、スキーマの正本（magi-aggregate.py の validate_canonical / build_review_plan）と突き合わせなかったこと。

**Suggested Action:** builder の検証を正本スキーマに合わせて修正済み（inline: path+line のみ非 null 必須、side/head_sha は null 要求）。テスト fixture は magi-aggregate merge の実出力形に修正済み。連携する artifact のテスト fixture は、生成側スクリプトを実際に呼んで作るか、生成側の validator を通してから使う（スキーマ正本とのクロスチェックを SPEC に明記する）。

**Source:** magi-hard v2 E2E
**Related Files:** magi-aggregate.py
**Tags:** magi, poster, test-fixture, schema
**Pattern-Key:** magi-poster-anchor-schema-fixture-drift
**Recurrence-Count:** 1
**Status:** pending
**Knowledge-Status:** pending

### ERR-20260713-004
**Summary:** poster の冪等性が実環境で破綻し、コメントが重複投稿された（gh --slurp 未対応 + 一覧取得失敗の黙認続行）

**Details:** E2E で poster post 再実行時に skipped_existing にならず重複投稿された。コメント一覧取得 `gh api ... --paginate --slurp` が gh 2.46.0 で "unknown flag: --slurp" となり rc≠0 → コード側が continue で黙って続行 → marker 集合が空 → 全件再投稿された。原因は (1) --slurp は新しめの gh のみ対応で、fake gh テストはフラグを検証しないため検出不能だったこと、(2) 冪等性の根拠である一覧取得の失敗を fail-closed にせず続行する設計欠陥があったこと。

**Suggested Action:** 一覧取得は --paginate + --jq '.[]'（JSONL、1行1comment）で gh 旧版でも動く形に変更済み。一覧取得が1エンドポイントでも失敗したら投稿せず exit 1（重複防止は fail-closed）に変更済み。外部 CLI のフラグはローカルの実バージョンで最低1回実行確認する（fake だけで完結させない）。安全性の前提となる読み取りの失敗は「黙って続行」でなく fail-closed に倒す。

**Source:** magi-hard v2 E2E
**Related Files:**
**Tags:** magi, poster, gh-cli, idempotency
**Pattern-Key:** magi-poster-gh-slurp-idempotency-failure
**Recurrence-Count:** 1
**Status:** pending
**Knowledge-Status:** pending

### ERR-20260714-001
**Summary:** `git -C <worktree>` の status がメインリポジトリの結果を返し、worktree の状態を誤判断させる

**Details:** `git -C worktree/<branch> status --short` が worktree ではなくメインリポジトリの status（別の M ファイル群・untracked 一覧）を返した。同一呼び出し内の `git -C <worktree> branch --show-current` は正しく worktree のブランチを返すため、一見「worktree に無関係な変更が混入した」ように見え誤判断を誘発する。原因は RTK フックが git コマンドをリライトする際に `-C <path>` の一部コマンド（status 等）で作業ディレクトリ指定が失われるため（ERR-20260713-001 の変数消失と同族のリライト問題）。

**Suggested Action:** `cd <worktree絶対パス> && git status --short` の形にすると正しい結果が得られることを確認済み。worktree 内の git 操作は `git -C` ではなく `cd <worktree> && git ...` を使う。`git -C` の出力が期待と異なる場合は、まず RTK リライトを疑い cd 形式で再実行して照合する。

**Source:** RTK フック使用時（worktree 内 git 操作）
**Related Files:**
**Tags:** rtk, git, worktree
**Pattern-Key:** rtk-hook-git-c-worktree-status-wrong-cwd
**Recurrence-Count:** 1
**Status:** pending
**Knowledge-Status:** pending

### ERR-20260717-001
**Summary:** MAGI ローカル LLM（MELCHIOR）の completion marker 欠落が確率的に再発し、commit gate が閉じる

**Details:** magi-fast の sink mode で MELCHIOR（qwen2.5-coder:7b）が completion marker を最終行に出力せず、persona status が partial/failed になり commit gate が閉じる。PR #313/#317/PR-C の判定で通算5回発生（成功は3回＝遵守率~50%）。原因は (1) 7B モデルの長出力末尾での指示追従の減衰（本文完走後に marker/Assessment を出さず EOS）、(2) 例文 echo（#319 で修正済み）・反復ループ（repeat_penalty 1.3 で修正済み）・num_predict 切断（4096 で緩和）を除去した後も marker の純粋な出し忘れが残ること。副次事象として、marker の例示が system（output-format.md 終端例）と呼び出し側プロンプトで二重になると BALTHASAR（gemma4）まで marker を落とす。

**Suggested Action:** 呼び出し側プロンプトの marker 例示を「最終行にこの文字列」の1指示に単純化し BALTHASAR は復帰済み。MELCHIOR は確率的なため、恒久対策は orchestrator レベルの限定再試行（marker missing 時に当該チャンクを1回だけ再実行）を #314 で設計する。MAGI プロンプト変更時は同一入力での前後比較実験（persona×言語）を必ず行う。marker 遵守率のような確率的挙動は1回の成功で「直った」と判断しない。

**Source:** PR #313 / #317 / PR-C
**Related Files:** output-format.md
**Tags:** magi, melchior, completion-marker
**Pattern-Key:** magi-marker-missing-probabilistic-recurrence
**Recurrence-Count:** 1
**Status:** pending
**Knowledge-Status:** pending

### ERR-20260723-001
**Summary:** MELCHIOR が特定 diff で3回連続、反復ループに陥り Assessment 節に到達できない

**Details:** Issue #340（MAGI review router）実装差分（`scripts/magi-run-setup.py` + `scripts/tests/test_magi_run_setup.py`、単一chunk・302行）に対する `/magi-fast` 実行で、MELCHIOR（qwen2.5-coder:7b）が新規 run dir を作り直して3回連続で `execution_status=failed` になった。原因は (1) 出力が同一パターンの finding（1回目は「race condition in file deletion」「None value in route」の交互反復、2回目は「Redundant assignment to route」の単独反復）を、行番号だけ変えながら際限なく繰り返し、`OLLAMA_NUM_PREDICT=4096` の上限で打ち切られること（8件までという finding limit 指示をモデルが完全に無視している）、(2) `repeat_penalty=1.3` を適用済みでも防止できていないこと（既知の反復ループ問題の再発）、(3) 対象 diff 自体が「似た構造の route/finding 分岐が何度も繰り返される」コードであり、入力の反復構造がモデル自身の出力反復を誘発している可能性（未検証の仮説）、(4) temperature=0.1 と低いため、同一 diff に対しては再試行しても同じ失敗パターンに収束しやすいこと（3回とも同じ diff で failed）。

**Suggested Action:** 今回は未実施・次回の課題として、finding limit（8件）を prompt 指示だけでなく、runner 側で「同一 severity+title パターンが N回連続したら生成を打ち切る」ような反復検出を実装することを検討する。このセッションでは BALTHASAR/CASPER の結果と目視確認で代替し、MELCHIOR 分は review_incomplete として記録した上で人間判断で進めた。同一 diff で3回連続失敗した場合、4回目以降の自動再試行はしない（時間・コストの無駄になるため）。人間判断で「他 persona の結果で代替」か「diff を分割し直す」かを決める。反復構造を持つコード（多数の似た分岐・繰り返しブロック）を含む diff は MELCHIOR が反復ループに陥りやすい、という経験則を記録しておく。

**Source:** Issue #340（MAGI review router）、/magi-fast 実行
**Related Files:** scripts/magi-run-setup.py, scripts/tests/test_magi_run_setup.py
**Tags:** magi, melchior, repeat-loop
**Pattern-Key:** melchior-repeat-loop-finding-limit-ignored
**Recurrence-Count:** 1
**Status:** pending
**Knowledge-Status:** pending
