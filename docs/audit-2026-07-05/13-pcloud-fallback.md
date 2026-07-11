# 13. 知識ストアの疎結合化（記録層 / 配送層 / 取込層の分離）

種別: アーキテクチャ変更（方針決定済み: 2026-07-05）/ 優先度: 高

## 決定事項（経緯順）

1. rclone FUSE マウント（`~/pcloud`）は廃止する（複数 WSL コンテナ運用で構造的に不安定）
2. クラウド同期は Windows 側 pCloud アプリの **Sync フォルダ**（実 NTFS フォルダ ⇔ クラウド）に任せる
   （Windows 常時起動・アプリ導入済みのため）
3. **セッション記録と Obsidian への配送は完全に疎にする**。記録層はローカルで完結し、
   Obsidian / pCloud / /mnt/c を一切知らない
4. **逆方向（Obsidian の人間ノート → RAG）も必要**。ユースケース: スマホで URL をメモ →
   Claude が調査 → 結果を knowledge として還流（「AI の第2の脳」構想 → [16](16-obsidian-second-brain.md)）

## アーキテクチャ

方向はディレクトリ単位で固定する（= 各ディレクトリの writer は常に一方。双方向同期はどこにも無い）。

```
ローカル store: ~/.local/share/claude-knowledge/   ← RAG が見る唯一の場所・記録層の正
├── sessions/          [機械生成・日本語] → outbound（人間用）
├── knowledge/         [機械生成・日本語] → outbound（人間用）
├── lessons-learned/   [機械生成・日本語] → outbound（人間用）
├── index-en/          [機械生成・英語シャドウ] → outbound で vault/.index-en/ へ（下記参照）
└── vault/             [人間領域ミラー] ← inbound（読み取り専用扱い。Claude は書き換えない）

[記録層]  hooks（knowledge-distill / remember / auto-promote）→ store の機械領域に書いて責務完了
[配送層]  rsync -a store/{sessions,knowledge,lessons-learned} → /mnt/c/Users/<user>/Obsidian/
          rsync -a store/index-en/ → /mnt/c/.../Obsidian/.index-en/   ← ドットフォルダ
[取込層]  rsync -a --delete /mnt/c/.../Obsidian/ → store/vault/
          （sessions/knowledge/lessons-learned と .index-en を除外）
[共有取込] rsync -a --ignore-existing vault の機械領域（.index-en 含む）→ store の機械領域
          （他コンテナが生成した session/knowledge/英語カードの「追加のみ」取込。既存ファイルは上書きしない）
```

**英語カードの共有について**: vault はマシン間の唯一の交換ハブなので、英語カードも vault 経由で
共有しないと「他マシンの経験が自マシンの索引に入らない」（再英訳は N 倍コスト + ドリフトで不採用）。
置き場は **`.index-en/`（ドットフォルダ）**とする：

- Obsidian はドットフォルダを UI・検索・グラフから完全に無視する → 全デバイスで設定不要のまま不可視
- pCloud 同期はただのファイルとして運ぶ → 共有取込で全マシンの index-en/ が合流する
- 翻訳は生成元マシンの蒸留時に**1回だけ**。他マシンは共有取込で受け取るのみ
- store 側は `index-en/`（ドットなし）を維持する。knowledge-rag のスキャナが隠しディレクトリを
  スキップする可能性への防御で、ドットへの載せ替えは rsync の宛先指定のみで行う

- 配送・取込とも冪等な一方向 rsync。機械生成ファイル名はユニーク（日付-transcriptID-プロジェクト）
  なので衝突なし、状態管理テーブル不要
- 共有取込により vault が**追記専用の交換ハブ**になり、複数コンテナの知識が全コンテナの RAG に合流する。
  ファイル単位では writer は常に生成元コンテナ1つ（`--ignore-existing` が保証）なので疎結合原則は崩れない
- 配送層・取込層は systemd user timer（各コンテナ、15分目安）。実装は将来自由に差し替え可
  （rclone copy 版 = 純 Linux 環境用の保険。git push 版も可）
- 記録層の失敗要因は Ollama のみに絞られる → `pcloud` reason のキューは廃止

## 実施手順

### Step 0: Windows 側の前提確認（手動）

- pCloud アプリで**仮想ドライブ P: ではなく Sync 機能**を使用していることを確認
  （`C:\Users\<user>\Obsidian` ⇔ `pCloud/obsidian` の Sync ペア）
- WSL から `/mnt/c/Users/<user>/Obsidian/` の読み書き確認

### Step 1: 記録層のローカル化

- store パス設定ファイル `~/.local/share/claude-startup/store-path`（マシン固有・git 管理外）を導入
- `hooks/knowledge-distill.sh`（OUTPUT_DIR）、`hooks/knowledge-auto-promote.sh`、
  `skills/remember/SKILL.md`、`scripts/generate-obsidian-index.sh` を store 参照に書き換え
- `mountpoint -q` ガードを削除（ローカル書き込みは失敗しない前提。ディスク満杯等は log_error のみ）
- ファイル名の NTFS サニタイズ（プロジェクト名は cwd basename 由来のため `: ? * " < > |` を置換）
  — 配送層で置換するのではなく**記録層で最初から NTFS 安全な名前にする**（層間の暗黙依存を作らない）

### Step 2: キュー簡素化

- `pcloud` reason のキュー・通知・drain 分岐を削除（`knowledge-distill.sh`, `check-queue.sh`）
- `ollama` / `pending` キューは存続。既存滞留分は移行時に一括 drain（store 書き込みで再処理）

### Step 3: 配送層・取込層の新設

- `scripts/obsidian-sync.sh` を新設（out/in を1スクリプトに同居させ、除外リストを1箇所で管理）:
  - outbound: `rsync -a "$STORE"/{sessions,knowledge,lessons-learned} "$VAULT"/`
  - inbound: `rsync -a --delete --exclude={sessions,knowledge,lessons-learned} "$VAULT"/ "$STORE/vault/"`
- systemd user unit + timer のテンプレートを `templates/systemd/obsidian-sync.{service,timer}` に追加
- setup モジュール（`setup/500-pcloud.sh` を改名・役割変更）で store-path / vault-path の設定と
  timer の enable を行う

### Step 4: RAG 取り込み経路の一本化【設計判断ポイント】

現状は distill 時の API 登録（`knowledge-distill-register.sh`）。store 導入後は
**documents_dir = store ルート + watch_for_changes 方式への一本化を推奨**:

- 原則が「store に置かれたものは全部インデックスされる」に単純化され、
  vault/（人間ノート）も機械生成分も同一経路で検索に載る
- `config.yaml` の category_mappings はパスベースなのでそのまま機能（`vault/inbox` 等の追加のみ）
- API 登録との併用は二重登録リスクがあるため、`register.sh` は廃止または watch 死活時の
  フォールバックに降格する。**どちらにするかは knowledge-rag の watch 信頼性を検証してから決定**
- lessons-learned の直接 API 登録（CLAUDE.md 記載の運用）は、add_document が documents_dir に
  実ファイルを書く挙動なら現状維持で整合
- **検索言語の正準化（決定 2026-07-05: 英語シャドウノート方式）**: 検索スタック3コンポーネント
  （埋め込み bge-small-en / BM25 / reranker ms-marco）はすべて英語前提。多言語埋め込みへの切替は
  埋め込みしか直らないため、**索引対象を英語に正準化する**方針とする：
  - 蒸留時に1プロンプトで日英を同時出力し、英語版は `store/index-en/` へ。配送層が vault の
    `.index-en/`（ドットフォルダ = Obsidian からは不可視）に載せ、共有取込で全マシンに合流させる
  - `config.yaml` の exclude_patterns で日本語機械領域（sessions/knowledge/lessons-learned）を索引から除外
    → 索引 = 「index-en/（英語）+ vault/（人間ノート）」。同一内容の日英二重ヒットを防ぐ
  - クエリ側も英語に揃える: CLAUDE.md に「search_knowledge のクエリは英語で書く」を追記。
    auto-recall（[17](17-cross-project-recall.md)）は ASCII 技術語抽出でクエリ生成（翻訳レイテンシなし）
  - 人間の日本語 vault ノートの埋め込み品質は既知の弱点として許容（量が少ない・inbox 処理は直接読む）。
    将来必要なら取込層に非同期英訳パス（既存キュー基盤流用）を追加
  - 保険: 移行前に A/B 評価（実ノート20件 ×「日本語+multilingual-e5」vs「英語+bge-small-en」×
    現実的クエリ10本）で確証を取ってから確定してもよい。多言語埋め込み切替はフォールバック案として保持

### Step 5: 既存データの移行（初回のみ）

既存のセッションログ・知識は3種類あり、扱いが異なる：

1. **蒸留済みノート（現 pCloud 上の sessions/ knowledge/ lessons-learned/）— 初期シード必須**
   - store は空で始まるため、シードしないと RAG・auto-promote が過去の知識を全て失う
   - 手順: 取込層と同じ経路で一度だけ実行
     `rsync -a "$VAULT"/{sessions,knowledge,lessons-learned} "$STORE"/`
   - シード後、outbound は同一内容の no-op になる（--delete を使わないため削除事故の経路なし）
   - Windows 側 Sync が完了している（= /mnt/c にクラウドの全ファイルが実体化している）ことを
     シード前に確認する。pCloud の仮想プレースホルダ状態でコピーしないこと
2. **滞留キュー（pending / pcloud reason）— 移行時に一括 drain**
   - 書き込み先が store に変わった状態で drain すれば通常経路で回収される（Step 2 と同時）
3. **未蒸留の過去 transcript（~/.claude/projects/、フック導入前・dead-letter 落ち分）— オプション**
   - 移行のブロッカーにしない。必要になったら `scripts/distill-backfill.sh`（transcript を列挙し
     `knowledge-distill.sh` に順次流すバッチ、Ollama 実行時間との相談）で後日回収可能
   - dead-letter に残る transcript_not_found 分は回収不能として破棄

### Step 6: ドキュメント追随

- `docs/pcloud-rclone-setup.md` → 新構成の手順に改訂（rclone mount 手順は付録へ）
- `DESIGN.md` のツール連携図に 記録層/配送層/取込層 を反映
- 12番チェックリスト: 「rclone OAuth / mount 常駐化」→「pCloud Sync ペア確認 + store/vault パス設定」
- 900-verify（10番）: store 書き込み可否・timer 稼働・vault 到達性のチェックを追加

## 既知の制限（v1 で許容）

- **人間が vault 側で機械生成ノート（knowledge/ 等）を直接編集した場合、その編集は取り込まれない**
  （機械領域は outbound 専用のため）。運用回避: 編集したいノートは人間領域へコピー/移動してから編集。
  双方向が本当に必要になったら mtime ベースの調停を別途設計する（安易に rsync 双方向にはしない）

## 受け入れ基準

- [ ] rclone mount なし・pCloud アプリ停止中でも、蒸留・RAG 登録・自動昇格が完走する
- [ ] 配送層 timer 稼働時、セッション終了後 15 分以内に Obsidian（スマホ）からノートが見える
- [ ] Obsidian で書いた人間ノートが、取込層経由で `search_knowledge` にヒットする
- [ ] **移行前の既存セッションノートが移行後も `search_knowledge` にヒットする**（初期シードの検証）
- [ ] 他コンテナで生成した新規セッションが、共有取込（`.index-en/` の英語カード含む）経由で
      自コンテナの RAG にヒットする（= 再英訳なしで索引が全マシン同一内容に収束する）
- [ ] `.index-en/` が Obsidian（Windows/スマホ）の UI・検索・グラフに一切表示されない
- [ ] `pcloud` reason のキューがコード・通知とも存在しない
- [ ] 複数 WSL コンテナ同時運用でファイル欠損・重複インデックスがない

## 影響ファイル

- `hooks/knowledge-distill.sh`, `hooks/knowledge-distill-register.sh`, `hooks/check-queue.sh`,
  `hooks/knowledge-auto-promote.sh`, `hooks/lib/queue.sh`
- `skills/remember/SKILL.md`, `scripts/generate-obsidian-index.sh`
- 新規: `scripts/obsidian-sync.sh`, `templates/systemd/obsidian-sync.{service,timer}`
- `setup/500-pcloud.sh`（役割変更）, `docs/pcloud-rclone-setup.md`, `DESIGN.md`, `TOOLS.md`
- 関連: [16-obsidian-second-brain.md](16-obsidian-second-brain.md)（この基盤の上に載るワークフロー）
