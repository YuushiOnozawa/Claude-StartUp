# SANDALPHON TypeScript Deploy Flaws Fixture Answer Key

## 目的

この fixture は、SANDALPHON の実行環境・デプロイ観点で、TypeScript/Express の起動コードに仕込まれた既知の運用欠陥をどれだけ raw finding として検出できるかを測定するための合成 diff である。
主用途は候補モデルの**比較**であり、severity 付けではなく、起動失敗・情報漏えい・停止不能・運用不能につながる根拠を Location/Problem/Breakage として抽出できるかを確認する。

## 使い方

`skills/magi-common/references/execution-steps.md` のステップ 2 と同じ組み立てで、SANDALPHON 用の `system.txt` / `prompt.txt` を作る。

- `system.txt`: `skills/sandalphon/references/task-instruction.md`、`skills/sandalphon/references/review-criteria.md`、`scripts/tests/fixtures/detection-notes-format.md`
- `prompt.txt`: `skills/magi-common/references/task-base.md` の後に `<TASK>` / `</TASK>` で包んだ `scripts/tests/fixtures/sandalphon-deploy-flaws-ts.diff`

**注意:** `skills/magi-common/references/output-format.md`（severity付きの旧フォーマット）は使わない。`detection-notes-format.md` は、`task-instruction.md` に埋め込まれた `### [HIGH]` 形式の Example Output より優先される旨を自身の中で明記しており、それを system.txt の最後に置くことで severity 形式の Example が無効化される設計になっている。

## 正解キー表

| ID | 仕込んだ欠陥の説明 | review-criteria の観点 | expected_raw_findings | allowed_locations | evidence_quotes | duplicate_groups | out_of_scope_decoys |
| --- | --- | --- | --- | --- | --- | --- | --- |
| TS-D1 | 必須環境変数の検証を削除し、`DATABASE_URL` / `JWT_SECRET` / `DEPLOY_TOKEN` が未設定でも起動処理へ進む。 | Configuration validation | `Location: src/server.ts:8` / `Problem: required env vars are read without fail-fast validation` / `Breakage: service can boot with undefined database or auth settings and fail later at runtime` | `src/server.ts:8`, `src/server.ts:10`, `src/server.ts:11`, `src/server.ts:12`, `src/server.ts:22` | `databaseUrl: process.env.DATABASE_URL,` / `jwtSecret: process.env.JWT_SECRET,` / `deployToken: process.env.DEPLOY_TOKEN,` | - | `src/server.ts:13` の `PUBLIC_ORIGIN` はデフォルト付きで URL として parse される公開 origin なので、必須 secret 未検証として数えない。 |
| TS-D2 | `config` 全体をログ出力し、DB URL、JWT secret、deploy token を漏えいさせる。 | Secret leakage | `Location: src/server.ts:16` / `Problem: startup log prints config containing secrets` / `Breakage: credentials can be captured by centralized logs or CI output` | `src/server.ts:16`, `src/server.ts:10`, `src/server.ts:11`, `src/server.ts:12` | `console.info("boot config", config);` | - | `src/server.ts:17` は commit SHA と nodeEnv だけを出す運用ログなので、この fixture では secret leak ではない。 |
| TS-D3 | HTTP server の request/header timeout を 0 にしており、低速接続でリソースを保持される。 | Runtime resource limits | `Location: src/server.ts:40` / `Problem: HTTP request and header timeouts are disabled` / `Breakage: slow clients can keep sockets open indefinitely and exhaust workers` | `src/server.ts:40`, `src/server.ts:41` | `server.requestTimeout = 0;` / `server.headersTimeout = 0;` | TS-D3 | - |
| TS-D4 | `SIGTERM` で `server.close()` せず即 `process.exit(0)` するため、Kubernetes や systemd の graceful shutdown を壊す。 | Signal handling | `Location: src/server.ts:43` / `Problem: SIGTERM handler exits without closing the server or draining requests` / `Breakage: in-flight deploy requests are terminated and readiness cannot drain cleanly` | `src/server.ts:43`, `src/server.ts:45` | `process.exit(0);` | - | - |
| TS-D5 | `app.listen` と `server.listen` が同じ port で二重 bind し、起動時に `EADDRINUSE` になり得る。 | Startup correctness | `Location: src/server.ts:50` / `Problem: two servers attempt to listen on the same port` / `Breakage: process may crash or expose inconsistent listener state during deploy` | `src/server.ts:50`, `src/server.ts:51` | `app.listen(config.port, () => console.info(\`express listening on ${config.port}\`));` / `server.listen(config.port, () => console.info(\`http listening on ${config.port}\`));` | TS-D5 | - |
| TS-D6 | `start()` の Promise を await/catch せず、さらに `unhandledRejection` を warn だけで握りつぶす。 | Process failure handling | `Location: src/server.ts:54` / `Problem: async startup failures are not caught and unhandled rejections do not fail the process` / `Breakage: failed DB connect can leave a half-started or silently unhealthy deployment` | `src/server.ts:54`, `src/server.ts:56`, `src/server.ts:57` | `start();` / `console.warn("background rejection", err);` | TS-D6 | - |

## 採点基準

- raw_recall: TS-D1〜TS-D6 のうち何件を検出できたか。検出と認めるには `allowed_locations` のいずれかに対応し、`Problem` と `Breakage` が同じ運用欠陥を指していること。
- lossless 性: `expected_raw_findings` の意味を落とさず、Location/Problem/Breakage を分離して説明できていること。
- 重複: TS-D3、TS-D5、TS-D6 は複数行にまたがるが、`duplicate_groups` が同じ行群は 1 欠陥として数えること。
- decoy 耐性: `PUBLIC_ORIGIN` の parse と `runtime` ログを、必須 secret 未検証や secret leak として数えないこと。
- 捏造: diff に存在しない CI、コンテナ、ロードバランサ、外部監視設定を根拠にしないこと。

## 合格条件

- raw_recall が 6 件中 4 件以上である。
- TS-D1、TS-D2、TS-D5 のうち 2 件以上を検出している。
- decoy を欠陥として数えた誤検知が 1 件以下である。
- Location/Problem/Breakage の三要素が追跡でき、根拠行が diff 内にある。
