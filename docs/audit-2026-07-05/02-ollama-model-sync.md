# 02. setup/800-ollama-models.sh とスキルのモデル割当不整合

種別: 修正対応 / 深刻度: 高

## 現状

Issue #252 / #254（Codex 移行・MAGI モデル格上げ）はスキル側には反映済みだが、
`setup/800-ollama-models.sh` が追随していない。新規環境にワンライナー展開すると
**スキルが要求するモデルが pull されず、使わないモデルが pull される**。

| ペルソナ / 用途 | スキルが要求（現状の正） | 800 が pull するもの | 判定 |
|---|---|---|---|
| MELCHIOR | `qwen2.5-coder:7b` | `qwen2.5-coder:7b` | ✅ 一致 |
| BALTHASAR | `gemma4:e4b-it-qat` | `phi4:latest`（BALTHASAR用と注記） | ❌ 未pull |
| CASPER | Haiku 標準（Ollama 不使用） | `llama3.1:8b`（CASPER用と注記） | ❌ 不要 pull（~5GB） |
| METATRON | `devstral:latest` | `devstral:latest` | ✅ 一致（ただし VRAM 注意、下記） |
| SANDALPHON | `phi4:latest` | `lfm2.5:8b`（SANDALPHON用と注記） | ⚠ phi4 は pull されるが注記が旧割当。lfm2.5 は不要 pull |
| LELIEL | `deepseek-r1:8b` | なし | ❌ 未pull → **magi-hard 6体目が新規環境で常に Haiku 行き** |
| codegen | Codex（Ollama 不使用、fallback は Haiku） | `gemma4:12b`（codegen用と注記、~8GB） | ❌ 不要 pull |
| knowledge-rag/index | `qwen3:8b`, `qwen2.5:3b`(+7b) | 同左 | ✅ 一致 |

## 影響

- 新規環境で BALTHASAR / LELIEL がローカル LLM で動かない（「1スキル1ローカルLLM」原則が初期状態で崩れる）。
- 不要モデル3本（llama3.1:8b, lfm2.5:8b, gemma4:12b）で約18GBのディスクと pull 時間を浪費。
- TargetPC（RTX 3070 / 8GB VRAM、800 内コメント）では `devstral:latest`（~14GB）が VRAM に収まらず
  CPU オフロードで低速になる懸念。METATRON のモデル選定は別途検証が必要。

## 対応プラン

1. `setup/800-ollama-models.sh` のモデルリストをスキル定義（正）に同期する：
   - `_om_shared`: `qwen2.5-coder:7b`（MELCHIOR）のみに整理
   - `_om_hard`: `gemma4:e4b-it-qat`（BALTHASAR）, `devstral:latest`（METATRON）, `phi4:latest`（SANDALPHON）,
     `deepseek-r1:8b`（LELIEL）, `qwen3:8b`（index）
   - `_om_codegen` ブロックを削除（codegen は Codex 委譲。fallback も Haiku でありローカルLLM不使用）
   - 旧注記コメント（granite4 経緯等）を現状に合わせ更新
2. 既存環境向けに、不要になったモデルの掃除手順をコメントまたは docs に残す：
   `ollama rm llama3.1:8b lfm2.5:8b gemma4:12b`（自動削除はしない — 他用途で使っている可能性があるため）。
3. **単一情報源化（再発防止）**: モデル割当を `skills/*/SKILL.md` と 800 の2箇所に持つ構造が原因。
   `setup/ollama-models.list`（`<persona>\t<model>` 形式）を新設し、800 はそれを読むだけにする案を検討。
   スキル側の書き換えまでやると差分が大きいので、第一段階は「800 にリストの正はスキル側と明記＋
   CI で突合チェック（[11-ci-pipeline.md](11-ci-pipeline.md) のスクリプトで grep 突合）」に留めるのが現実的。
4. METATRON の VRAM 問題は別判断: `devstral` 継続（速度許容）か、8GB 級モデルへの置換ベンチを Issue 化。

## 受け入れ基準

- [ ] 新規環境で setup 実行後、`ollama list` に 6体分（CASPER除く5モデル）+ knowledge 系が揃う
- [ ] `/magi-hard` が新規環境でフォールバック確認なしに完走する（Ollama 起動時）
- [ ] gemma4:12b / llama3.1:8b / lfm2.5:8b が pull 対象から消えている
- [ ] SKILLS.md のモデル表と 800 のリストが一致（→ 03 と同時に修正）

## 影響ファイル

- `setup/800-ollama-models.sh`
- `SKILLS.md`（→ 03 で対応）
