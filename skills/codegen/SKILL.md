---
name: codegen
desc: ローカルLLM（gemma4:12b）にコードを実装させる。Claude が計画・仕様策定を行い、gemma4:12b が実装を担当することで出力トークンコストを削減する。Trigger: "/codegen", "codegenで実装", "ローカルLLMで実装"
argument-hint: "<実装したい内容>"
---

# codegen スキル

Claude が実装仕様を策定し、ローカルLLM（`gemma4:12b`）にコードを生成させる。
出力トークンが多いコード生成をローカルに移行し、Claude API の消費を削減する。

Ollama `gemma4:12b` が利用可能な場合はそちらを使い、なければ Haiku にフォールバックする。

## 実行手順

### ステップ 1: タスクと対象ファイルの把握

1. ユーザーの要求を確認する
2. 関連するファイルを Read ツールで読み込み、以下を把握する：
   - 既存コードのスタイル・命名規則・パターン
   - 変更対象のファイルと編集箇所

### ステップ 2: 実装仕様の策定

Claude が以下を含む詳細な実装仕様を作成する：

```
## 実装仕様

### 対象ファイル
<ファイルパス>

### 変更箇所
<変更前のコードスニペット（前後のコンテキスト含む）>

### 要件
<何を実装するか（箇条書き、具体的に）>

### 既存コードのスタイル規約
<インデント・命名規則・型ヒント等>

### 出力形式
変更後のコードブロックのみ出力。説明・コメント追加・コードフェンス不要。
```

### ステップ 3: Ollama 可否チェック

```bash
ollama list 2>/dev/null | grep -q "gemma4:12b"
```

#### Ollama が使える場合

実装仕様を一時ファイル `prompt.txt` に書き出し、gemma4:12b に渡す：

```bash
ollama run gemma4:12b < prompt.txt
rm prompt.txt
```

#### Ollama が使えない場合（Haiku fallback）

実装仕様を `Agent(subagent_type="general-purpose", model="haiku")` に渡し、コードのみ生成させる。

### ステップ 4: コードの適用

1. gemma4:12b（または Haiku）の出力を確認する
2. Edit ツールで対象ファイルに適用する
3. 構文・ロジックの妥当性を確認する（`python -m py_compile` 等）

### ステップ 5: 結果の報告

- どちらのパスを使ったか（Ollama / Haiku fallback）を冒頭に 1 行記載する
- 変更したファイルと内容を簡潔に報告する
