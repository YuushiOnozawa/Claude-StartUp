# FX-M2-011 — 投稿直前の head 変化

- Source: MC-014 / mining@b289e62 / mining@fdf3b70
- Invariant: INV-011
- Test ID: M2-FX-011

## Scenario

review 開始時に取得した target の head が、確認の途中から外部書き込みの直前までに変化する。

## Observable expected result

- 外部書き込みの直前に最新 head が確認される。
- head の変化を検出した run は、stale result として明示的に非完了で終端する。
- 変化前の revision への外部書き込みや、投稿済みとする誤判定が発生しない。

## Out of scope

- 実行コマンド
- JSON schema
- lock 名、post key 名、関数名
