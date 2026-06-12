# 設計・背景

このリポジトリの設計意図や設定の背景をまとめる。

## ツール間の連携

```
会話
 ├─ RTK（PreToolUse）    → Bash 出力を圧縮してトークン消費を削減
 ├─ kizami（SessionEnd） → 会話履歴を長期記憶として保存
 └─ knowledge-rag（MCP） → 過去の知識・lessons-learned を検索
        ↑
        UserPromptSubmit フック（lessons-learned 自動記録）
        SessionEnd フック（sessions → knowledge 昇格）
```

- **RTK** は透過的に動作し、Claudeがコマンドを実行するたびにトークンを節約する
- **kizami** はセッション単位の記憶を担い、過去の会話コンテキストを再利用可能にする
- **knowledge-rag** は構造化された知識を蓄積・検索し、作業品質を向上させる

---

## ローカル LLM モデル選定方針

codegen スキル（Claude → ローカル LLM への委譲）および Obsidian インデックス生成に Ollama を使用する。

| 用途 | モデル | 備考 |
|------|--------|------|
| codegen（コード生成委譲） | `gemma4:12b` | VRAM ~8GB。現状の最適解 |
| knowledge-rag / Obsidian index | `qwen3:8b` | `~/.local/share/knowledge-rag/model` で管理 |

`gemma4:26b` は VRAM 約 17GB を要求するため、現環境では実用的でない。

### llm-checker の推薦について

`llm-checker` コマンドの推薦モデルはセッションごとに変動するため、ドキュメントには記載しない。ドキュメントに記載するモデルは**実績ベース（ollama list で確認済み・動作確認済み）のものに固定**する方針とする。

---

## effortLevel と adaptive thinking の設定

`settings.json` で `effortLevel: "medium"` を設定している。`effortLevel: high` は adaptive thinking と組み合わさると thinking tokens が最大化され、トークン消費量が激増する。`medium` では単純作業で thinking をスキップするため、コスト対効果が高い。

また `CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING=1` を設定し、adaptive thinking を無効化している。これは `effortLevel: high` 時に発生する不具合（[claude-code#23936](https://github.com/anthropics/claude-code/issues/23936)）の回避に加え、使用するモデルや設定レベルに関わらず、思考プロセスの安定化とトークン消費の抑制を確実にするための措置。

---

## Claude Code バージョン固定

**v2.1.100 以降はトークン消費が約 40% 増加するバグ（[#46917](https://github.com/anthropics/claude-code/issues/46917)）が未修正のため、v2.1.98 を推奨する。**

原因はサーバーサイドの User-Agent ルーティング変更。増加分は billing だけでなく実際のコンテキストウィンドウを消費するため、長いセッションほど影響が大きい。

インストール:

```bash
npm install -g @anthropic-ai/claude-code@2.1.98
```

自動アップデートの無効化は `settings.json` の `env` に以下を追加済み:

```json
"DISABLE_AUTOUPDATER": "1"
```

バージョン固定は `setup.sh` には組み込まない（更新を逃す副作用が大きいため、個人判断で実施する）。
