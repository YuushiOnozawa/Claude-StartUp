# FX-M2-005 — 大きさ上限の境界

- Source: C2 / MC-005
- Invariant: INV-005
- Test ID: M2-FX-005

## Scenario

diff 行数と chunk 数を、3,200行・8チャンクの境界値およびその直上で与える。

## Observable expected result

- 境界内の入力は処理対象として終端する。
- 境界を超えた入力は、明示的な非完了または拒否として終端する。
- 処理時間、メモリ、生成量が入力超過に伴って無界に増えない。

## Out of scope

- 実行コマンド
- JSON schema
- lock 名、post key 名、関数名
