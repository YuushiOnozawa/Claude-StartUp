# 04. knowledge-distill フック登録の二重化と設計競合

種別: 修正対応 / 深刻度: 高（蒸留の二重実行・データ品質に影響）

## 現状

蒸留パイプラインは「SessionEnd でキュー投入（session-end-queue.sh）→ 次回 SessionStart でドレイン
（knowledge-distill.sh）」というキュー方式に移行済みで、リポジトリの `settings.json` もそうなっている：

- SessionStart: `knowledge-distill.sh`（キュー drain + 空会話スキップ）
- SessionEnd: `session-end-queue.sh`（pending キューに push）

ところが `setup/410-hooks-distill.sh` は旧設計のまま、**SessionEnd に `knowledge-distill.sh` を追加登録**する。
jq の冪等チェックは「SessionEnd 内に `knowledge-distill.sh` を含むコマンドがあるか」なので、
`session-end-queue.sh` しかない現 settings.json ではチェックをすり抜けて追記される。

さらにログパスも不一致：
- settings.json（リポジトリ）: `2>> ~/.claude/hooks/logs/knowledge-distill.log`
- 410 が登録するコマンド: `2>> ~/.claude/hooks/knowledge-distill.log`（logs/ なし）

## 実装履歴による裏付け（どちらが正か）

- `hooks/session-end-queue.sh` は PR #97「knowledge-distill のトリガーを **SessionEnd → SessionStart に移す**（Issue #96）」で導入。
- `setup/410-hooks-distill.sh` の SessionEnd 登録は、その後の分割（#171）・修正（#221, #227）でも
  削除されずに残った**旧設計の残骸**。キュー方式（settings.json 側）が意図された設計で確定。
- **本番環境で二重登録を実測済み**: 本番 `~/.claude/settings.json` の SessionEnd には
  `session-end-queue.sh` と `knowledge-distill.sh` の**両方が現に登録されている**
  （後者は `2> >(tee -a ...)` の旧形式コマンド）。本項は理論上のリスクではなく現在進行形の事象。

## 影響

- setup 実行後、同一 transcript が SessionEnd で即時蒸留され、かつ pending キュー経由で次回
  SessionStart にも再蒸留される。raw 生成は KRAG_DISTILL_RETRY ガードで抑止されるが、
  `knowledge-distill-extract.sh` は OUTPUT_FILE を**無条件上書き**（既存ファイルの存在ガードなし）、
  `knowledge-distill-register.sh` にも重複登録ガードがないため、**Ollama 蒸留の再実行と
  knowledge-rag への二重登録が確実に発生する**（「しうる」ではない）。
- ログが2箇所に分散し追跡が困難。
- `~/.claude` は git リポジトリそのものなので、410〜412 による settings.json 書き換えで
  作業ツリーが常に dirty になる（TOOLS.md は「無視してよい」方針だが、settings.json は
  リポジトリに実体があるファイルであり、pull 時のコンフリクト源になる）。

## 追記（2026-07-06）: 先行導入される compact 強化フックの扱い

compact 強化セット（compact-prep skill + 復旧 hook + 閾値通知。`compact-hardening-instructions.md`
参照）は**本項の対応より先行して jq 動的注入で導入される**（監査作業自体を compact 劣化から守るため、
という優先度判断）。本項の実施時に、これらの hook 登録（SessionStart(compact) または PostCompact /
UserPromptSubmit ×2）と statusline wrapper 設定も **repo 直書きへの移行対象に含めること**。
hook スクリプト本体は hooks/ 配下に置かれていれば 700 の自動配備規約に乗る。

## 対応プラン

1. **方針決定（先に決める）**: settings.json のフック登録は「リポジトリ直書き」に一本化する。
   理由: ワンライナー展開では repo = `~/.claude` であり、jq による動的注入は
   (a) リポジトリ版とのドリフト、(b) 冪等チェックのすり抜け、(c) git dirty 化、の3点で不利。
   動的注入が必要なのは「repo が ~/.claude 以外にある開発時」のみで、そのケースは
   600-local-plugins.sh と同様に「手動デプロイ案内」で足りる。
2. `settings.json`（リポジトリ）に、現在 setup が動的注入しているフックをすべて直書きする：
   - SessionStart: knowledge-distill.sh（既存）+ knowledge-prune.sh（411 が注入していたもの）
   - SessionEnd: session-end-queue.sh（既存）+ lessons-learned-distill.sh（410 が注入していたもの）
   - UserPromptSubmit: check-queue.sh（412 が注入していたもの）
   - Stop 等 700-claude-md-lifecycle.sh が注入する claude-md 系フックも同様に棚卸し
3. `setup/410〜412` と `700` の settings.json 書き換え部を削除し、以下だけ残す：
   - フックスクリプトの配置（repo ≠ ~/.claude の場合のみ cp）と chmod
   - `~/.claude/hooks/logs/` ディレクトリの mkdir（現状ログ書き込み先が未作成だと `2>>` が失敗する）
   - settings.json に必要エントリが存在するかの**検証**（なければ fail 表示。書き換えはしない）
4. ログパスを `~/.claude/hooks/logs/<name>.log` に統一する。
5. 移行済み環境向け: 二重登録された SessionEnd の knowledge-distill エントリを検出して警告する
   一時チェックを 10-setup-verify.md の verify スクリプトに含める。

## 受け入れ基準

- [ ] setup.sh をワンライナー実行しても settings.json が書き換わらない（git status がクリーン）
- [ ] SessionEnd に knowledge-distill.sh の直接実行が存在しない（キュー方式のみ）
- [ ] 1セッション終了 → 次セッション開始で、同一 transcript の蒸留・register が1回だけ行われる
- [ ] 全フックのログが `hooks/logs/` 配下に出る

## 影響ファイル

- `settings.json`
- `setup/410-hooks-distill.sh`, `setup/411-hooks-auto.sh`, `setup/412-hooks-queue.sh`, `setup/700-claude-md-lifecycle.sh`
