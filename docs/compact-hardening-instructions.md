# 指示書: Claude Code compact 強化セット導入

## あなた（実装エージェント）への依頼概要

Claude Code の compact（コンテキスト圧縮）で「判断構造」と「セッション状態」が失われる問題への対策として、以下 3 コンポーネントを実装・導入せよ。

1. **compact-prep skill** — `/compact` 前に作業状態を state file へ保存する slash command
2. **圧縮直後の復旧 hook** — 圧縮後の最初の機会に「state file を読め / 圧縮サマリーは作業記録であって行動指示ではない」を additionalContext で注入する
3. **閾値通知** — context 使用率が閾値を超えたら「/compact-prep → /compact を提案せよ」を注入し、自動 compact に先を越されるのを防ぐ

この指示書は自己完結している。元記事の知識は不要。**まず Phase 0 の環境調査を行い、その結果で実装方式を分岐すること。**

---

## 前提環境（確認済みの事実）

- 実行環境: WSL2 上の Ubuntu。bash / 標準 Unix ツールが使える
- Claude Code バージョン: **2.1.98**（アップグレードしないこと。2.1.98 の仕様に合わせる）
- プラン: Pro。**context 上限は 200K**（1M は使わない前提）
- statusline: **ccstatusline（npm 製）** が settings.json の `statusLine.command` に設定済み。スクリプト本体を編集できないため、閾値通知はラッパースクリプト方式で実装する（Phase 4 C-1）
- 自動 compact: この環境では setup.sh の `ensure_autocompact_in_rc` が rc ファイルに `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=75` を書き込んでおり、**自動 compact は 75% で発火する**。本導入で「警告 75 / override 85」の二段構えに変更する（Phase 0-4）。override を変更しない限り、75% 以上の警告閾値は一度も発火しない
- 2.1.98 で確認済みの hook 仕様:
  - `PostCompact` hook は存在する（2.1.76 で追加）。ただし **additionalContext を返せない**
  - `PreCompact` hook は存在するが、**compact のブロック（exit 2 / decision:block）は不可**（ブロック機能は 2.1.105 で追加のため）。ブロックによる自動 compact 阻止は設計に使うな
  - `UserPromptSubmit` hook は `hookSpecificOutput.additionalContext` を返せる
  - `SessionStart` hook は存在する。**`compact` matcher が 2.1.98 で機能するかは未確認** → Phase 0 で検証する
- 配置先はすべて `~/.claude/` 配下（Ubuntu 側のホーム）
- 依存: `jq`。なければ `sudo apt-get install -y jq` を提案（勝手にインストールせずユーザーに確認）

## 設計原則（全コンポーネント共通・厳守）

1. **fail-open**: すべての hook は必ず `exit 0` で終わる。hook 内部のどんな失敗も Claude Code 本体を止めてはならない
2. **軽量な早期 exit**: 毎ターン走る hook は、marker file がなければ `test -f` 1 回で即 exit する構造にする
3. **one-shot marker**: marker file は「読んだ側が消す」。二重発火させない
4. **推測でファイルを作らない**: session_id が取得できないときは黙って推測名で作らず、その旨を報告して停止する（Hard gate）
5. **既存設定を壊さない**: `~/.claude/settings.json` は読み込んで hook 配列にマージ追記する。上書きで既存 hook を消さないこと。編集前にバックアップ（`settings.json.bak`）を取る

## 使用する marker / state のパス一覧

すべて `${TMPDIR:-/tmp}` 配下。WSL 再起動で消えるが、いずれも一時データなので許容する。

| パス | 内容 | 書く者 | 消す者 |
|---|---|---|---|
| `${TMPDIR:-/tmp}/claude-compact-state/<session_id>.md` | 圧縮前の作業状態 | compact-prep skill | （残置でよい） |
| `${TMPDIR:-/tmp}/claude-compacted/<session_id>` | 圧縮発生 marker（案Bのみ使用） | PostCompact hook | UserPromptSubmit 復旧 hook |
| `${TMPDIR:-/tmp}/claude-compact-warn/<session_id>` | 閾値超過 warn marker | statusline | UserPromptSubmit 通知 hook |
| `${TMPDIR:-/tmp}/claude-compact-warned/<session_id>` | 通知済み cooldown marker | UserPromptSubmit 通知 hook | 圧縮時（復旧 hook 側） |
| `${TMPDIR:-/tmp}/claude-active-plan/<session_id>` | active plan file へのポインタ（任意・存在すれば使う） | （既存運用があれば） | （残置でよい） |

---

# Phase 0: 環境調査（実装前に必ず行う）

## 0-1. transcript ディレクトリの slug 形式を確認

Claude Code はプロジェクトごとに `~/.claude/projects/<slug>/<session_id>.jsonl` に transcript を書く。slug は cwd のパスを変換したものだが、**変換規則を推測せず実物で確認する**:

```bash
ls ~/.claude/projects/
```

現在の作業ディレクトリに対応する slug を特定し、後述の `get-session-id.sh` の slug 生成ロジックを実物に合わせること（一般には `/` や `.` が `-` に置換される形式だが、必ず実物と突き合わせる）。

## 0-2. SessionStart `compact` matcher の動作検証（実装方式の分岐点）

以下のテスト hook を作り、2.1.98 で SessionStart(compact) が (a) 発火するか、(b) additionalContext が注入されるかを検証する。

`~/.claude/hooks/test-sessionstart-compact.sh`:

```bash
#!/bin/bash
set -uo pipefail
INPUT=$(cat)
printf '%s | %s\n' "$(date -Is)" "$INPUT" >> /tmp/test-sessionstart-compact.log
jq -n '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:"[TEST-MARKER-SS-COMPACT] この文字列が見えたら、次の応答の冒頭で TEST-MARKER-SS-COMPACT visible と発言せよ。"}}'
exit 0
```

settings.json に一時登録:

```json
"SessionStart": [
  { "matcher": "compact", "hooks": [{ "type": "command", "command": "~/.claude/hooks/test-sessionstart-compact.sh" }] }
]
```

検証手順（ユーザーに実施してもらうか、`claude -p` 等で再現する）:
1. 新しいセッションを開始し、数ターン適当な会話をする
2. `/compact` を実行する
3. 次のターンで応答に `TEST-MARKER-SS-COMPACT visible` が出るか確認する
4. `/tmp/test-sessionstart-compact.log` に発火記録があるか確認する

**判定:**
- log に記録があり、かつ marker 発言が出た → **案A（SessionStart 方式）** で実装
- log に記録はあるが marker 発言が出ない（additionalContext が捨てられている） → **案B（PostCompact + UserPromptSubmit リレー方式）** で実装
- log に記録すらない（matcher が発火しない） → **案B** で実装

検証後、テスト hook と一時登録は削除する。

## 0-3. statusline の現状確認（ラッパー方式の前提確認）

この環境の `statusLine.command` は `ccstatusline`（npm 製）であり、スクリプト本体に分岐を追記できない。そのため閾値通知は**ラッパースクリプト方式**（C-1）で実装する。ここでは前提を確認する:

1. `~/.claude/settings.json` の `statusLine` 設定を読み、`ccstatusline` の起動コマンド（PATH 上のコマンド名か、フルパスか、`npx` 経由か）を正確に記録する
2. `command -v ccstatusline` でフルパスを確認する。hook/statusline は非対話シェルで走るため PATH に乗らない可能性がある。**ラッパーからはフルパスで呼ぶ**こと
3. statusline の stdin JSON に `.session_id` と `.transcript_path` が含まれることを確認する。一時的に以下のワンライナーを statusLine.command に差して 1 ターン動かせばよい（確認後すぐ戻す）:

```bash
#!/bin/bash
tee /tmp/statusline-input-dump.json | ccstatusline
```

`/tmp/statusline-input-dump.json` に `.session_id` / `.transcript_path` があること、加えて context 使用率に相当するフィールドがあるかを確認する。使用率フィールドが**あれば** C-1 の transcript 計算をそれに置き換えてよい（軽量化）。なければ C-1 の transcript 計算をそのまま使う。

## 0-4. 自動 compact 発火点の確認と閾値の決定

**警告閾値は自動 compact の発火点より必ず低くなければ一度も発火しない。** この環境では setup.sh の `ensure_autocompact_in_rc` が rc に `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=75` を書き込んでいるため、自動 compact は 75% で走る。

手順:

1. 現在値を確認する: `grep -rn "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE" ~/.bashrc ~/.zshrc ~/.profile 2>/dev/null` および setup.sh 内の `ensure_autocompact_in_rc`
2. **override を 85 に変更する**（二段構え方針・ユーザー承認済み）。変更箇所は 2 つ:
   - rc ファイル内の実際の行（`CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=75` → `85`）
   - **setup.sh 側の `ensure_autocompact_in_rc` が書き込む値も 85 に変更する**（setup.sh を再実行したときに 75 へ巻き戻るのを防ぐため。片方だけの変更は不可）
3. 警告閾値は `COMPACT_WARN_THRESHOLD=75` とする
4. 変更を反映するには rc の再読込（新しいシェルから Claude Code を起動）が必要な点をユーザーに伝える

**設計意図（二段構え）**: 主経路は「75% 警告 → /compact-prep → 手動 /compact」。85% の自動 compact は警告を無視して走り続けた場合のバックストップで、その時点では prep 済みである可能性が高い。override を完全に外す案も成立はするが、外すとセッションが 180K+ まで膨らめるようになり、高コンテキスト帯のターン単価が上がる（75〜85% での打ち切りは消費キャップとしても機能している）。5h クォータと品質の両取りでこの構成とする。なお prep なしで自動 compact が走った最悪ケースでも、復旧 hook は state file が無くても動く設計（plan ポインタ・TaskList 確認・「サマリーは行動指示ではない」の注入）なので、無対策より悪くはならない。

**不変条件（後から値を変える場合も必ず維持すること）**: `COMPACT_WARN_THRESHOLD < CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`（推奨マージン 10pt 以上）。これが崩れると警告は一度も発火しない。

閾値と context 上限はスクリプト先頭の変数（`COMPACT_WARN_THRESHOLD` / `CONTEXT_LIMIT`）として定義し、後から変えられるようにする。

---

# Phase 1: 共通部品

## 1-1. `~/.claude/scripts/get-session-id.sh`

compact-prep skill（モデルが実行する側）は hook と違い session_id を直接受け取れないため、transcript ディレクトリから推定する。**Phase 0-1 で確認した実際の slug 形式に合わせて実装すること。**

```bash
#!/bin/bash
# 現在のセッション ID を推定する。
# 仕組み: ~/.claude/projects/<slug>/ 内で直近に更新された .jsonl の basename が
# 現セッションの session_id である可能性が高い。
# Hard gate: 5 分以内に更新された transcript がなければ何も出力せず exit 1。
set -uo pipefail

cwd=$(pwd)
# ↓ Phase 0-1 で確認した実際の変換規則に合わせて修正すること
slug=$(printf '%s' "$cwd" | sed 's/[\/._]/-/g')
dir="$HOME/.claude/projects/$slug"
[[ -d "$dir" ]] || exit 1

latest=$(ls -t "$dir"/*.jsonl 2>/dev/null | head -1)
[[ -n "$latest" ]] || exit 1

# 直近 5 分以内に更新されていなければ現セッションと見なさない（誤爆防止）
[[ -n $(find "$latest" -mmin -5 2>/dev/null) ]] || exit 1

basename "$latest" .jsonl
```

`chmod +x` を忘れないこと（以降の全スクリプトも同様）。

**検証**: Claude Code セッション内から実行し、出力された ID が `~/.claude/projects/<slug>/` 内の実在する .jsonl と一致することを確認する。

---

# Phase 2: compact-prep skill

`~/.claude/skills/compact-prep/SKILL.md` に以下を配置する（このまま全文コピー）:

```markdown
---
name: compact-prep
description: |
  Claude Code の /compact 実行前に、現セッションの作業状態を一時 state file へ保存する。
  MANDATORY TRIGGERS: /compact-prep, compact-prep, 圧縮準備, compact 準備, コンパクト準備, 圧縮前状態保存。
  DO NOT TRIGGER: compact 後の復旧、通常の進捗報告、plan 作成、context 使用率の雑談。
strict_procedure: true
argument-hint: "[復旧メモ]"
allowed-tools: Read Write Bash(~/.claude/scripts/get-session-id.sh *) Bash(mkdir *) Bash(date *) Bash(pwd)
---

# compact-prep

Claude Code の `/compact` 前に、圧縮サマリーへ残りにくい作業状態を
`${TMPDIR:-/tmp}/claude-compact-state/${SESSION_ID}.md` へ保存する。

## Strict procedure profile

- Strictness: strict-procedure。圧縮前 state file の内容と保存完了報告が成果そのもの。
- Hard gates: session_id が取得できない場合は state file を推測名で作らず、取得不能として停止する。
- Forcing function: 保存先パスを固定し、保存後にファイルを読み返して必須項目の有無を確認する。
- Completion receipt: state file パス、保存した主要項目、未確認項目、次に実行する `/compact` 案内を報告する。

## 手順

1. session_id を取得する。
   - `~/.claude/scripts/get-session-id.sh` を実行する。
   - 取得できない場合は state file を作らず、session_id が取得できないため準備未完了と報告する。
2. 保存先を `${TMPDIR:-/tmp}/claude-compact-state/${SESSION_ID}.md` に決める。
3. TaskList、active plan file、編集中ファイルを確認する。
   - active plan file がある場合はそのファイルを読む。
   - 並行 worker（tmux 等）を使っていない場合は「未使用」と記録する。
4. state file に以下の見出しをこの順で保存する。
   - `# Compact Prep State`
   - `## Active Plan`
   - `## Current Phase`
   - `## TaskList Summary`
   - `## Session Decisions`
   - `## Constraints and Blockers`
   - `## Worker Topology`
   - `## Editing Files`
   - `## Recovery Notes`
5. 保存後に state file を読み直し、上記見出しがすべて存在することを確認する。
6. ユーザーに「準備完了。`/compact` を実行してください。」と伝える。

## 保存内容

- active plan file パスと、現在のフェーズ/ステップ
- in-progress タスク一覧と補足
- session 中の判断、ユーザーの選択、不採用にした案の理由
- 制約、ブロッカー、未完了の検証
- worker 体制。tmux 等の並行 worker 使用時は pane、role、担当を記録する
- 編集中のファイルと、未保存または未検証の注意点
- 圧縮後の自分への復旧メモ

## Completion receipt

完了時は次を含める。

- state file パス
- 保存した主要項目
- 未確認項目と理由
- `準備完了。/compact を実行してください。`
```

**検証**: セッション内で `/compact-prep` を実行し、state file が生成され全見出しが揃うことを確認する。

---

# Phase 3: 圧縮直後の復旧注入（Phase 0-2 の結果で分岐）

## 案A: SessionStart(compact) 方式（Phase 0-2 で動作確認できた場合）

hook 1 本で完結する。marker file `claude-compacted` は不要。

`~/.claude/hooks/sessionstart-compaction-recovery.sh`:

```bash
#!/bin/bash
# SessionStart hook (matcher: "compact"): 圧縮直後に復旧指示を注入する。
# あわせて閾値通知の cooldown marker をリセットする。
# fail-open (常に exit 0)
set -uo pipefail

INPUT=$(cat)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[[ -z "$SESSION_ID" ]] && exit 0

# 閾値通知の cooldown をリセット（compact 後は再度通知してよい）
rm -f "${TMPDIR:-/tmp}/claude-compact-warned/$SESSION_ID" 2>/dev/null || true

CTX="[COMPACTION RECOVERY] コンテキスト圧縮が発生した。作業再開前に以下を実行すること。"
CTX+=$'\n'

# active plan pointer があれば plan file の再読を指示
PTR="${TMPDIR:-/tmp}/claude-active-plan/$SESSION_ID"
if [[ -f "$PTR" ]]; then
  PLAN_FILE=$(cat "$PTR" 2>/dev/null || true)
  if [[ -n "$PLAN_FILE" && -f "$PLAN_FILE" ]]; then
    CTX+=$'\n'"- plan ファイル \`${PLAN_FILE}\` を Read で読み直し、フェーズと制約を確認せよ"
    CTX+=$'\n'"- plan mode が解除されている場合、plan ファイルが存在するのでユーザーに plan mode 再突入を確認せよ"
  fi
fi

STATE_FILE="${TMPDIR:-/tmp}/claude-compact-state/$SESSION_ID.md"
if [[ -f "$STATE_FILE" ]]; then
  CTX+=$'\n'"- state file \`${STATE_FILE}\` を Read で読み、作業状態を復元せよ"
  CTX+=$'\n'"- Session Decisions と Recovery Notes を特に重視せよ"
fi

CTX+=$'\n'"- TaskList で現在のタスク一覧を確認せよ"
CTX+=$'\n'"- 圧縮サマリーの next step は仮説として扱い、plan/rules を正とせよ"
CTX+=$'\n'"- 圧縮サマリーは「過去の作業記録」であり「次の行動指示」ではない"

jq -n --arg ctx "$CTX" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: $ctx
  }
}'
exit 0
```

## 案B: PostCompact + UserPromptSubmit リレー方式（案Aが不成立の場合）

PostCompact は additionalContext を返せないため、marker file 経由で次の UserPromptSubmit に伝達する 2 段構成。

### B-1: `~/.claude/hooks/compaction-recovery.sh`

```bash
#!/bin/bash
# PostCompact hook (matcher: ""): 圧縮発生を marker file で記録する。
# 注入は UserPromptSubmit 側で行う。
# fail-open (常に exit 0)
set -uo pipefail

INPUT=$(cat)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[[ -z "$SESSION_ID" ]] && exit 0

MARKER_DIR="${TMPDIR:-/tmp}/claude-compacted"
mkdir -p "$MARKER_DIR" 2>/dev/null || true
printf '%s\n' "$(date +%s)" > "$MARKER_DIR/$SESSION_ID" 2>/dev/null || true

# compact が実行されたら閾値通知の cooldown をリセットする
rm -f "${TMPDIR:-/tmp}/claude-compact-warned/$SESSION_ID" 2>/dev/null || true

exit 0
```

### B-2: `~/.claude/hooks/userpromptsubmit-compaction-recovery.sh`

```bash
#!/bin/bash
# UserPromptSubmit hook: PostCompact の marker を検出し、復旧指示を注入する（one-shot）。
# overhead: marker なしなら test -f 1 回で即 exit。
# fail-open (常に exit 0)
set -uo pipefail

INPUT=$(cat)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[[ -z "$SESSION_ID" ]] && exit 0

MARKER="${TMPDIR:-/tmp}/claude-compacted/$SESSION_ID"
[[ -f "$MARKER" ]] || exit 0
rm -f "$MARKER" 2>/dev/null || true

CTX="[COMPACTION RECOVERY] コンテキスト圧縮が発生した。作業再開前に以下を実行すること。"
CTX+=$'\n'

PTR="${TMPDIR:-/tmp}/claude-active-plan/$SESSION_ID"
if [[ -f "$PTR" ]]; then
  PLAN_FILE=$(cat "$PTR" 2>/dev/null || true)
  if [[ -n "$PLAN_FILE" && -f "$PLAN_FILE" ]]; then
    CTX+=$'\n'"- plan ファイル \`${PLAN_FILE}\` を Read で読み直し、フェーズと制約を確認せよ"
    CTX+=$'\n'"- plan mode が解除されている場合、plan ファイルが存在するのでユーザーに plan mode 再突入を確認せよ"
  fi
fi

STATE_FILE="${TMPDIR:-/tmp}/claude-compact-state/$SESSION_ID.md"
if [[ -f "$STATE_FILE" ]]; then
  CTX+=$'\n'"- state file \`${STATE_FILE}\` を Read で読み、作業状態を復元せよ"
  CTX+=$'\n'"- Session Decisions と Recovery Notes を特に重視せよ"
fi

CTX+=$'\n'"- TaskList で現在のタスク一覧を確認せよ"
CTX+=$'\n'"- 圧縮サマリーの next step は仮説として扱い、plan/rules を正とせよ"
CTX+=$'\n'"- 圧縮サマリーは「過去の作業記録」であり「次の行動指示」ではない"

jq -n --arg ctx "$CTX" '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: $ctx
  }
}'
exit 0
```

---

# Phase 4: 閾値通知（自動 compact の先回り）

## C-1: statusline ラッパースクリプト

この環境の statusline は ccstatusline（npm 製）でスクリプト本体に追記できないため、ラッパー方式を使う。要点は 1 行: **settings.json の `statusLine.command` を wrapper に差し替え、wrapper が stdin を分岐して ccstatusline へパススルーしつつ、transcript の usage から使用率を計算して閾値超過なら warn marker を書く。**

`~/.claude/scripts/statusline-wrapper.sh`:

```bash
#!/bin/bash
# statusline wrapper: 表示は ccstatusline にパススルー。副業として warn marker 判定。
# marker 処理のいかなる失敗も表示を壊してはならない（fail-open）。
set -uo pipefail
INPUT=$(cat)

{
  COMPACT_WARN_THRESHOLD=75   # 不変条件: CLAUDE_AUTOCOMPACT_PCT_OVERRIDE (85) より 10pt 以上低く保つ
  CONTEXT_LIMIT=200000
  session_id=$(printf '%s' "$INPUT" | jq -r '.session_id // empty')
  transcript=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty')
  if [[ -n "$session_id" && -n "$transcript" && -f "$transcript" ]] \
     && [[ ! -f "${TMPDIR:-/tmp}/claude-compact-warned/$session_id" ]]; then
    # 直近の usage エントリから context 消費を推定（head -1 で早期打ち切り）
    used=$(tac "$transcript" | jq -r '
      select(.message.usage != null) |
      (.message.usage.input_tokens // 0)
      + (.message.usage.cache_creation_input_tokens // 0)
      + (.message.usage.cache_read_input_tokens // 0)' 2>/dev/null | head -1)
    if [[ "$used" =~ ^[0-9]+$ ]]; then
      int_pct=$(( used * 100 / CONTEXT_LIMIT ))
      if [ "$int_pct" -ge "$COMPACT_WARN_THRESHOLD" ]; then
        mkdir -p "${TMPDIR:-/tmp}/claude-compact-warn"
        printf '%s\n' "$int_pct" > "${TMPDIR:-/tmp}/claude-compact-warn/$session_id"
      fi
    fi
  fi
} 2>/dev/null || true

# 表示: ccstatusline へパススルー（Phase 0-3 で確認したフルパスに置き換えること）
printf '%s' "$INPUT" | /path/to/ccstatusline
```

補足:
- ccstatusline の呼び出しは Phase 0-3 で確認したフルパスを使う（非対話シェルでは PATH に乗らない可能性があるため）
- Phase 0-3 で stdin JSON に使用率フィールドが見つかった場合は、transcript 計算をそれに置き換えてよい（軽量化）
- settings.json の `statusLine.command` を `~/.claude/scripts/statusline-wrapper.sh` に差し替える。元の設定値はバックアップ（Phase 5 で取得）に残ることを確認する

## C-2: `~/.claude/hooks/userpromptsubmit-compact-prep-reminder.sh`

```bash
#!/bin/bash
# UserPromptSubmit hook: statusline が書いた warn marker を検出し、
# compact-prep 実行提案を注入する（one-shot + cooldown）。
# fail-open (常に exit 0)
set -uo pipefail

INPUT=$(cat)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[[ -z "$SESSION_ID" ]] && exit 0

WARN_MARKER="${TMPDIR:-/tmp}/claude-compact-warn/$SESSION_ID"
[[ -f "$WARN_MARKER" ]] || exit 0

CTX_PCT=$(cat "$WARN_MARKER" 2>/dev/null)
CTX_PCT=${CTX_PCT:-"?"}
rm -f "$WARN_MARKER" 2>/dev/null || true

# cooldown marker（statusline の再 warn を防止。compact 時にリセットされる）
WARNED_DIR="${TMPDIR:-/tmp}/claude-compact-warned"
mkdir -p "$WARNED_DIR" 2>/dev/null || true
printf '%s\n' "$(date +%s)" > "$WARNED_DIR/$SESSION_ID" 2>/dev/null || true

CTX="[COMPACT PREP REMINDER] context 使用率が ${CTX_PCT}% に達した。"
CTX+=$'\n'"- 作業区切りでユーザーに \`/compact-prep\` の実行を提案せよ。"
CTX+=$'\n'"- \`/compact-prep\` 実行後、ユーザーに \`/compact\` 実行を案内せよ。"
CTX+=$'\n'"- scope 縮小や別セッション化ではなく、圧縮前 state 保存で対処せよ。"

jq -n --arg ctx "$CTX" '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: $ctx
  }
}'
exit 0
```

---

# Phase 5: settings.json への登録

`~/.claude/settings.json` を読み、既存の hooks 設定に**マージ追記**する（バックアップを先に取る）。あわせて `statusLine.command` を `~/.claude/scripts/statusline-wrapper.sh` に差し替える（元の ccstatusline 起動コマンドはバックアップと wrapper 内に保全される）。

**案A採用時:**

```json
{
  "hooks": {
    "SessionStart": [
      { "matcher": "compact", "hooks": [{ "type": "command", "command": "~/.claude/hooks/sessionstart-compaction-recovery.sh" }] }
    ],
    "UserPromptSubmit": [
      { "hooks": [{ "type": "command", "command": "~/.claude/hooks/userpromptsubmit-compact-prep-reminder.sh" }] }
    ]
  }
}
```

**案B採用時:**

```json
{
  "hooks": {
    "PostCompact": [
      { "matcher": "", "hooks": [{ "type": "command", "command": "~/.claude/hooks/compaction-recovery.sh" }] }
    ],
    "UserPromptSubmit": [
      { "hooks": [{ "type": "command", "command": "~/.claude/hooks/userpromptsubmit-compaction-recovery.sh" }] },
      { "hooks": [{ "type": "command", "command": "~/.claude/hooks/userpromptsubmit-compact-prep-reminder.sh" }] }
    ]
  }
}
```

登録後、設定を反映させるには Claude Code の再起動（または新セッション）が必要。

---

# Phase 6: 受け入れ検証

以下をすべて確認し、結果を報告すること。

## 単体テスト（hook スクリプト単体）

```bash
# 各 hook に模擬入力を流し、exit 0 かつ想定出力であることを確認
echo '{"session_id":"test-1234"}' | ~/.claude/hooks/<各スクリプト>; echo "exit=$?"
# 異常系: 空入力・壊れた JSON でも exit 0 であること（fail-open）
echo '' | ~/.claude/hooks/<各スクリプト>; echo "exit=$?"
echo 'not-json' | ~/.claude/hooks/<各スクリプト>; echo "exit=$?"
```

- marker file の生成/削除が仕様どおりか（one-shot: 2 回目の実行では注入されない）
- `claude-compact-state/test-1234.md` を置いた状態で復旧 hook を実行すると、注入 JSON に state file パスが含まれるか

## 結合テスト（実セッション）

1. 新セッションで数ターン会話 → `/compact-prep` → state file の全見出し確認 → `/compact`
2. compact 後の最初のターンで、モデルが state file を Read しに行くこと（復旧注入が効いている証拠）を確認
3. 通常ターン（marker なし）で hook がエラー表示を出さないこと
4. **statusline 表示**: wrapper 差し替え後も ccstatusline の表示が従来どおりであること（表示が消えた場合はフルパス解決を疑う）
5. 閾値通知: wrapper 内の `COMPACT_WARN_THRESHOLD=1` に一時的に下げて 1 ターン動かし、次ターンで compact-prep 提案が出ること、その次のターンでは再提案されないこと（cooldown）を確認。確認後に閾値を 75 に戻す
6. **override 変更の確認**: 新しいシェルで `echo $CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` が 85 を返すこと

## 完了報告に含めるもの

- 採用した方式（案A / 案B）と Phase 0-2 の判定根拠
- 作成・変更したファイルの一覧（settings.json のバックアップパス、rc / setup.sh の変更箇所含む）
- 各検証の結果（成功/失敗と証跡）
- 決定した値の一覧: `COMPACT_WARN_THRESHOLD` / `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` / `CONTEXT_LIMIT`（不変条件を満たしていることを明記）

---

# 既知の制約・注意（実装後にユーザーへ伝えること)

- state file は `/tmp` 配下のため WSL 再起動で消える。compact をまたぐ短期の受け渡し用であり、永続メモとしては使えない
- `get-session-id.sh` は「直近 5 分以内に更新された transcript」ヒューリスティックのため、同一ディレクトリで複数セッションを並走させると誤った session_id を返す可能性がある
- 自動 compact が閾値通知より先に走った場合（急激な context 消費時）、state file なしで圧縮される。重要な判断（採用/却下/理由）はセッション中に随時 plan/notes ファイルへ書く運用を併用することを推奨
- 閾値通知は 1 compact サイクルにつき 1 回のみ（cooldown 設計）
- 閾値や override を後から調整する場合も、不変条件 `COMPACT_WARN_THRESHOLD < CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`（マージン 10pt 以上推奨）を必ず維持すること。崩れると警告が一度も発火しなくなる。また setup.sh を再実行する運用がある限り、override の値は rc と setup.sh の両方で揃えること
