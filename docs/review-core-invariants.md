# Review core invariants

Mining baseline SHA: 557f90b247c1821ad482e00fa26ce72de14bf7ad

## INV 台帳

| INV | source | 期待挙動 | test_id |
|---|---|---|---|
| INV-001 | Issue #409 / Issue #410 / MC-001; mining@557f90b247c1821ad482e00fa26ce72de14bf7ad | 同一 review revision への外部書き込みは高々1回で、別主体が作成した印は投稿済み判定に使われない | M2-FX-001 |
| INV-002 | Issue #411 / MC-002; mining@557f90b247c1821ad482e00fa26ce72de14bf7ad | 同一 target の同時 run は1本だけが実行権を持ち、他は無期限に待たず終端する | M2-FX-002 |
| INV-003 | Issue #411 / MC-003 / mining@b8721a5; mining@557f90b247c1821ad482e00fa26ce72de14bf7ad | 異なる target の外部 executor も同時に高々1本で、各 run の終端結果が失われない | M2-FX-003 |
| INV-004 | C1 / MC-004; mining@557f90b247c1821ad482e00fa26ce72de14bf7ad | owner 消失や stale ownership があっても待機は有界で、無限待機しない | M2-FX-004 |
| INV-005 | C2 / MC-005; mining@557f90b247c1821ad482e00fa26ce72de14bf7ad | 3,200行・8チャンクを境界として、超過入力を無界処理または成功扱いにしない | M2-FX-005 |
| INV-006 | C3–C6 / MC-006–MC-009; mining@557f90b247c1821ad482e00fa26ce72de14bf7ad | ローカル LLM 180秒 / 外部 API 60秒 / 補助 executor 900秒 / Codex 600秒 の各上限で終端し、timeout を成功扱いせず残留資源を残さない | M2-FX-006 |
| INV-007 | ERR-20260713-002 / ERR-20260717-001 / MC-010; mining@557f90b247c1821ad482e00fa26ce72de14bf7ad | completion marker の有無だけに依存せず、情報不足は非完了として扱う | M2-FX-007 |
| INV-008 | 構造的欠陥6 / MC-011 / mining@f11852d; mining@557f90b247c1821ad482e00fa26ce72de14bf7ad | 空・不正・一貫しない構造化出力は共通契約で拒否し、成功や投稿へ進めない | M2-FX-008 |
| INV-009 | 構造的欠陥7 / MC-012; mining@557f90b247c1821ad482e00fa26ce72de14bf7ad | 宣言された全 job に終端結果を残し、無音 skip を成功扱いにしない | M2-FX-009 |
| INV-010 | MC-013 / mining@f11852d; mining@557f90b247c1821ad482e00fa26ce72de14bf7ad | `line:0` だけを理由に finding を捨てず、観測可能な結果として保持する | M2-FX-010 |
| INV-011 | MC-014 / mining@b289e62 / mining@fdf3b70; mining@557f90b247c1821ad482e00fa26ce72de14bf7ad | 外部書き込み直前に head を再確認し、変化した旧 revision を書き込まない | M2-FX-011 |
| INV-012 | MC-015 / mining@fdf3b70; mining@557f90b247c1821ad482e00fa26ce72de14bf7ad | 投稿開始後の成否不明を `posted_unknown` 相当で保持し、自動再投稿しない | M2-FX-012 |
| INV-013 | MC-016 / mining@b8721a5 / mining@83a6557 / mining@070aec4; mining@557f90b247c1821ad482e00fa26ce72de14bf7ad | 親終了後に active な子の処理・排他資源・一時資源を残さず、次 run を塞がない | M2-FX-013 |
| INV-014 | Issue #411 / MC-017 / mining@fdf3b70 / mining@070aec4; mining@557f90b247c1821ad482e00fa26ce72de14bf7ad | lease 期限切れ後は新 owner だけを有効とし、旧 owner の遅い操作を fencing する | M2-FX-014 |
| INV-015 | MC-018 / mining@f11852d / mining@043d009; mining@557f90b247c1821ad482e00fa26ce72de14bf7ad | exit 0 だけで成功とせず、不正・空・過大出力を有界に拒否する | M2-FX-015 |
| INV-016 | MC-019 / mining@83a6557; mining@557f90b247c1821ad482e00fa26ce72de14bf7ad | executor の利用不能を `unavailable` 相当で明示し、自動 fallback や投稿へ進めない | M2-FX-016 |
| INV-017 | MC-020 / mining@c819dba / mining@6088cc3; mining@557f90b247c1821ad482e00fa26ce72de14bf7ad | `publish=none` では外部書き込みを発生させず、投稿要求時だけ外部書き込みを行う | M2-FX-017 |
| INV-018 | MC-021 / mining@83a6557 / mining@fdf3b70; mining@557f90b247c1821ad482e00fa26ce72de14bf7ad | target の同一性・所有権を示す入力が欠落・不一致・破損しているとき、外部書き込み前に明示的な失敗または評価不能で終端し、成功や投稿へ進まない | M2-FX-018 |
| INV-019 | 構造的欠陥1 / 構造的欠陥9 / MC-022; mining@557f90b247c1821ad482e00fa26ce72de14bf7ad | source と runtime の実行 closure の不一致を検出し、完全一致時だけ全入口の到達可能性を観測する | M2-FX-019 |

## Coverage / waiver

### Coverage

| 対象 | 対応 fixture | 状態 |
|---|---|---|
| 構造的欠陥1 | FX-M2-019 | runtime reachability と drift 検出で対応 |
| 構造的欠陥2 | WAIVER-M2-001 | M9 の到達性監査で対応 |
| 構造的欠陥3 | WAIVER-M2-002 | M9 の到達性監査で対応 |
| 構造的欠陥4 | WAIVER-M2-003 | M8–M9 の責務監査で対応 |
| 構造的欠陥5 | WAIVER-M2-004 | M5 の機械契約監査で対応 |
| 構造的欠陥6 | FX-M2-008 | 構造化出力の共通契約で対応 |
| 構造的欠陥7 | FX-M2-009 | required job の終端結果で対応 |
| 構造的欠陥8 | WAIVER-M2-005 | M9–M10 の scope audit で対応 |
| 構造的欠陥9 | FX-M2-019 | runtime drift 検出で対応 |
| Issue #409 | FX-M2-001 | 投稿冪等性で対応 |
| Issue #410 | FX-M2-001 | 投稿冪等性で対応 |
| Issue #411 | FX-M2-002 / FX-M2-003 / FX-M2-014 | 同一 target、共有 executor、lease fencing で対応 |
| C1 | FX-M2-004 | 有界待機で対応 |
| C2 | FX-M2-005 | 大きさ上限で対応 |
| C3 | FX-M2-006 | timeout 境界で対応 |
| C4 | FX-M2-006 | timeout 境界で対応 |
| C5 | FX-M2-006 | timeout 境界で対応 |
| C6 | FX-M2-006 | timeout 境界で対応 |
| ERR-20260713-002 | FX-M2-007 | completion marker 欠落で対応 |
| ERR-20260717-001 | FX-M2-007 | completion marker 欠落で対応 |
| `line:0` | FX-M2-010 | line:0 を保持する契約で対応 |

### Waiver

#### WAIVER-M2-001 — MC-023 / 構造的欠陥2

- 対象: 未配備層を検証する最大テストが実行されない層を green として扱う問題。
- M2 で fixture 化しない理由: 実行入口と検証対象の到達性を照合する静的な問題であり、宣言的な runtime fixture だけでは判定できないため。
- 対応 milestone: M9。
- 完了条件: 全テストが active entrypoint と対応付けられ、未配備層の結果が運用上の coverage から除外される。
- 未 triage でないこと: MC-023 として M9 の構造検査へ割り当て済みであり、未 triage ではない。

#### WAIVER-M2-002 — MC-024 / 構造的欠陥3

- 対象: 実行経路外の大容量資産が実行 closure と誤認される問題。
- M2 で fixture 化しない理由: 資産の到達性と容量の静的な検査が必要で、事故 replay の宣言だけでは判定できないため。
- 対応 milestone: M9。
- 完了条件: active closure に未参照資産がなく、残す非実行資産は別 scope として記録される。
- 未 triage でないこと: MC-024 として M9 の到達性検査へ割り当て済みであり、未 triage ではない。

#### WAIVER-M2-003 — MC-025 / 構造的欠陥4

- 対象: 同じ phase 順序を持つ重複した Flow 実装の drift。
- M2 で fixture 化しない理由: 2つの実装の責務と参照関係を構造的に比較する必要があり、事故 replay だけでは閉じられないため。
- 対応 milestone: M8–M9。
- 完了条件: phase 遷移、checkpoint、fix loop の正本が1つに定まり、重複手順が存在しない。
- 未 triage でないこと: MC-025 として M8–M9 の責務監査へ割り当て済みであり、未 triage ではない。

#### WAIVER-M2-004 — MC-026 / 構造的欠陥5

- 対象: 表示用の見出し変更が機械契約の抽出結果へ影響する問題。
- M2 で fixture 化しない理由: 表示内容の判定ではなく、構造 metadata と機械契約の依存関係を検査する課題であり、M2 の意味内容 fixture に含めないため。
- 対応 milestone: M5。
- 完了条件: 機械契約が表示用見出し名に依存せず、metadata 欠落が暗黙の fallback にならないことを構造検査で確認する。
- 未 triage でないこと: MC-026 として M5 の機械契約監査へ割り当て済みであり、未 triage ではない。

#### WAIVER-M2-005 — MC-027 / 構造的欠陥8

- 対象: Flow/Review 外の補助分析が認証未設定で無音 skip され、完了判定へ混入する問題。
- M2 で fixture 化しない理由: hooks 領域は D1 の対象外であり、M2 で修正または runtime fixture 化を行わないため。
- 対応 milestone: M9–M10。
- 完了条件: 新コアが補助分析の可否を review/flow の完了条件や判定へ混入させず、補助分析 unavailable の場合も review/flow の終端が明示的に観測できる。
- 未 triage でないこと: MC-027 として M9–M10 の scope audit と smoke 検査へ割り当て済みであり、未 triage ではない。

## Legacy baseline evidence

固定 SHA は全行で同一である。実行は `git archive` で展開した固定 SHA の tracked 内容を隔離環境で行った（`git worktree add` は `.git/worktrees` が read-only のため使えなかった）。

| test path | 固定 SHA | 結果 | 実行環境 | 失敗または skip の理由 |
|---|---|---|---|---|
| `test-advisor-run.sh` | `557f90b247c1821ad482e00fa26ce72de14bf7ad` | PASS (exit 0) | HOME/XDG_RUNTIME_DIR/TMPDIR 隔離・shim 4種・timeout 300 | — |
| `test-casper-engine-contract.sh` | `557f90b247c1821ad482e00fa26ce72de14bf7ad` | PASS (exit 0) | HOME/XDG_RUNTIME_DIR/TMPDIR 隔離・shim 4種・timeout 300 | — |
| `test-codex-review-audit.sh` | `557f90b247c1821ad482e00fa26ce72de14bf7ad` | PASS (exit 0) | HOME/XDG_RUNTIME_DIR/TMPDIR 隔離・shim 4種・timeout 300 | — |
| `test-codex-review-merge.sh` | `557f90b247c1821ad482e00fa26ce72de14bf7ad` | PASS (exit 0) | HOME/XDG_RUNTIME_DIR/TMPDIR 隔離・shim 4種・timeout 300 | — |
| `test-function-calling.sh` | `557f90b247c1821ad482e00fa26ce72de14bf7ad` | SKIP (exit 0) | HOME/XDG_RUNTIME_DIR/TMPDIR 隔離・shim 4種・timeout 300 | テスト自身が Ollama 未起動として SKIP（shim 呼び出しなし） |
| `test-knowledge-rag-local.sh` | `557f90b247c1821ad482e00fa26ce72de14bf7ad` | PASS (exit 0) | HOME/XDG_RUNTIME_DIR/TMPDIR 隔離・shim 4種・timeout 300 | — |
| `test-magi-diff-filter.sh` | `557f90b247c1821ad482e00fa26ce72de14bf7ad` | PASS (exit 0) | HOME/XDG_RUNTIME_DIR/TMPDIR 隔離・shim 4種・timeout 300 | — |
| `test-magi-format.sh` | `557f90b247c1821ad482e00fa26ce72de14bf7ad` | SKIP (exit 0) | HOME/XDG_RUNTIME_DIR/TMPDIR 隔離・shim 4種・timeout 300 | テスト自身が Ollama 未起動として SKIP（shim 呼び出しなし） |
| `test-magi-ground-findings.sh` | `557f90b247c1821ad482e00fa26ce72de14bf7ad` | PASS (exit 0) | HOME/XDG_RUNTIME_DIR/TMPDIR 隔離・shim 4種・timeout 300 | — |
| `test-ollama-run-options.sh` | `557f90b247c1821ad482e00fa26ce72de14bf7ad` | PASS (exit 0) | HOME/XDG_RUNTIME_DIR/TMPDIR 隔離・shim 4種・timeout 300 | — |
| `test-review-adjudicate-findings.sh` | `557f90b247c1821ad482e00fa26ce72de14bf7ad` | PASS (exit 0) | HOME/XDG_RUNTIME_DIR/TMPDIR 隔離・shim 4種・timeout 300 | — |
| `test-review-dedup-findings.sh` | `557f90b247c1821ad482e00fa26ce72de14bf7ad` | PASS (exit 0) | HOME/XDG_RUNTIME_DIR/TMPDIR 隔離・shim 4種・timeout 300 | — |
| `test-review-dispatch-envelope.sh` | `557f90b247c1821ad482e00fa26ce72de14bf7ad` | PASS (exit 0) | HOME/XDG_RUNTIME_DIR/TMPDIR 隔離・shim 4種・timeout 300 | — |
| `test-review-dispatch-wiring.sh` | `557f90b247c1821ad482e00fa26ce72de14bf7ad` | PASS (exit 0) | HOME/XDG_RUNTIME_DIR/TMPDIR 隔離・shim 4種・timeout 300 | — |
| `test-review-findings-artifact.sh` | `557f90b247c1821ad482e00fa26ce72de14bf7ad` | PASS (exit 0) | HOME/XDG_RUNTIME_DIR/TMPDIR 隔離・shim 4種・timeout 300 | — |
| `test-review-post-contract.sh` | `557f90b247c1821ad482e00fa26ce72de14bf7ad` | PASS (exit 0) | HOME/XDG_RUNTIME_DIR/TMPDIR 隔離・shim 4種・timeout 300 | — |
| `test-codex-broker-run.sh` | `557f90b247c1821ad482e00fa26ce72de14bf7ad` | PASS (exit 0) | HOME/XDG_RUNTIME_DIR/TMPDIR 隔離・shim 4種・timeout 300 | — |
| `test-execution-budget.sh` | `557f90b247c1821ad482e00fa26ce72de14bf7ad` | PASS (exit 0) | HOME/XDG_RUNTIME_DIR/TMPDIR 隔離・shim 4種・timeout 300 | — |
| `test-resource-lock-wiring.sh` | `557f90b247c1821ad482e00fa26ce72de14bf7ad` | PASS (exit 0) | HOME/XDG_RUNTIME_DIR/TMPDIR 隔離・shim 4種・timeout 300 | — |
| `test-review-dispatch-managed-e2e.sh` | `557f90b247c1821ad482e00fa26ce72de14bf7ad` | PASS (exit 0) | HOME/XDG_RUNTIME_DIR/TMPDIR 隔離・shim 4種・timeout 300 | — |
| `test-review-dispatch-state-process-isolation.sh` | `557f90b247c1821ad482e00fa26ce72de14bf7ad` | PASS (exit 0) | HOME/XDG_RUNTIME_DIR/TMPDIR 隔離・shim 4種・timeout 300 | 当初は集計行（FAIL=0）が出力に無いため機械規則で FAIL と判定したが、ログ全文で assertion 2件とも PASS・exit 0 を確認し PASS に訂正（このテストは集計行を出力しない） |
| `test-review-fast-no-post.sh` | `557f90b247c1821ad482e00fa26ce72de14bf7ad` | PASS (exit 0) | HOME/XDG_RUNTIME_DIR/TMPDIR 隔離・shim 4種・timeout 300 | — |
| `test-review-post-lock.sh` | `557f90b247c1821ad482e00fa26ce72de14bf7ad` | PASS (exit 0) | HOME/XDG_RUNTIME_DIR/TMPDIR 隔離・shim 4種・timeout 300 | — |
| `test-review-singleflight-fencing.sh` | `557f90b247c1821ad482e00fa26ce72de14bf7ad` | PASS (exit 0) | HOME/XDG_RUNTIME_DIR/TMPDIR 隔離・shim 4種・timeout 300 | — |
| `test-review-singleflight.sh` | `557f90b247c1821ad482e00fa26ce72de14bf7ad` | PASS (exit 0) | HOME/XDG_RUNTIME_DIR/TMPDIR 隔離・shim 4種・timeout 300 | — |

集計: PASS 23 / FAIL 0 / SKIP 2 / UNAVAILABLE 0（計25件）。SKIP 2件（`test-function-calling.sh` / `test-magi-format.sh`）は Ollama 未起動によるもので green とみなさない。両テストは MAGI（ollama）系で D6（v1 は unavailable stub）の範囲外のため、対象外の理由付きで waiver とする（Claude 裁定）。

## 規律

今後の control-plane bug fix には必ず fixture を追加する。
