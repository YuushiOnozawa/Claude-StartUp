# LELIEL TypeScript Caller Break Fixture Answer Key

## 目的

この fixture は、LELIEL の影響範囲・呼び出し元破壊検出で、exported 関数の TypeScript シグネチャ変更に追従できていない caller をどれだけ raw finding として検出できるかを測定するための合成 diff である。
`scripts/tests/fixtures/leliel-caller-break-ts.impact-context.txt` は `git grep` 相当の参照一覧であり、壊れている caller と追従済み caller の両方を含む。壊れている caller のうち `src/jobs/reconcileInvoices.ts` と `src/tests/invoiceTotal.test.ts` は、このコミットで一切変更されていない（＝呼び出し元の追従漏れをそのまま放置している）ため diff には現れず、impact-context.txt からのみ発見できる。diff だけを見て「変更された行に現れないファイルは対象外」と判断すると、この2件は見落とすことになる。

## 使い方

`skills/magi-common/references/execution-steps.md` のステップ 2 と同じ組み立てで、LELIEL 用の `system.txt` / `prompt.txt` を作る。

- `system.txt`: `skills/leliel/references/task-instruction.md`、`skills/leliel/references/review-criteria.md`、`scripts/tests/fixtures/detection-notes-format.md`
- `prompt.txt`: `skills/magi-common/references/task-base.md` の後に `<TASK>` / `</TASK>` で包んだ `scripts/tests/fixtures/leliel-caller-break-ts.diff` と、追加文脈として `scripts/tests/fixtures/leliel-caller-break-ts.impact-context.txt`

**注意:** `skills/magi-common/references/output-format.md`（severity付きの旧フォーマット）は使わない。`detection-notes-format.md` は、`task-instruction.md` に埋め込まれた `### [HIGH]` 形式の Example Output より優先される旨を自身の中で明記しており、それを system.txt の最後に置くことで severity 形式の Example が無効化される設計になっている。

## 正解キー表

| ID | 壊れている呼び出し元 | 破壊内容 | expected_raw_findings | allowed_locations | evidence_quotes | duplicate_groups | out_of_scope_decoys |
| --- | --- | --- | --- | --- | --- | --- | --- |
| TS-L1 | `src/jobs/reconcileInvoices.ts`（diffには現れない、impact-context.txtのみで発見可能） | 新シグネチャは `calculateInvoiceTotal(invoice: Invoice, options: CalculateInvoiceOptions): InvoiceTotal` だが、旧形式の `invoice.lines, invoice.currency` を渡している。戻り値も number として `recordExpectedTotal` や `total > 0` に渡している。このファイル自体は今回のコミットで変更されていない（追従漏れの放置）。 | `Location: src/jobs/reconcileInvoices.ts:6` / `Problem: caller still passes InvoiceLine[] and currency string to calculateInvoiceTotal` / `Breakage: TypeScript call no longer matches required Invoice/options signature and downstream code treats InvoiceTotal as number` | `src/jobs/reconcileInvoices.ts:6`, `src/jobs/reconcileInvoices.ts:7`, `src/jobs/reconcileInvoices.ts:9` | `const total = calculateInvoiceTotal(invoice.lines, invoice.currency);` / `if (total > 0) {` | TS-L1 | `src/api/invoiceRoutes.ts:6` は `invoice` と `{ taxRate, includeDiscounts }` を渡し、`.totalCents` を返しているため追従済み。 |
| TS-L2 | `src/cli/printInvoice.ts` | 必須の `Invoice` オブジェクトと options を渡さず、旧 `lines` だけを渡している。戻り値オブジェクトを文字列補間で旧 number のように扱っている。 | `Location: src/cli/printInvoice.ts:6` / `Problem: caller invokes calculateInvoiceTotal with only invoice lines after the function now requires invoice and options` / `Breakage: compile-time arity/type error and printed total becomes an object if forced through` | `src/cli/printInvoice.ts:6`, `src/cli/printInvoice.ts:7` | `const total = calculateInvoiceTotal(invoice.lines);` / ``process.stdout.write(`${invoice.id}: ${total} ${invoice.currency}\n`);`` | TS-L2 | `src/reports/monthlyRevenue.ts:6` は options を渡し `.totalCents` を読むため追従済み。 |
| TS-L3 | `src/tests/invoiceTotal.test.ts`（diffには現れない、impact-context.txtのみで発見可能） | テストが旧 API の `lines, currency` と number 戻り値を期待したままで、新しい options と `InvoiceTotal.totalCents` に追従していない。このファイル自体は今回のコミットで変更されていない（追従漏れの放置）。 | `Location: src/tests/invoiceTotal.test.ts:5` / `Problem: test still calls calculateInvoiceTotal with old arguments and expects a number` / `Breakage: test no longer compiles and asserts the wrong return shape` | `src/tests/invoiceTotal.test.ts:5` | `expect(calculateInvoiceTotal(lines, "USD")).toBe(900);` | - | `src/widgets/invoicePreview.ts:4` の `calculateInvoiceTotalPreview` は名前が似ているだけの別関数で、シグネチャ変更された `calculateInvoiceTotal` の caller ではない。 |

## 採点基準

- raw_recall: TS-L1〜TS-L3 のうち何件を検出できたか。検出と認めるには `allowed_locations` のいずれかに対応し、`Problem` と `Breakage` が同じ caller 破壊を指していること。
- impact-context 利用: `.impact-context.txt` にある caller 一覧から、追従済みの `src/api/invoiceRoutes.ts` と `src/reports/monthlyRevenue.ts` を除外し、壊れている caller だけを残せていること。
- lossless 性: `expected_raw_findings` の意味を落とさず、Location/Problem/Breakage を分離して説明できていること。
- 重複: TS-L1 は 1 つの誤った呼び出しから戻り値利用まで連鎖するが、同じ caller 破壊として 1 件に正規化すること。
- decoy 耐性: `calculateInvoiceTotalPreview` のような名前が似た別関数や、追従済み caller を欠陥として数えないこと。
- 捏造: diff と impact-context に存在しない caller、型、戻り値フィールドを根拠にしないこと。

## 合格条件

- raw_recall が 3 件中 2 件以上である。
- TS-L1 または TS-L2 のどちらかを検出している。
- 追従済み caller または類似名関数を欠陥として数えた誤検知が 1 件以下である。
- Location/Problem/Breakage の三要素が追跡でき、根拠行が diff または impact-context 内にある。
