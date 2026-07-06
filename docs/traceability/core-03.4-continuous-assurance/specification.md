# Specification Draft: Core 06

## 仕様候補

- CIの bash -n、shellcheck、既存テスト、モデル突合、hooks参照、禁止パスgrep
- verifyの到達性、インストール状態、モデル存在、hooks配備、キュー滞留
- README/SKILLS/DESIGN更新対象と同時更新ルール
- 手動ステップと環境変数一覧の集約

## 境界条件

- この仕様候補は、分類成果物の「仕様化の観点」から起こした論点であり、まだ確定仕様ではない。
- 関連Fable項目 03, 07, 10, 11, 12 のうち、他の核問題にも現れる項目は重複として扱う。
- 実装確認メモに基づく現状は次の通り。

- .github/ は存在しない
- templates/security/github-workflows/security-scan.yml は配布用テンプレート
- scripts/test-*.sh はあるが自動実行CIがない
- setup.sh に --verify はなく setup/900-verify.sh もない
- git状態では audit ディレクトリも未追跡

## fail / warn / info の判定が必要なもの

- 目的達成に必須で、欠けると主要機能が動かないものは fail 候補。
- 手動認証、環境差、任意機能、段階導入対象は warn / info 候補。
- 具体的な判定境界は requirements.md の人間確認事項を解消してから決める。

## 未確定事項

- shellcheck厳格度
- smoke testでネットワーク・Ollama・pCloud依存をどこまで扱うか
- CI fail と verify warn の境界
- auditディレクトリを追跡対象にするか