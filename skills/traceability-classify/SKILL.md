---
name: traceability-classify
description: Step 1 問題の分解・核問題分類。監査結果・目的・リポジトリ情報から問題を核問題単位に分解し docs/planning/ に分類ドキュメントを出力する。コード変更はしない。Trigger: "/traceability-classify", "核問題に分類", "問題を分解して"
argument-hint: "<入力（監査結果パス・問題の説明など）>"
---

# TRACEABILITY-CLASSIFY（Step 1: 問題の分解・核問題分類）

核問題の切り方は下流全工程の照準を決める高負荷ステップだが、メインセッションの
モデル切替はコンテキスト再処理で 5h ウィンドウを大きく消費するため行わない。
**高負荷な統合だけを Phase B として小さく外出しする**3フェーズ構成とし、
メインセッションは Sonnet のままでよい。

## 手順

1. `skills/traceability-common/references/rules.md`（repo 内。なければ `~/.claude/skills/traceability-common/references/rules.md`） を Read し、入力を特定する
2. **Phase A — 候補抽出（メインセッション・機械的）**
   入力文書ごとに問題候補を全列挙した候補表を作る:
   `| 候補ID | 出典 | 1行要約 | 根拠（実装/文書/推測） |`
   - 網羅が目的。統合・優先度判断はしない
   - **ドキュメントではなく実装・git 履歴を現状の正として読む**。推測は「推測:」明記
3. **Phase B — 統合案の生成（外出し・低クォータ）**
   候補表**のみ**を渡して核問題グルーピング案を得る（生文書は渡さない）。優先順:
   - a. **Codex**（Claude クォータ消費ゼロ）: `codex-audit.md` と同じ companion 呼び出しで
     read-only 実行。依頼内容: 「候補を核問題単位に統合し、各核問題に関連候補ID・関連目的・
     分類（必須/推奨/将来拡張/要確認）・confidence・統合理由を付けよ」
   - b. Codex 不可: `Agent(subagent_type="general-purpose", model="opus")` に候補表のみ渡す
   - c. 両方不可: メインセッションで実施（この場合 Phase C の grill-me を必須とする）
4. **Phase C — 検証（メインセッション + 人間）**
   - 統合案を提示し、`/grill-me` で深掘り確認: 切り方の粒度 / 核問題の境界 / 横断関係 / 優先度
   - **機械的網羅チェック**: 候補表の全 ID が少なくとも1つの核問題の関連項目に現れることを
     突合する。欠落があれば Phase B に差し戻す
5. `docs/planning/<入力名>-traceability-classification.md` に出力する:
   概要（入力・読み取り根拠・**Phase B 実施者の記録**）→ 核問題一覧表 → 詳細 → 重複・横断関係
6. AskUserQuestion: 「承認（Step 2 へ）/ 修正 / 中断」

## 完了条件

- 全候補 ID が核問題に紐づいている（機械的突合で検証済み）
- 各核問題に関連項目・関連目的・分類・confidence が付き、推測と事実が分離されている
- Phase B の実施者（Codex / Opus subagent / main）が文書に記録されている
- **コード変更をしていない**

再実行時は既存 core-XX の番号を変えず差分更新とする。
