# ERRORS.md — 再発防止ログ

### ERR-20260911-001
**Summary:** `gh pr merge --delete-branch` で base ブランチを削除すると、そのブランチを base にしている別PRが自動 closed になり `gh pr reopen`/`gh pr edit --base` 双方で復旧不能

**Details:** PR#417（base=main）を `gh pr merge 417 --merge --delete-branch` でマージ。PR#418（base=feat/flow-review-execution-budget = PR#417のheadブランチ、PR#417の上に積んだスタック）は base ブランチ削除と同時に GitHub が自動的に CLOSED にした（mergeable=CONFLICTING/mergeStateStatus=DIRTY として表面化）。`gh pr edit 418 --base main` は無関係な `GraphQL: Projects (classic) is being deprecated` エラーで見かけ上失敗し反映もされず、`gh pr reopen 418` も `Could not open the pull request` で失敗（base ブランチが存在しない状態からは reopen 不可）。復旧は「同じ head ブランチ（まだ remote に存在）から base=main で新規 PR を作り直す」のみ。head ブランチの内容は不変（PR#417 の内容が既に main に入っているため diff も自動的に縮小される）。

**Suggested Action:** 複数PRがスタックしている（PR-Bの base = PR-Aのheadブランチ）場合、PR-Aを `--delete-branch` でマージする前に、必ず先に PR-B の base を `gh pr edit <B> --base main`（または次段の実ブランチ）へ retarget してから PR-A をマージする。retarget 後は `gh pr view <B> --json baseRefName` で反映を確認すること（`gh pr edit` は Projects Classic 由来の無害な GraphQL エラーを返すことがあり、エラー表示だけでは実際に反映されたか判断できない）。手遅れで closed になった場合は reopen を試みず、同じ head ブランチから base=main で新規 PR を作成する。

**Source:** Issue #411 PR-1(#417)/PR-2(#418→#419) マージ作業
**Related Files:** N/A（gh CLI 操作手順の問題、特定ファイルに紐付かない）
**Tags:** gh-cli, pr-stacking, branch-deletion, pr-merge
**Pattern-Key:** gh-pr-delete-branch-closes-stacked-pr
**Recurrence-Count:** 1
**Status:** resolved
**Knowledge-Status:** pending

### ERR-20260907-001
**Summary:** codex-companion `task --model gpt-5.6` が `400 invalid_request_error: The 'gpt-5.6' model is not supported when using Codex with a ChatGPT account.` で即失敗（4秒）

**Details:** Issue #411 草案の R2 設計レビューを `node codex-companion.mjs task --background --model gpt-5.6 --prompt-file ...` で発行したところ turn 開始直後に上記エラーで failed。ChatGPT アカウント経由の Codex では `gpt-5.6` 素の指定が不可。`--model` を外してデフォルトモデルで再発行したら正常起動（task-mtqll343-asabwi）。plangen skill が使う `gpt-5.6-sol` / `gpt-5.6-luna` は許可されるが、素の `gpt-5.6` は別扱い。

**Suggested Action:** codex-companion の `task` は原則 `--model` を付けない（デフォルトに任せる）。モデル固定が必要な場合は `gpt-5.6-sol` / `gpt-5.6-luna` のような許可された変種名を使う。`gpt-5.6` 素指定はしない。

**Source:** Issue #411 R2 レビュー発行
**Related Files:** ~/.claude/plugins/cache/openai-codex/codex/1.0.5/scripts/codex-companion.mjs
**Tags:** codex-companion, model-selection, chatgpt-account
**Pattern-Key:** codex-companion-task-model-gpt56-unsupported
**Recurrence-Count:** 1
**Status:** resolved
**Knowledge-Status:** pending

### ERR-20260825-004
**Summary:** `.wslconfig`のmemory=26GB化後もFreeToken cold startが host RAM不足でクラッシュ（`cudaHostRegister failed: out of memory`）。WSL全体のフリーズは再発せず、プロセス単体の異常終了に抑制できた

**Details:** [[ERR-20260825-003]]の`model.safetensors.index.json`ワークアラウンド適用後、WSL2 `.wslconfig`を`memory=26GB`（swap込み計32GB）に変更・`wsl --shutdown`で反映確認済みの状態で、`systemd-run --user --scope -p MemoryMax=24G -p MemorySwapMax=0`配下（`timeout 900`併用）で`ft serve --model-path <NVFP4 snapshot> --moe-backend offload --nvfp4-backend auto`を起動した。mixed-fp8 weightsロード(3/3, 36秒)は成功、続くNVFP4 expert banksロード(3/3, 3分11秒、"low free RAM -> serial build"警告あり)も進行完了したが、直後の`PinPipeline`でのpinned host memory登録(`freetoken/moe/host_banks.py:91` `bank.pin()` → `cudaHostRegister`)が`RuntimeError: cudaHostRegister failed: out of memory`で失敗し、バックエンドworkerがクラッシュ、サーバーが`503`→`server unavailable: maintenance failed (restart required)`で応答不能になった（プロセスは`INFO: Shutting down`で正常終了し、systemdスコープも自然消滅）。cgroup memory使用量をポーリングした結果、expert bank構築中に線形増加し(21.8G→22.5G→23.4G→23.6G→24.0G)、クラッシュ直前に`MemoryMax=24G`上限へ到達していたことを確認済み。エラー文言が"cudaHostRegister failed for 0.0 GiB"（サイズ0GiB表示）となっており、これはFreeToken側のログ整形バグの可能性がある（実際に登録しようとしたバッファサイズがログに正しく出ていない）が、根本原因はホストRAM枯渇でpinned page確保に失敗したことで一致している。**前回セッションで疑われた「WSL2ごとフリーズ」は今回発生せず**、`systemd-run`のcgroupメモリ上限がOOM killerより先にCUDA側のメモリ確保失敗として顕在化し、プロセス単体のクラッシュに抑制できたことが確認できた（安全策としては機能した）。

**Suggested Action:** 22GB checkpoint + NVFP4 expert bank構築時のpinned memory要求は、`.wslconfig memory=26GB`（`MemoryMax=24G`のcgroup制限込み）でもホストRAM不足でcold startが失敗する。次に試すなら(1) `MemoryMax`を26GBのVM上限ぎりぎり（例: 25.5G）まで引き上げる、(2) `.wslconfig`のmemory自体を28GB以上に再度引き上げる（Windows側実測空き12.8GBとの兼ね合いを再確認）、(3) `--expert-load serial`は既定で自動選択されており変更余地なし、(4) pinned memory自体を使わない構成（`--moe-backend cpu`等、性能は落ちる）を検討、のいずれか。現状のfeasibility gateはNG判定継続。

**Source:** project_freetoken_magi_upgrade_rejected.md — Step 0 feasibility gate（cold start計測、`.wslconfig`変更・`wsl --shutdown`後の再試行）
**Related Files:** (プロジェクト外) freetoken/moe/host_banks.py:89-91 `pin()`、/mnt/c/Users/ylocal/.wslconfig
**Tags:** freetoken, wsl2, cudaHostRegister, oom, pinned-memory, cold-start
**Pattern-Key:** freetoken-nvfp4-coldstart-pinned-memory-oom
**Recurrence-Count:** 1
**Status:** confirmed
**Knowledge-Status:** pending

### ERR-20260825-003
**Summary:** FreeTokenのHFダウンローダーが`*.safetensors`のみ許可するallow_patternsのため、NVFP4チェックポイントの必須`model.safetensors.index.json`を取得できず、約24GBのダウンロード完了直後にロード失敗する

**Details:** `ft serve --model nvidia/Qwen3.6-35B-A3B-NVFP4`実行時、checkpointダウンロード自体（~24GB、mixed-fp8 weights 3/3ロード成功）は正常完了したが、その後のNVFP4 expert-bank構築(`freetoken/models/nvfp4_banks.py:91` `load_nvfp4_expert_source_banks`)が`model.safetensors.index.json`を開こうとして`FileNotFoundError`でクラッシュし、バックエンドworkerが落ちてサーバー全体が停止した。原因は`freetoken/utils/hf.py:207-215`の`download_hf_weight()`が`snapshot_download(model_path, allow_patterns=["*.safetensors"])`のみを使っており、JSON拡張子の`model.safetensors.index.json`がこのglobにマッチせず一度もダウンロード対象にならないため。この関数はqwen3_5_moe/glm4_moe/glm_moe_dsa/minimax_m3/deepseek_v4等、全MoEモデルの重みロード経路で共通利用されている（`weight.py`は各shardのsafetensorsヘッダから自力でshard mapを再構成するため気づかれにくいが、`nvfp4_banks`だけは事前ビルド済みindexファイルを必須とする）。GitHub側で既知: Issue #124が報告、PR #129（未マージ、2026-08-24作成）が`allow_patterns`に`*.json`を追加する修正を提出済み。PR本文には「repoから該当ファイルを手動でsnapshotディレクトリに配置するワークアラウンドで動作確認済み（RTX 4090、262,144 ctx、42.2 tok/s decode）」との記載あり。同じワークアラウンドを適用: `huggingface_hub.hf_hub_download(repo_id="nvidia/Qwen3.6-35B-A3B-NVFP4", filename="model.safetensors.index.json")`で該当ファイルのみ追加ダウンロードし、HFキャッシュの同一snapshotディレクトリに正しく配置(シンボリックリンク込み)されることを確認。

**Suggested Action:** FreeTokenでHF repo idを直接`--model`に渡してNVFP4/量子化チェックポイントをロードする場合、ダウンロード完了後に`model.safetensors.index.json`欠落によるクラッシュが起き得ることを事前に想定する。クラッシュしたら都度手動ダウンロードでしのぐより、事前に`hf_hub_download(repo_id=..., filename="model.safetensors.index.json")`を先回りで実行してから`ft serve`を起動すると手戻りが無い。PR #129がマージされたら本ワークアラウンドは不要になる想定——freetokenのバージョンアップ時にリグレッションが直っているか確認すること。

**Source:** project_freetoken_magi_upgrade_rejected.md — Step 0 feasibility gate（checkpointダウンロード〜`ft serve`起動）
**Related Files:** (プロジェクト外) freetoken/utils/hf.py:207-215 `download_hf_weight()`、freetoken/models/nvfp4_banks.py:91
**Tags:** freetoken, huggingface, nvfp4, download, upstream-bug
**Pattern-Key:** freetoken-nvfp4-missing-index-json-download
**Recurrence-Count:** 1
**Status:** confirmed
**Knowledge-Status:** documented

### ERR-20260825-001
**Summary:** FreeToken(`freetoken[accel]`)のCUDA JITビルドが、pip単独導入のCUDAコンポーネント群で3層の環境不整合を起こした

**Details:** MAGI MELCHIORのFreeTokenアップグレード検証（feasibility gate、`ft bench bw`実行）で、`uv pip install "freetoken[accel]"`のみ導入した状態から`ft bench bw --model qwen3.6-moe`のPCIe gatherカーネル(`fast_index_copy`)JITビルドが3段階で失敗した。(1) `nvidia-cuda-nvcc==13.0.88`を追加導入したが、依存解決で`nvidia-nvvm`/`nvidia-cuda-crt`が最新の`13.3.73`に引かれ、nvcc(13.0.88)がPTX .version 9.0までしか扱えないのにnvvm(13.3.73)がPTX .version 9.3を生成し`ptxas fatal: Unsupported .version 9.3; current version is '9.0'`で失敗。(2) `gcc`本体が未導入（`nvidia-cuda-runtime`等のpipパッケージはランタイムライブラリのみでホストコンパイラを含まない）で`nvcc fatal: Failed to preprocess host compiler properties`が先に発生していた（ユーザーが`apt install build-essential`で解消）。(3) nvcc/nvvmをどちらも`13.3.73`に揃えてコンパイルは通ったが、リンク時に`-lcudart`が解決できず失敗——pipの`nvidia-cuda-nvcc`パッケージ群は`lib/`配下に`libcudart.so.13`のみを配置し、`lib64/`ディレクトリも無版数シンボリックリンク`libcudart.so`も持たない。一方FreeTokenのビルドスクリプトは`-L.../nvidia/cu13/lib64`を決め打ちで参照するため、pipオンリー構成とは構造的に噛み合わない。install.mdには"need a CUDA 13 toolkit with nvcc on PATH"としか書かれておらず、pipオンリー構成向けの注意書きは無い（公式に非対応の組み合わせ）。

**Suggested Action:** FreeTokenのJITビルドを使う場合は最初から`sudo apt-get install -y cuda-toolkit-13-<minor>`でNVIDIA公式CUDA toolkitをフル導入する（WSL2は`https://developer.download.nvidia.com/compute/cuda/repos/wsl-ubuntu/x86_64/`のkeyringを先に登録）。`nvidia-cuda-nvcc`等の分割pipパッケージだけで揃えようとしない——lib64構成・無版数シンボリックリンク・依存パッケージ間のバージョン整合が保証されない。[[ERR-20260825-002]]（同じ検証で連続発生したCUDA/glibc不整合）と合わせて、CUDA toolkitのバージョンはUbuntu側のglibcとの組み合わせも要確認。

**Source:** project_freetoken_magi_upgrade_rejected.md — Step 0 feasibility gate（`ft bench bw`実行）
**Related Files:** (プロジェクト外、FreeTokenパッケージ側) freetoken/kernel/csrc配下のJITビルド、docs/install.md
**Tags:** freetoken, cuda, nvcc, pip-packaging, jit-build
**Pattern-Key:** freetoken-pip-only-cuda-jit-build-mismatch
**Recurrence-Count:** 1
**Status:** confirmed
**Knowledge-Status:** documented

### ERR-20260825-002
**Summary:** apt導入のCUDA 13.0 toolkitがUbuntu 26.04の新しいglibcヘッダと衝突し`rsqrt`/`rsqrtf`の例外指定不一致でコンパイル失敗

**Details:** [[ERR-20260825-001]]のリンクエラー解消のため`sudo apt-get install -y cuda-toolkit-13-0`（NVIDIA公式wsl-ubuntuリポジトリ、13.0.3）を導入し`CUDA_HOME=/usr/local/cuda`で`ft bench bw`を再実行したところ、FreeTokenのJITビルド(`fast_index_copy`カーネル)コンパイルが`/usr/include/x86_64-linux-gnu/bits/mathcalls.h(206): error: exception specification is incompatible with that of previous function "rsqrt"`（`rsqrtf`も同様）で失敗した。CUDA 13.0(`crt/math_functions.h`)がリリースされた時点（2025年半ば）ではUbuntu 26.04 "Resolute Raccoon"（本セッション時点の稼働OS、glibc版が新しく`rsqrt`/`rsqrtf`をnoexcept付きで再宣言）がまだ存在せず、両者のGNU拡張関数宣言のnoexcept指定が食い違うバージョン間非互換だった。apt-cache policyで`cuda-toolkit-13-3`(13.3.1)が同リポジトリから入手可能と判明し、これに切り替えたところ（ユーザーが`sudo apt-get install -y cuda-toolkit-13-3`実行）問題なくコンパイル・リンクとも成功した。

**Suggested Action:** 非常に新しいUbuntuリリース（LTS未満の中間バージョン含む）でCUDA toolkitを導入する際、まずディストリのデフォルト最新（このケースでは13-0）を疑わずに試すのではなく、`apt-cache policy cuda-toolkit-13-<N>`で入手可能な最新マイナーバージョンを先に確認し、それを導入する。ビルドエラーの文言に`mathcalls.h`や`exception specification is incompatible`が出た場合はCUDA toolkitとglibcのバージョンスキューを疑い、まずCUDA toolkitを最新マイナーに上げてみる（glibc側のダウングレードは非現実的）。

**Source:** project_freetoken_magi_upgrade_rejected.md — Step 0 feasibility gate（`ft bench bw`実行、[[ERR-20260825-001]]の続き）
**Related Files:** /usr/local/cuda（apt管理シンボリックリンク）
**Tags:** cuda, glibc, ubuntu, toolkit-version-skew
**Pattern-Key:** cuda-toolkit-glibc-rsqrt-exception-spec-mismatch
**Recurrence-Count:** 1
**Status:** confirmed
**Knowledge-Status:** documented

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

### ERR-20260805-001
**Summary:** `llm -T MCP` がローカルOllamaモデルでMCPツール呼び出しをdispatchせず、knowledge-rag登録が静かに失敗する

**Details:** `skills/remember/SKILL.md` および新規 `skills/learnings-promote/SKILL.md` が使う `"$LLM" prompt -m "$MODEL" -T MCP --no-stream` 呼び出しで、MCPサーバー（knowledge-rag）側ログには `ListToolsRequest` のみが記録され `CallToolRequest` に到達しない。`qwen2.5:3b`（設定ファイル既定モデル）では出力が完全に空（exit code 0、stdout/stderrとも空）、`--td`（tool-debug）でも何も表示されない。`qwen2.5-coder:7b` に切り替えると `--td` はモデルが生成した妥当なtool call JSON（`add_document`、正しいfilepath/category/content）を表示するが、それでもMCPサーバーには `CallToolRequest` が届かない。原因は `llm-tools-mcp`/`llm-ollama` 側のツール呼び出しディスパッチの問題と推定されるが未特定（`~/.llm-tools-mcp/mcp.json` の設定・`mcp_server.server` 単体起動はいずれも正常）。`KNOWLEDGE_RAG_DIR`・`OLLAMA_HOST` を呼び出し元シェルでexportしても、`mcp.json` に `env` キーが無いため、MCPサーバーの子プロセスにはPython MCP SDKの `get_default_environment()`（HOME/LOGNAME/PATH/SHELL/TERM/USERのみ）しか継承されない点も別途確認（今回のdispatch失敗の直接原因ではなさそうだが、環境変数依存の副作用が起きうる設計）。

**Suggested Action:** `remember`・`learnings-promote` はいずれも「成功痕跡が確認できなければ登録失敗として扱いStatusを更新しない」設計になっており、危険側には倒れていない（サイレントなデータ破損はない）が、`remember` は現状ユーザーに気づかれず登録し続けているつもりが実際には何も登録されていない可能性が高い。別Issueとして起票し、(1) `llm-tools-mcp`/`llm-ollama` バージョンアップでの解消有無、(2) MCPクライアント実装を `llm` CLI 経由でなくPython `mcp` SDKで直接呼ぶ代替経路、を検討する。

**Source:** PR #378（learnings-promote実機検証）
**Related Files:** skills/remember/SKILL.md, skills/learnings-promote/SKILL.md
**Tags:** knowledge-rag, mcp, ollama, llm-cli
**Pattern-Key:** llm-mcp-tool-dispatch-silent-failure
**Recurrence-Count:** 1
**Status:** pending
**Knowledge-Status:** pending

### ERR-20260805-002
**Summary:** MAGI Normalizer（qwen3:4b-instruct）が候補間でpersona/evidenceを混入させたが、lossless突合・スキーマ検証の双方をすり抜けた

**Details:** magi-fastのバッチNormalizer呼び出しで、MELCHIORの指摘（`error-detector.sh:78`、evidence無し）が出力JSONで `persona: "BALTHASAR"` に誤帰属され、さらにCASPERの指摘に付いていたEvidence文言（`Old: ... → New: ...`）がこのMELCHIOR由来の候補に混入した。加えて2件目の候補では `persona` フィールドに `"BALTHASิAR"`（タイ文字の結合文字が混入した文字化け）が出力された。`normalizer.md` が定義する検証（`_normalizer_valid`のスキーマチェック、`^Location:`行数と出力配列長のlossless突合）はいずれも通過した——スキーマ検証はフィールドの型・必須性のみを見ており、値の意味的な正しさ（どの候補がどのpersonaに属するか、evidenceが正しい候補のものか）は検証していないため。

**Suggested Action:** 候補が少数（3件）だったため今回はNormalizer出力を破棄し手動でJSONを再構築して対処した。件数が多い場合にこの種の混入をどう検出するかは未解決。対策候補: (1) 入力側で候補ごとに一意なsentinel ID（`CANDIDATE-001`等）を付与し、出力にも同じIDを含めさせて突合する、(2) persona値が入力ヘッダーに実在する値の集合に含まれるかをスキーマ検証に追加する、(3) evidence文字列が入力の対応するブロック内に実在するかを文字列照合で検証する。いずれも今回は未実装。

**Source:** PR #378（learnings-promote、MAGI-FAST実行時）
**Related Files:** skills/magi-common/references/normalizer.md
**Tags:** magi, normalizer, ollama, data-integrity
**Pattern-Key:** magi-normalizer-persona-evidence-crosscontamination
**Recurrence-Count:** 1
**Status:** pending
**Knowledge-Status:** pending

### ERR-20260805-003
**Summary:** CASPER/MELCHIOR/BALTHASARのHaiku fallback用エージェント定義ファイル（`agents/casper.md`等）がrepo・グローバルいずれにも存在しない

**Details:** `skills/magi-common/references/execution-steps.md` は Haiku fallback パスで `agents/<persona>.md`（repo内優先、無ければ `~/.claude/agents/<persona>.md`）を読み込む前提だが、`melchior.md`・`balthasar.md`・`casper.md` のいずれも `agents/` ディレクトリ（repo・グローバル双方）に存在しない（`agents/`には`code-reviewer.md`・`leliel.md`のみ）。CASPERは `casper/SKILL.md` で「Ollamaパスを使用しない。常にHaikuパスを実行する」と明記されているため、この欠落は毎回のCASPER実行で該当ファイル参照が失敗することを意味する。今回はtask-instruction.md（Your Role節）とreview-criteria.mdの内容で代替してAgent呼び出しを構成し実害なく完了したが、これは手順の必須ファイルが恒常的に見つからない状態であり、今後CASPER実行のたびに同じ代替が必要になる。

**Suggested Action:** `agents/melchior.md`・`agents/balthasar.md`・`agents/casper.md` を新規作成するか、execution-steps.mdのHaiku fallback手順から「エージェント定義ファイル読み込み」の記述を削除し「task-instruction.md + review-criteria.mdで十分」と明記するかのいずれかで整合させる。

**Source:** PR #378（learnings-promote、MAGI-FAST CASPER実行時）
**Related Files:** skills/magi-common/references/execution-steps.md, skills/casper/SKILL.md
**Tags:** magi, casper, agents, missing-file
**Pattern-Key:** magi-persona-agent-definition-missing
**Recurrence-Count:** 1
**Status:** pending
**Knowledge-Status:** pending

### ERR-20260805-004
**Summary:** `lean-ctx config set shell_allowlist '[]'` が空配列でなく文字列 `"[]"` を書き込み、意図と逆に allowlist を制限的な状態にする

**Details:** 新規環境の SessionEnd hook で `kizami save --stdin` が lean-ctx の shell allowlist に未登録のためブロックされる不具合を調査中、`shell_allowlist = []`（空配列＝allowlist無効化・全コマンド許可）を明示的に書き込む目的で `lean-ctx config set shell_allowlist '[]'` を実行した。結果、config.toml には `shell_allowlist = ["[]"]`（文字列 `"[]"` を要素に持つ配列）が書き込まれ、`lean-ctx doctor` は "2 command(s) enforced" と報告した。これは元々の「全許可」状態から一転して「`"[]"` と `kizami` の2つしか許可しない」制限状態への regression であり、他の全コマンドがブロックされる状態になっていた。TOML の値をシェル経由でCLI引数として渡す際、空配列リテラル `[]` が空配列としてパースされず文字列として扱われるパーサ側の不具合と考えられる。`lean-ctx allow <cmd>` コマンド（config.toml が存在しない場合に新規生成し、その際 `shell_allowlist = []` を正しい空配列として書き込む）は同じ問題を起こさなかった。

**Suggested Action:** `lean-ctx config set shell_allowlist <value>` は使わない。allowlist を無効化したい場合は (1) config.toml が存在しなければ `lean-ctx allow <任意のcmd>` を1回実行して新規生成させる、または (2) config.toml に直接 `shell_allowlist = []` の行を追記する（本セッションでは setup/250-lean-ctx.sh に後者の冪等チェックを追加した）。誤って `["[]"]` になってしまった場合は config.toml を直接編集して `shell_allowlist = []` に戻せば復旧する。

**Source:** 新規環境ワンライナーセットアップ後の SessionEnd hook エラー対応
**Related Files:** setup/250-lean-ctx.sh, ~/.config/lean-ctx/config.toml
**Tags:** lean-ctx, config, cli-bug, shell-allowlist
**Pattern-Key:** lean-ctx-config-set-empty-array-string-bug
**Recurrence-Count:** 1
**Status:** pending
**Knowledge-Status:** pending

### ERR-20260820-001
**Summary:** `codex-companion.mjs adversarial-review --help` が使い方表示ではなく実際のレビュージョブをフォアグラウンド起動した

**Details:** dev-flow Phase 5 の代替として Codex レビューを起動する前に、コマンドの使い方を確認する目的で `node codex-companion.mjs adversarial-review --help` を実行した。`--help` は認識されないオプションとして無視され、通常の `adversarial-review`（working-tree diff 全体を対象とする本番レビュー）がそのままフォアグラウンドで開始された。Bash ツールのデフォルトタイムアウト（2分）を超えて実行が続いたため呼び出し元コマンドはエラー扱いで返ったが、レビュー本体は codex app-server 側で検知プロセスとして動作し続けており（`state/.../jobs/review-<id>.log` に進捗が書き込まれ続けている）、ジョブ自体は生きていた。結果的に意図せぬタイミングで本番レビューが起動しただけで、対象diffは正しかったため実害はなかったが、`--help` 目的の呼び出しが実コストのかかるジョブを誤爆させる点は再発しうる。

**Suggested Action:** `codex-companion.mjs` のヘルプ確認は `--help` に頼らず、スクリプト本体（`.mjs` ファイル）を直接 grep/read してサブコマンドと引数を確認する。誤って本番コマンドを引数なし/`--help`付きで叩いてしまった場合は、慌てて cancel せず `status <job-id>` とログ mtime でジョブが正常に走っているか確認し、意図した diff を対象にしていれば継続利用して良い。

**Root Cause（Codex自身への調査依頼で判明、2026-08-20）:** 仕様ではなくCLIの安全性バグと確認。`--help` の特別扱いは最上位 subcommand のみで実装されており（`codex-companion.mjs:1024-1028`）、`adversarial-review` サブコマンドの `booleanOptions` には `help` が定義されていない（同:712-719）。引数パーサー（`lib/args.mjs:27-49`）は未知の long option をエラーにせず positionals に入れるため、`--help` がそのまま `focusText`（同:712-729）として本番レビューに渡ってしまう。各サブコマンドで `--help`/`-h` を明示処理するか、未知オプションを reject するのが恒久対応。

**Source:** Issue #389 dev-flow Phase 5 代替レビュー起動
**Related Files:** /home/ylocal/.claude/plugins/cache/openai-codex/codex/1.0.5/scripts/codex-companion.mjs
**Tags:** codex-companion, cli-usage, background-job, help-flag
**Pattern-Key:** codex-companion-help-flag-triggers-real-job
**Recurrence-Count:** 1
**Status:** confirmed
**Knowledge-Status:** documented

### ERR-20260820-002
**Summary:** `codex-companion.mjs` のバックグラウンドジョブが基盤プロセス死亡後も `status` 上は "running" のまま残る

**Details:** Issue #389 の Codex adversarial-review（`review-mt15ordu-1d2qx9`）で、基盤プロセスが（親のstate永続化より先にworkerが起動し得るrace、またはSIGKILL/OOM/親終了等）死亡した後も `status <job>` は "running" を返し続けた。実データでも state.json 上は running/pid=1435872 のままだったが `ps` にはそのPIDが存在せず、ログの最終更新も止まっていた。原因をCodex自身に調査依頼し判明: `enqueueBackgroundTask` はdetached workerをspawnした後にqueued/running状態を書く実装（`codex-companion.mjs:671-698`）で、workerが起動直後に`readStoredJob`（同:849-852）を行うため親の永続化と競合するrace がある。`runTrackedJob`（`lib/tracked-jobs.mjs:142-152`）はpidを記録するが、正常完了・捕捉可能な例外以外を回収するsupervisor/finallyが存在しない。`status`コマンド自体（`lib/job-control.mjs:213-239`）もstateを読むだけで、pidの生存確認（kill -0）やログmtime監視を一切行っていない。

**Suggested Action:** `status <job>` の "running" 表示を鵜呑みにしない。長時間"running"のままの場合は `ps -p <pid>`（state.jsonのpidフィールド参照）とログファイルのmtimeを直接確認し、プロセス不在またはmtime停滞（目安600秒超）ならスタール扱いで打ち切る。この確認は単発の `Bash run_in_background` ポーリング（完了/スタール判定時のみ1回通知、Monitorツールは毎回通知されるため使わない）で行う。恒久対応（companion側のsupervisor/liveness実装）はこちらでは着手しない。

**Source:** Issue #389 Codex adversarial-review実行、Codexへの`.agmsg`調査依頼
**Related Files:** /home/ylocal/.claude/plugins/cache/openai-codex/codex/1.0.5/scripts/codex-companion.mjs, lib/tracked-jobs.mjs, lib/job-control.mjs
**Tags:** codex-companion, background-job, race-condition, process-liveness
**Pattern-Key:** codex-companion-dead-pid-status-running
**Recurrence-Count:** 3
**Status:** confirmed
**Knowledge-Status:** documented

### ERR-20260820-003
**Summary:** `codex-companion.mjs` のjob registryから正常完了ジョブのエントリが消失するが、jobファイル自体は残る

**Details:** `status`/`result <job>` が "No job found" を返しjob registryからエントリごと消えているのに、`jobs/<job-id>.log`/`.json` はディスクに残っており、直接読めば正常完了していたと分かるケースが複数回発生した。原因をCodex自身に調査依頼し判明: `updateState`は無ロックのread-modify-write、`saveState`もアトミック書き込みでなく直接`writeFileSync`（`lib/state.mjs:92-122`）。同時書込み中に別プロセスが`loadState`するとJSON parse失敗を握りつぶしてdefault state（jobs=[]）に黙って戻り（同:65-76）、その後のupsert/saveで他ジョブのregistryエントリを落とし得る（正常な同時read-modify-writeでもlast-writer-winsで落ちる）。job本体ファイルは`writeJobFile`（同:166-170）でstate更新とは別経路に書かれ、削除処理は`saveState`が読めた`previousJobs`のみが対象（同:93,105-112）のため、registryだけ消えてもjobファイルは残る。

**Suggested Action:** `status`/`result`が"No job found"を返しても即座に失敗と判断しない。`jobs/<job-id>.log`・`.json`を直接読んで完了状況を確認する（本セッションで確立済みの対処法）。複数のCodexバックグラウンドジョブをほぼ同時に起動しない（registry書き込みが競合するrace自体を避ける）。恒久対応（companion側のロック/アトミック書き込み実装）はこちらでは着手しない。

**Source:** Issue #389 Codex adversarial-review/task実行、Codexへの`.agmsg`調査依頼
**Related Files:** /home/ylocal/.claude/plugins/cache/openai-codex/codex/1.0.5/scripts/codex-companion.mjs, lib/state.mjs
**Tags:** codex-companion, background-job, race-condition, state-persistence
**Pattern-Key:** codex-companion-registry-entry-lost-race
**Recurrence-Count:** 2
**Status:** confirmed
**Knowledge-Status:** documented
