# METATRON TypeScript Security Flaws Fixture Answer Key

## 目的

この fixture は、METATRON のセキュリティ観点で、TypeScript/Express の一般的なアプリコードに仕込まれた既知の脆弱性をどれだけ raw finding として検出できるかを測定するための合成 diff である。
主用途は候補モデルの**比較**であり、severity 付けの正確さではなく、DETECTION NOTES 契約の `Location` / `Problem` / `Breakage` を落とさず抽出できるかを確認する。

## 使い方

`skills/magi-common/references/execution-steps.md` のステップ 2 と同じ組み立てで、METATRON 用の `system.txt` / `prompt.txt` を作る。

- `system.txt`: `skills/metatron/references/task-instruction.md`、`skills/metatron/references/review-criteria.md`、`skills/magi-common/references/output-format-v2.md`
- `prompt.txt`: `skills/magi-common/references/task-base.md` の後に `<TASK>` / `</TASK>` で包んだ `scripts/tests/fixtures/metatron-security-flaws-ts.diff`

**注意:** `skills/magi-common/references/output-format.md`（severity付きの旧フォーマット）は使わない。`output-format-v2.md` は、`task-instruction.md` に埋め込まれた `### [HIGH]` 形式の Example Output より優先される旨を自身の中で明記しており、それを system.txt の最後に置くことで severity 形式の Example が無効化される設計になっている。

## 正解キー表

| ID | 仕込んだ欠陥の説明 | review-criteria の観点 | expected_raw_findings | allowed_locations | evidence_quotes | duplicate_groups | out_of_scope_decoys |
| --- | --- | --- | --- | --- | --- | --- | --- |
| TS-S1 | `email` を SQL 文字列へ直接連結しており、検索条件を注入できる。 | Injection | `Location: src/routes/admin.ts:16` / `Problem: email query parameter is concatenated into a SQL statement` / `Breakage: attacker can alter the WHERE clause or append SQL` | `src/routes/admin.ts:16` | `const rows = await db.query("select id, email, role from users where email = '" + email + "'");` | - | `src/routes/admin.ts:15` は `$1` プレースホルダと値配列を使うため SQL injection ではない。 |
| TS-S2 | `req.params.name` を正規化せず `REPORT_ROOT` に join しており、`../` で任意ファイルを読める。 | Injection | `Location: src/routes/admin.ts:22` / `Problem: route parameter is joined into a filesystem path without basename or root containment check` / `Breakage: ../ traversal can download files outside REPORT_ROOT` | `src/routes/admin.ts:21`, `src/routes/admin.ts:22`, `src/routes/admin.ts:23` | `const reportPath = path.join(REPORT_ROOT, requestedName);` | - | `src/routes/admin.ts:54` は `path.basename(req.params.name)` でディレクトリ要素を落としてから join しているため、この fixture では decoy とする。 |
| TS-S3 | `dir` を shell コマンド文字列へ埋め込んで `exec` しており、コマンド注入が可能。 | Injection | `Location: src/routes/admin.ts:30` / `Problem: request body value is interpolated into a shell command passed to exec` / `Breakage: attacker controlled dir can execute additional shell commands` | `src/routes/admin.ts:27`, `src/routes/admin.ts:30` | ``exec(`tar -czf ${archivePath} ${REPORT_ROOT}/${dir}`, (err) => {`` | - | `src/routes/admin.ts:28` の `archiveName` は `path.basename` 済みであり、ここだけを根拠に path traversal と扱わない。 |
| TS-S4 | 本番用途に見える JWT 秘密鍵がソースにハードコードされている。 | Secret leakage | `Location: src/routes/admin.ts:10` / `Problem: JWT secret is committed as a literal string` / `Breakage: source disclosure exposes a reusable secret and rotation requires code changes` | `src/routes/admin.ts:10` | `const JWT_SECRET = "prod-admin-panel-secret";` | - | - |
| TS-S5 | 認証トークンを `jwt.decode` で読むだけで、署名検証や `algorithms` 制約をしていない。 | Insufficient authentication validation | `Location: src/routes/admin.ts:38` / `Problem: JWT claims are trusted from decode without verify` / `Breakage: forged token with admin=true is accepted` | `src/routes/admin.ts:37`, `src/routes/admin.ts:38`, `src/routes/admin.ts:39` | `const claims = jwt.decode(token) as { sub?: string; admin?: boolean } \| null;` | - | `src/routes/admin.ts:10` の `JWT_SECRET` はこの欠陥では使われていないため、検出時は hardcoded secret と JWT verification bypass を別 finding として扱う。 |
| TS-S6 | リクエストボディの URL をそのまま `fetch` しており、内部ネットワークへの SSRF が可能。 | Insufficient input validation | `Location: src/routes/admin.ts:48` / `Problem: user supplied URL is fetched without allowlist or scheme validation` / `Breakage: attacker can make the server request internal metadata or admin endpoints` | `src/routes/admin.ts:47`, `src/routes/admin.ts:48` | `const response = await fetch(target);` | - | - |

## 採点基準

- raw_recall: TS-S1〜TS-S6 のうち何件を検出できたか。検出と認めるには `allowed_locations` のいずれかに対応し、`Problem` と `Breakage` が同じ欠陥を指していること。
- lossless 性: `expected_raw_findings` の意味を落とさず、Location/Problem/Breakage を分離して説明できていること。
- 重複: TS-S5 と TS-S4 のように同じ周辺行から見つかる別欠陥は別 finding とし、同一欠陥の言い換えは 1 件に正規化すること。
- decoy 耐性: `out_of_scope_decoys` に挙げた安全な行を欠陥として数えないこと。
- 捏造: diff に存在しないファイル、関数、設定値、外部コンポーネントを根拠にしないこと。

## 合格条件

- raw_recall が 6 件中 4 件以上である。
- TS-S1、TS-S3、TS-S5 のうち 2 件以上を検出している。
- decoy を欠陥として数えた誤検知が 1 件以下である。
- Location/Problem/Breakage の三要素が追跡でき、根拠行が diff 内にある。
