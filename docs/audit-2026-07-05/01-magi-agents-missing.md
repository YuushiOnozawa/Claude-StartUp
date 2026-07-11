# 01. MAGI エージェント定義の参照不整合（#203 の統一方針が未完遂）

種別: 修正対応 / 深刻度: 高

## 実態（git 履歴 + 本番 ~/.claude 確認済み）

当初「5体分のエージェント定義ファイル欠落」と見えたが、履歴を追うと事情が異なる：

1. #135 で `agents/{melchior,balthasar,casper,metatron,sandalphon}.md` を含む MAGI 5体を実装
2. **#203「fix(agents): MAGI エージェント定義を削除しスキル経由呼び出しに統一する」で5体分を意図的に削除**
3. しかし `skills/magi-common/references/execution-steps.md` の Haiku フォールバックパスと
   `skills/casper/SKILL.md`（「agents/casper.md のステップ1で CLAUDE.md を読む」）には
   **`agents/<persona>.md` への参照が残ったまま**
4. その後 #234 で LELIEL 追加時に `agents/leliel.md` だけが**新規作成され、削除方針と矛盾**
5. 本番デプロイ先 `~/.claude/`（repo clone）にも5体分は存在しない（HEAD では追跡、
   作業ツリーで削除 = #203 相当の状態）。リポジトリと本番の両方で参照先不在が確定

つまり問題は「ファイルを作り忘れた」ではなく「**#203 の統一を参照側まで完遂していない**」こと。

## 影響

- CASPER（Haiku 標準・magi-fast/hard の必須構成員）は毎回、存在しない `agents/casper.md` を
  参照する手順で動く。Ollama 停止時は melchior/balthasar/metatron/sandalphon も同様
- ペルソナ定義の実体が「references のみ（5体）」と「agents + references（leliel）」に分裂しており、
  新ペルソナ追加時にどちらに倣うべきか判断できない

## 対応プラン

### 方針判断（先に決める）: 案A を推奨

**案A（推奨）: #203 の方針を完遂 — agents/ 参照を撤去し references に一本化**

直近の明示的な設計判断（#203）に沿い、変更も削除方向で小さい：

1. `execution-steps.md` の Haiku フォールバックから `$AGENT_PATH` / `agents/<persona>.md` 読み込み手順を削除。
   Haiku に渡す内容を references 4点（task-base / task-instruction / review-criteria / output-format）に統一
2. ペルソナ人格の記述が不足するなら `references/task-instruction.md` 側に補強（実体は既にロール定義を持つ）
3. `skills/casper/SKILL.md` の「agents/casper.md のステップ1で〜」を「execution-steps の CASPER 専用手順
   （$CLAUDE_RULES 取得）で〜」に書き換え
4. `agents/leliel.md`（692 bytes）の内容を `skills/leliel/references/task-instruction.md` に統合し、
   `agents/leliel.md` を削除。melchior/leliel の SKILL.md から「エージェント定義」行を削除
5. `agents/code-reviewer.md` は MAGI 外（別用途）なので対象外
6. 各ペルソナ SKILL.md の「エージェント定義」行を全て削除（grep で機械的に確認:
   `grep -rn 'agents/' skills/`）

**案B: #203 を部分巻き戻し — `git show 20b367f^:agents/<persona>.md` から5体分を復元**

参照側は無変更で済むが、#203 でわざわざ削除した経緯（スキル経由統一）に逆行する。
#203 の削除理由に「references と内容重複していた」等の記載がないか PR を確認してから判断すること。

### 検証

- Ollama 停止状態で `/magi-fast` を実行し、3体とも references のみで規定フォーマット出力になること
- `/casper` 単独実行で CLAUDE.md ルール読み込みが機能すること
- `grep -rn 'agents/' skills/ | grep -v code-reviewer` がゼロ件（案A の場合）

## 受け入れ基準

- [ ] ペルソナ定義の実体が全6体で同一方式（references のみ）に統一されている
- [ ] 存在しないファイルへの参照が skills/ 配下にない
- [ ] Haiku フォールバック経路が実ファイルのみで完結する

## 影響ファイル

- `skills/magi-common/references/execution-steps.md`
- `skills/casper/SKILL.md`, `skills/leliel/SKILL.md` ほか各ペルソナ SKILL.md（「エージェント定義」行）
- `skills/leliel/references/task-instruction.md`（leliel.md 統合先）
- 削除: `agents/leliel.md`（案A の場合）
