# Traceability Audit: Core 03.2 — hooks / knowledge-distill / 知識ストアの二重化・欠落・密結合

> ステータス: verified（2026-07-19 人間承認済み。REQ-03.2-03 の knowledge-rag 登録 mount 非依存性は blocked=#326 として明記の上 verified）
> 実施日: 2026-07-19（Step 9）
> 実施者: Claude（機械的突合 + 意味的チェック）+ Codex（gpt-5.6-luna、read-only、二次確認）

## 機械的チェック（表突合）

### PROB → REQ

| PROB ID | 対応 REQ | 判定 |
|---|---|---|
| PROB-03.2-01 | REQ-03.2-01 | OK |
| PROB-03.2-02 | REQ-03.2-02 | OK |
| PROB-03.2-03 | （設計事項・独立 REQ なし、requirements.md に明記） | OK（意図的） |
| PROB-03.2-04 | REQ-03.2-03 | OK |
| PROB-03.2-05 | REQ-03.2-04 | OK |
| PROB-03.2-06 | （audit 対象・独立 REQ なし、requirements.md に明記） | OK（意図的。本監査で確認済み、下記参照） |

### REQ → SPEC → IMPL → TEST

| REQ ID | SPEC ID | IMPL ID（PR） | TEST ID | 判定 |
|---|---|---|---|---|
| REQ-03.2-01 | SPEC-03.2-01 | IMPL-03.2-01（PR-A #313, merged） | TEST-03.2-01（9 PASS） | OK |
| REQ-03.2-02 | SPEC-03.2-02 | IMPL-03.2-01（PR-A #313, merged） | TEST-03.2-02（2 PASS） | OK |
| REQ-03.2-03 | SPEC-03.2-03 | IMPL-03.2-02（PR-B #317, merged） | TEST-03.2-03（13 PASS。一部未テスト → A-001） | 部分未達（blocked） |
| REQ-03.2-03 | SPEC-03.2-05 | IMPL-03.2-04, 05（PR-D #324, merged） | TEST-03.2-05（12 PASS） | OK |
| REQ-03.2-04 | SPEC-03.2-04 | IMPL-03.2-03（PR-C #322, merged） | TEST-03.2-04（8 PASS） | OK |

全 REQ に対応 SPEC あり。全 SPEC に対応 IMPL・TEST あり（未対応理由付き含む）。orphan（派生元のない map 行）なし。

### 実装参照の実在確認（git/gh で検証）

| PR | 状態 | 確認内容 |
|---|---|---|
| #313 | MERGED (2026-07-16) | `setup/410-hooks-distill.sh`, `setup/412-hooks-queue.sh` に SessionStart/SessionEnd 登録ロジック実在確認 |
| #317 | MERGED (2026-07-16) | `hooks/knowledge-distill.sh` の `OUTPUT_DIR="$HOME/.local/share/knowledge-rag/sessions"`・`mountpoint` 参照なし確認 |
| #322 | MERGED (2026-07-16) | `hooks/error-detector.sh`（git ls-files で実在）・`setup/413-hooks-error-detector.sh` 実在確認 |
| #324 | MERGED (2026-07-19) | `hooks/lessons-learned-distill.sh` に pCloud 直書きなし・`CLAUDE.md` の lessons-learned 記録手順変更を確認 |
| #327 | MERGED (2026-07-19) | Step 7 design-review 記録 |
| #328 | MERGED (2026-07-19) | Step 8 test-plan 記録 |

すべて実在・merge 済み。ドキュメント記載と実装が一致。

### orphan implementation チェック（PROB-03.2-06: compact 強化フック群）

`setup/` 配下に compact-prep / compact-recovery 関連の登録スクリプトなし（`grep -rn "compact-prep\|compact-recovery\|compact-hardening" setup/` で 0 件）。
README.md の「外部先行変更（2026-07-06 記録）」に派生元宣言が既にあり、本 core の setup モジュールには含まれない外部導入として扱われている。
**orphan implementation ではない**（派生元記録が存在するため誤検知しない）。

### orphan implementation チェック（PR #249 クローズ済み構想）

README.md の「外部先行変更（2026-07-16 記録）」に、重複構想 PR #249 のクローズ経緯が記録済み。
本監査でも該当実装が repo に残っていないことを確認。orphan implementation なし。

### ライブ環境での実挙動確認（追加確認）

- `~/.local/share/knowledge-rag/sessions/` に蒸留済み `.md` が複数存在（実際に記録層がローカル完結で動作している証跡）
- `~/.local/share/knowledge-rag/lessons-learned/` にも手動保存ファイルが存在
- `~/.claude/hooks/queue/knowledge-distill/*.json` は現在 0 件（キュー滞留なし）
- `~/.claude/hooks/queue/dead-letter/` に 29 件存在するが、大半は 2026-07-08〜07-10（PR-B/D 以前）の古い項目。PR-B merge（07-16）後の新規分は `dead_letter_reason: "transcript_not_found"` であり、本 core の SPEC-03.2-03（pCloud mount 依存の drain 条件）とは無関係の別失敗モード（→ A-003、スコープ外）

## 意味的チェック・指摘事項

Codex（read-only、二次確認）による valid / false_positive 判定を付与。

| ID | 重大度 | 内容 | Codex 判定 | 対応 |
|---|---|---|---|---|
| A-001 | 情報 | REQ-03.2-03 の受け入れ条件「rclone mount なしで knowledge-rag 登録・自動昇格が完走する」が未達。design-review.md（Step 7）で HIGH 検出済み、[#326](https://github.com/YuushiOnozawa/Claude-StartUp/issues/326) に別トラック化・test-plan.md でも blocked と一貫して記録済み | **valid**（既知・一貫して記録済みと確認） | 対応不要（#326 で追跡継続。verified 判定への影響は下記参照） |
| A-002 | 低 | implementation-plan.md の IMPL-03.2-03 表に「setup.sh へ 413 source 追加」という当初計画の記載が残り、PR-C 完了注記の訂正（glob 方式のため不要）と表面上不整合だった | **valid** | **本監査で修正済み**（表の内容欄を実態に合わせて更新） |
| A-003 | 情報・対象外 | 実環境の dead-letter キューに `transcript_not_found` 理由の項目が複数存在するが、SPEC-03.2-03 が扱う「pCloud マウント依存の drain 条件」とは別の失敗モードであり、本 core の REQ/SPEC のいずれにも対応しない | **false_positive**（スコープ外と確認） | 対応不要（本 core の対象外。将来的に別課題として起票するかは任意） |

## 過剰実装

なし（実装項目はすべて SPEC に対応関係を持つ）。

## 未確認事項

- specification.md の未確定事項 #3（`pcloud-sync.sh` の実行タイミング/cadence）は core-01 側で確定予定。本 core の SPEC-03.2-03/05 は pcloud-sync.sh への委任を明記するのみで、cadence 自体は本 core のスコープ外
- 未確定事項 #4（documents_dir 依存）は #326 で追跡中（A-001 と同一事象）

## 最終判定（verified 可否）

- REQ-03.2-01, REQ-03.2-02, REQ-03.2-04: **完全達成**。対応 SPEC・IMPL・TEST がすべて揃い PASS
- REQ-03.2-03: **部分達成**。「記録層の pCloud 非依存化」（蒸留・ローカル保存）は完全に達成・テスト済み。「knowledge-rag 登録・自動昇格の mount 非依存完走」は #326 で blocked のまま残る
- A-002 の文書不整合は本監査で修正済み
- A-003 はスコープ外と確認済み、対応不要

**推奨判定**: core-03.2 の hooks 側スコープ（REQ-03.2-01/02/04 全部、REQ-03.2-03 の記録層部分）は **verified** とし、
REQ-03.2-03 の残指摘（knowledge-rag 登録の mount 非依存性）は **blocked（#326 で追跡）** として明記した上で
verified とすることを提案する（隠さず残指摘として残す）。
