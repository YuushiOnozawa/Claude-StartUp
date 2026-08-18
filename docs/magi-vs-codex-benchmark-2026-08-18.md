# MAGI vs Codex単体 ベンチマーク（2026-08-18）

## 結論

この4 PR の範囲では、ユーザーの「現行MAGIは実運用上かなり機能していないのでは」という疑いは、少なくとも次の2点で支持された。

- BALTHASARの生出力は、意図的なレビュー用fixture・存在しないパス・設計上の好みを大量に指摘し、precisionが低い。
- MELCHIORはCS#362のフィクスチャを含むチャンクで、`ollama-run.sh` の30分呼び出し上限まで処理が終わらず、残りのMELCHIOR/KABU#6計測へ進めなかった。

ただし、MAGI全体を「価値がない」と結論づけるには不十分である。過去のMAGI-HARDでは、CS#376で実際に修正されたプロンプトインジェクション系の問題を検出し、CS#362でもgroundingの実際の行番号不整合を2件補正している。一方、今回のCodex単体はKABU#6でMAGIの掲載・採用に至らなかったURLエンコード問題を拾っており、単一エンジンにも固有の検出価値があった。

したがって、現時点の推奨は「全ペルソナをCodex化」でも「MAGI多様性を無条件に維持」でもない。通常の高速ルートは単一Codexレビューを基本にし、セキュリティ・grounding・大規模変更だけMAGIの対象ペルソナを限定的に追加するハイブリッドが妥当である。

## 方法

- `gh pr diff <n> --repo <repo>` でマージ済みPRの確定diffを取得した。
- 現行MAGI相当のフィルタ（`scripts/magi-diff-filter.sh`）とチャンク分割（400行）を使い、MELCHIOR/BALTHASARの生出力を正規化・Codexゲート前の状態で記録した。
- Ollamaは全て `scripts/ollama-run.sh` 経由で実行した。使用モデルはMELCHIOR=`qwen2.5-coder:7b`、BALTHASAR=`gemma4:e4b-it-qat`。
- CASPERは標準エンジンがHaikuで、Claude quotaを消費するため今回の実測から除外した。したがって今回の「現行MAGI生出力」はMELCHIOR+BALTHASARの測定値である。
- Codexは各PRにつき1回、読み取り専用・敵対的レビューとして実行した。Codexの出力件数も正規化前の候補数である。
- true/falseは、差分、マージ後のコミット、既存レビュー結果、対象コードを突き合わせた近似判定であり、実行時の完全なground truthではない。

## 測定結果

| PR | diff（全体→フィルタ後 / チャンク） | MELCHIOR生候補 | BALTHASAR生候補 | Codex単体 | 既存MAGI-HARD記録 |
|---|---:|---:|---:|---:|---|
| Claude-StartUp #376 | 275→204 / 3 | 14 | 6 | 2 | H0/M2/L1、Codex監査除外24 |
| Claude-StartUp #362 | 1724→1089 / 6 | 0（3/6完了、4チャンク目が30分timeout） | 9 | 4 | H26/M30/L22、Codex監査除外18 |
| kabuAPIMCP #1 | 65→65 / 2 | 1 | 1 | 0 | H0/M0/L0、Codex監査除外13 |
| kabuAPIMCP #6 | 941→941 / 3 | 未完（CS#362のtimeout後は未実行） | 2 | 1 | H1/M1/L1、Codex監査除外53 |

### 生候補の近似監査

| PR | MAGI生候補の監査 | Codex単体の監査 | 代表的な内容 |
|---|---|---|---|
| CS#376 | 20件中、確認できた真の問題0、誤読・設計論19、保留1 | 2件中、既知の残存インジェクションリスク1、設計トレードオフ1 | MAGIは未使用変数・関数シグネチャ・テスト期待値を誤読。Codexは未信頼本文のLLMプロンプト連結を検出。 |
| CS#362 | BALTHASAR 9件は、意図的fixture・存在しないスクリプト・設計論で、確認できた真のPR不具合0。MELCHIORは未完 | 4件中、パス境界外参照と候補探索の早期打切りは妥当性が高い、部分一致は要確認、整数検証は誤り | 大規模fixtureを通常ソースとしてレビューしたことがfalse positiveの主因。 |
| kabu#1 | 2件とも誤検知。環境変数は実際には直後に検証され、引数注入もテスト容易性のための設計 | 0件 | MAGIの設定依存性指摘は、注入可能な引数を見落とした設計論。 |
| kabu#6 | BALTHASAR 2件とも設計論・fixture構造論で、確認できた真のPR不具合0 | URLパスへsymbolを未エンコードで埋め込む問題1件。API仕様の確認は必要だが、予約文字入力への回帰テストがなく妥当性が高い | MAGIは大規模差分からテスト配列と型ファイルの凝集度だけを指摘し、実行経路の入力境界を拾わなかった。 |

### 既存レビューとの突合

- CS#376のMAGI-HARDのMEDIUM 2件は、`hooks/knowledge-auto-promote.sh` の入力境界・delimiter衝突に関するもので、後続コミットでサニタイズ等が追加された。今回のMELCHIOR/BALTHASAR生出力はこの問題を正確には再現できなかった。
- CS#362のMAGI-HARDは78件を出し、Codex監査で18件が除外された。fixture内の意図的脆弱性や、実在しない `scripts/lib/*.sh` を本番コードとして扱った候補が多く、precisionの悪化が明確だった。grounding上の行番号補正2件は実際に確認されたが、PRの機能不具合とは別の運用上の不整合である。
- KABU#1ではMAGI-HARDも重大度別0件で、今回のCodex単体0件と一致した。人手コメントでテスト説明の修正はあったが、MAGI/Codexの検出ではない。
- KABU#6のMAGI-HARDのHIGH（tokenManager）とMEDIUM（GET query/body）は、投稿後にユーザーがwaive/rejectしており、少なくとも採用された不具合ではない。今回のCodexのURLエンコード指摘はそれらとは別の、未確認のユニーク候補である。

## 観察

### 1. 「多様性」以前に運用層がボトルネック

今回のBALTHASARはモデル多様性の恩恵を測る以前に、fixtureを本番コードとして扱い、Codexゲート前に候補を膨らませた。MELCHIORはCS#362で30分上限に到達した。したがって現状の評価軸は「複数モデルのrecall」より先に、対象ファイル選別、fixture分離、チャンク境界、タイムアウト、出力の正規化を直す必要がある。

### 2. MAGIはゼロではないが、常時実行の費用対効果が悪い

CS#376の実問題やCS#362のgrounding不整合という実績はあるため、MAGIの検出能力を全否定する根拠にはならない。しかし今回の生候補は、確認できる問題よりも誤検知・設計論が大幅に多く、さらに大差分で完走性も悪い。通常PRでMELCHIOR/BALTHASAR/CASPERを逐次実行する構成は、少なくとも現状のままではquota・時間に見合わない。

### 3. Codex単体はprecisionと入力境界のレビューで有望

KABU#1では無駄な指摘を出さず、KABU#6ではMAGIが拾わなかった入力境界の候補を出した。CS#376でも既知の残存インジェクションリスクを指摘した。ただしCS#362の4件には誤った整数検証指摘も含まれ、Codex単体も無監査で真実扱いできない。

## 推奨する次の構成

1. `dev-flow-fast` の標準レビューは、単一Codexの敵対的レビュー1回＋明示的なJSON/位置検証を基本にする。
2. MAGIは削除せず、セキュリティ変更、grounding/レビュー基盤変更、大規模差分に限定した追加検査へ落とす。ペルソナは全員ではなく、目的に対応するものだけを選ぶ。
3. MAGIを残す前に、fixture・referencesの除外または明示的なテストデータ扱い、タイムアウト時の中断、候補の重複排除、Codex監査の前段での明らかな設計論除去を行う。
4. 次の検証では、既知バグを埋め込んだ固定ベンチマークと同一プロンプト条件で、少なくとも各PRを2回以上実行する。今回のn=4、かつMAGIのMELCHIOR/BALTHASARのみという条件では、recallの統計的比較はできない。

## 制約・再現情報

- サンプルはマージ済み4 PRのみで、true/falseの判定はマージ後経緯を利用した近似である。
- 過去のMAGI-HARD記録は6ペルソナ＋normalizer/Codex監査後の集計、今回のMAGI測定はMELCHIOR/BALTHASARの監査前生出力であり、同一層ではない。
- Codexは各PR一括1回、MAGIはフィルタ後チャンク単位で逐次実行したため、入力条件とコンテキスト長が異なる。
- MELCHIORのCS#362は3チャンク完了後、4チャンク目で約30分のOllama呼び出し上限に達した。KABU#6のMELCHIORはこの時点で未実行である。
- kabuAPIMCPは `/tmp/magi-vs-codex-benchmark-2026-08-18/kabuAPIMCP` に読み取り専用でcloneし、書き込み・commit・pushは行っていない。
- 生diff、プロンプト、レビュー出力は `/tmp/magi-vs-codex-benchmark-run-2026-08-18-b` および `...-m` に保存した。
