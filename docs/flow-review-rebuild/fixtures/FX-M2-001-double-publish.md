# FX-M2-001 — 二重投稿

- Source: Issue #409 / Issue #410 / MC-001
- Invariant: INV-001
- Test ID: M2-FX-001

## Scenario

同一 review revision に対して、内容や fingerprint が異なる投稿要求が2回発生する。また、既存の投稿済みの印（marker）の中に、別の主体が作成した同種の印が混在している。

## Observable expected result

- 同一 revision への外部書き込みは高々1回である。
- 結果の非決定性を理由に、2回目の書き込みが発生しない。
- 別の主体が作成した印は投稿済み判定に使われず、正しい主体の安定した印だけが再利用判定に使われる。

## Out of scope

- 実行コマンド
- JSON schema
- lock 名、post key 名、関数名
