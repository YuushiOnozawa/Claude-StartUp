# FX-M2-015 — 成功コードと不正・過大出力

- Source: MC-018 / mining@f11852d / mining@043d009
- Invariant: INV-015
- Test ID: M2-FX-015

## Scenario

外部実行元が exit 0 を返すが、出力が空、不正、許容サイズ超過、または stdout と stderr の混在を含む。

## Observable expected result

- exit 0 だけでは成功と判定されない。
- 空、不正、過大な出力は有界に拒否され、required job は非完了として終端する。
- 不正な出力を理由に、成功や外部投稿へ進まない。

## Out of scope

- 実行コマンド
- JSON schema
- lock 名、post key 名、関数名
