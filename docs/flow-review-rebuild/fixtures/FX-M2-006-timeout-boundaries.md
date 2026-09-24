# FX-M2-006 — timeout 境界

- Source: C3–C6 / MC-006–MC-009
- Invariant: INV-006
- Test ID: M2-FX-006

## Scenario

次の4種類の処理について、それぞれの境界で応答しない入力と、境界を超える入力を与える。

| 処理 | 境界 | 出典 |
|---|---|---|
| ローカル LLM 実行 | 180秒 | C3 / MC-006 |
| 外部 API 呼び出し | 60秒 | C4 / MC-007 |
| 補助 executor（Claude/Haiku 相当） | 900秒 | C5 / MC-008 |
| Codex 実行 | 600秒 | C6 / MC-009 |

ローカル LLM 実行は v1 では unavailable stub のため、この行は該当 executor の有効化時に適用する（境界値は保持する）。

外部 API 呼び出しでは、応答を受け取る前に60秒の境界で timeout させる。この時点ではリクエストが相手に届いたか分からない。

## Observable expected result

- 各処理が定められた上限内で終端する。
- timeout は成功として扱われず、`timed_out` または `unavailable` 相当の結果が観測できる。
- timeout 後に子プロセスや排他資源が次の run を塞がない。
- 外部 API 呼び出しのこのケースは `posted_unknown` 相当で保持し、自動再投稿しない。再判定は同じ stable marker の検索だけで行う。
- リクエストを送る前に失敗した場合だけは未投稿が確定し、再試行してよい。このケース（送信後かどうか不明）とは区別する。

## Out of scope

- 実行コマンド
- JSON schema
- lock 名、post key 名、関数名
