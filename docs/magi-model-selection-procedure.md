# MAGI モデル選定 手順書

MAGI 各ペルソナ（MELCHIOR / BALTHASAR / METATRON / SANDALPHON / LELIEL）に割り当てる
Ollama ローカルモデルを選定・入れ替えるための再利用可能な手順。
2026-07-29〜30 の実地検証（[[project_magi_detection_only_pipeline_2026_07_29]] 等）で
得た教訓を手順として固定化したもの。CASPER は Haiku 技術制約のため対象外。normalizer は
1モデル1ロール原則の対象外（別選定プロセス、[[project_magi_evidence_grounding_fix]] 参照）。

## 0. 前提確認（着手前に必須）

- **現行モデル割当は `skills/<persona>/SKILL.md` の `OLLAMA_MODEL` 行を直接確認する。**
  メモリやこの手順書の記述を鵜呑みにしない。過去に古いメモリの記載のままモデルを
  Codex に伝えてしまい、実際の割当と矛盾した提案を受け取ったミスがある。
- 同様に `OUTPUT_FORMAT_PATH` も確認する。2026-07-31 時点では全5ペルソナが
  `skills/magi-common/references/output-format-v2.md`（DETECTION NOTES 契約）を使用しており、
  `output-format.md`（v1・severity 付き）は本番では使われていない。**この前提が変わっていないか
  毎回確認すること**（後述「6. 既知の注意点」参照）。
- 1モデル1ロール原則（[[feedback_magi_one_model_one_role]]）を踏まえ、候補モデルが他ペルソナと
  ファミリー重複しないか確認する。

## 1. トリガー条件

- 特定ペルソナの recall が実運用（`/magi-hard` 実 PR 通し等）で不十分と判明した場合
- 新しい Ollama モデルを pull した／既存モデルの性能に疑問が生じた場合
- `output-format*.md` や `task-instruction.md` など共通プロンプト契約に変更が入った場合
  （既存割当の再検証が必要）

## 2. Fixture 準備

- ペルソナごとに1本、**本番相当の言語（TypeScript 等）で合成した diff + answer key**を用意する。
  リポジトリ自身の bash スクリプトを fixture にすると実運用（他リポジトリの一般的なアプリコード）
  から乖離するため避ける。
- 既存 fixture: `scripts/tests/fixtures/<persona>-*.diff` / `.answer.md`
  （`metatron-security-flaws-ts` / `sandalphon-deploy-flaws-ts` / `leliel-caller-break-ts` 等）
- precision（誤検知率）専用 fixture: `scripts/tests/fixtures/multi-persona-clean-ts.diff` /
  `.answer.md` / `.impact-context.txt`（2026-07-31追加）。5persona共通で使う、意図的に
  壊れていない diff。期待される true finding は0件で、各persona観点のdecoyを1〜3個ずつ
  含む。Codex敵対的レビュー2巡（module-load時fail-fastによる既存呼び出し元への巻き添え
  破壊を1巡目で検出→lazy validationへ修正→2巡目で通過）を経て「zero real defects」を
  確認済み。対象モデルの誤検知が疑わしい場合はこの fixture でも実行し、decoy 一覧
  （DC-M1〜DC-L1）のどれを誤検知したか個別ログに記録する。

## 3. 候補モデルの選定

- 既存割当モデルとファミリーが被らない候補を優先する（比較の便宜上、選定前の予備検証段階では
  一時的な重複は許容してよいが、最終割当時にファミリー排他を解決する）。
- インストール済みモデル一覧確認は `ollama-run.sh` と同じラッパー経由で行う
  （[[feedback_ollama_access_via_wrapper]]、素の `ollama list` の失敗を「未起動」と誤解しない）。
- 1ペルソナあたり現行 baseline 含め 2〜3 候補で比較する。

## 4. ベンチマーク実行

**本番と同一のプロンプト構成を完全再現することが絶対条件。**
`skills/magi-common/references/execution-steps.md` ステップ2 の構成に合わせる:

- `system.txt` = `task-instruction.md` の内容 + `review-criteria.md` の内容 +
  `$OUTPUT_FORMAT_PATH`（現行は `output-format-v2.md`）の内容をそのまま連結
- `prompt.txt` = `task-base.md` の内容 + `<TASK>` タグで囲んだ fixture diff

実行例:
```bash
cat task-instruction.md review-criteria.md output-format-v2.md > system.txt
{ cat task-base.md; echo; echo "<TASK>"; cat fixture.diff; echo "</TASK>"; } > prompt.txt
OLLAMA_TIMEOUT=900 bash scripts/ollama-run.sh "<候補モデル>" system.txt < prompt.txt
```

- 15分（900秒）を上限とする（`OLLAMA_TIMEOUT=900`）。タイムアウトで打ち切られた場合は
  「指摘なし」と混同せず、別扱い（timeout）として記録する。
- 自動 runner は作らず手動実行する（過去のユーザー方針）。1モデルにつき最低2回実行し、
  安定性（結果のブレ）も見る。

## 5. 採点方法

- `raw_recall` は **内容一致（evidence 相当の記述内容）で判定する。行番号一致は判定基準にしない**
  ——全モデル・全ペルソナで実際の行と数行〜10行程度ずれることが実測済み。
- 以下を個別に記録する:
  - 捏造（事実と逆の主張。例: 「フォールバックが無い」と主張しているが実際はある）
  - decoy 誤検知（正しく追従済みの箇所を壊れていると誤判定）
  - 重複／同一見出しの反復
  - `"No findings."` 等の契約違反混入
- 結果表フォーマット: `ペルソナ | モデル | raw_recall | 主な問題 | 実行時間 | 判定`

## 6. 採否判断基準

- 最低ライン: **現行モデル以上の raw_recall、かつ捏造ゼロ**
- 1モデル1ロール原則を破らない
- 検出（ペルソナ）と監査（Codex）が同一モデル系統にならないようにする
  （common-mode failure 回避、METATRON の教訓 [[project_magi_metatron_codex_357]]）
- 際どい場合は Codex に結果を提示して合議する。伝える際は **メモリではなく
  `skills/*/SKILL.md` の実ファイルを見せて正確な割当を伝える**（0番の教訓の再発防止）

## 7. 本番反映

1. `skills/<persona>/SKILL.md` の `OLLAMA_MODEL` 行を更新
2. 単体ペルソナ実行または `/magi-fast` で疎通確認
3. `/commit` スキルでコミット（`git commit` を直接叩かない）、必要なら PR 化
4. PR マージ後、`CLAUDE.local.md` の方針に従い `~/.claude/` へ cp で反映
   （`~/.claude/` の既存ファイルを直接編集しない）

## 8. 既知の注意点（過去の教訓）

- **出力契約（v1 severity 形式 ↔ v2 DETECTION NOTES 契約）が変わるとベンチマーク結果は転移しない。**
  2026-07-29 の検証では v2 で明確だった優劣が v1 では逆転・消失した。契約が変わった場合は
  同一 fixture で必ず再検証すること。2026-07-31 時点では本番は v2 に統一済みだが、
  将来 `output-format*.md` が再度分岐した場合は要注意。
- **few-shot anchoring**: `task-instruction.md` の Example Output の文言・件数をモデルが
  そのまま模倣する現象がある。「模倣しないように」という注記だけでは治らないモデルもある
  （`llama3.1:8b` で確認済み）。効果が出ない場合は Example 自体の書き換えを検討する
  （ただし6ペルソナ共通ファイルより影響範囲が大きい変更になる）。
- 精度（false positive）fixture が無いため、誤検知の多寡は Codex 監査側の濾過に依存する前提。
  ただし明らかに誤検知が多いモデルは選定段階で除外する。

関連: [[project_magi_recall_first_direction]] [[project_magi_detection_only_pipeline_2026_07_29]]
[[project_magi_evidence_grounding_fix]] [[feedback_magi_one_model_one_role]]
[[feedback_codex_role_division]] [[feedback_ollama_access_via_wrapper]]
