# Specification Draft: Core 01

## 仕様候補

- setup.sh --verify または setup/900-verify.sh のチェック項目
- Codex CLI 自動インストールとログイン未完了時の扱い
- Ollama未起動時の起動・常駐化・再実行案内
- スキル要求モデルとpull対象モデルの一致条件
- README上の手動ステップ導線

## 境界条件

- この仕様候補は、分類成果物の「仕様化の観点」から起こした論点であり、まだ確定仕様ではない。
- 関連Fable項目 02, 05, 08, 09, 10, 12 のうち、他の核問題にも現れる項目は重複として扱う。
- 実装確認メモに基づく現状は次の通り。

- setup/850-codex.sh は Codex CLI の確認のみで自動インストールしない
- setup/401-ollama.sh はOllamaインストールまででサーバー起動しない
- setup/800-ollama-models.sh は ollama list 失敗時に return 0 でモデル取得をスキップする
- settings.json は hooks/error-detector.sh を参照するが hooks/ に実体がない
- setup.sh に --verify / 900-verify はない

## fail / warn / info の判定が必要なもの

- 目的達成に必須で、欠けると主要機能が動かないものは fail 候補。
- 手動認証、環境差、任意機能、段階導入対象は warn / info 候補。
- 具体的な判定境界は requirements.md の人間確認事項を解消してから決める。

## 未確定事項

- Codex未認証を warn にするか info にするか
- 大容量モデルpullをデフォルト必須にするか
- verify の fail / warn 境界