name: learning-aggregator
desc: .learnings/ の全エントリをクロスセッション分析し、昇格候補パターンをランク付きで出力する（外側ループの inspect ステップ）。定期実行（週次・大きなタスクの前・重要プロジェクトの開始時）または手動呼び出し。Trigger: "/learning-aggregator", "learning-aggregator", "学習を集計", "パターン分析", "学習を振り返る"
argument-hint: "<--deep でセッション全体の深層分析を追加（省略可）>"

# Learning Aggregator スキル

蓄積された `.learnings/` ファイルを読み込み、パターンを見つけ、昇格候補のランク付きリストを生成する。

`self-improvement` / `self-healing` との関係:
- **self-improvement / self-healing**: 個別セッションでエントリを蓄積（内側ループ）
- **learning-aggregator（このスキル）**: 蓄積されたエントリを定期的に集計・分析（外側ループの inspect ステップ）

**Readonly**: `.learnings/` ファイルは読むだけ。変更・昇格の適用は行わない（それは harness-updater が担当）。

## ステップ 1: 全学習ファイルの読み込み

以下のファイルをすべて読み込む（存在しないファイルはスキップ）:

```
.learnings/LEARNINGS.md        # LRN エントリ
.learnings/ERRORS.md           # ERR エントリ
.learnings/FEATURE_REQUESTS.md # FEAT エントリ
.learnings/HEALS.md            # HEAL エントリ
```

## ステップ 2: グループ化と集計

Pattern-Key でエントリをグループ化し、以下を計算する:
- `total_recurrence`: グループ内の Recurrence-Count の合計
- `distinct_tasks`: 異なるタスクで発生した数（Source フィールドから推定）
- `days_since_first`: 最古のエントリからの日数
- `entry_types`: LRN / ERR / FEAT / HEAL の内訳

## ステップ 3: ランク付けと分類

昇格閾値（self-improvement と共通）:
- `total_recurrence >= 3`
- `distinct_tasks >= 2`
- 30日以内

ギャップ種別の分類:
| 種別 | 判断基準 |
|------|---------|
| knowledge gap | LRN エントリが主体。知識・手順の不足 |
| tool gap | FEAT エントリが主体。使いたいツール・スクリプトが未存在 |
| skill gap | ERR/HEAL エントリが主体。繰り返す操作ミス |
| ambiguity | 複数のエントリが矛盾する対応を記録 |
| reasoning failure | 根本原因が誤った前提に基づくエラー |

## ステップ 4: Gap Report の出力

```
## Learning Aggregator — Gap Report

**分析対象**: .learnings/ （YYYYMMDD 時点）
**エントリ総数**: N 件

---

### 昇格準備完了（全閾値クリア）

1. **[Pattern-Key]** — [ギャップ種別]
   - Recurrence: X / Distinct tasks: Y / 期間: Z日
   - 代表エントリ: [ERR-YYYYMMDD-XXX]
   - 推奨昇格先: [CLAUDE.md ルール / settings.json / 専用スクリプト]

---

### 昇格近し（閾値に近い）

2. **[Pattern-Key]** — [ギャップ種別]
   - Recurrence: X / Distinct tasks: Y（あと1タスク）
   ...

---

### 注目パターン（閾値未達だが重要）

3. **[Pattern-Key]** — [理由]
   ...

---

## 次のステップ

昇格候補を CLAUDE.md / settings.json に反映するには harness-updater を実行してください。
```

## ステップ 5: Handoff

昇格準備完了パターンがある場合、ユーザーに `harness-updater` の実行を提案する。

## --deep モード（オプション）

通常モードは `.learnings/` の明示的なエントリのみを対象とする。
`--deep` を指定した場合、セッション全体のトランスクリプトからも暗黙のパターンを検出する:
- リトライループ（同じコマンドを複数回試行）
- ユーザーによる暗黙の訂正
- 回避されたテスト失敗
- トークン・時間の異常値
