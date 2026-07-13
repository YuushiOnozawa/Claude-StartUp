# LELIEL impact targets schema

この文書は Feature 5 の `impact-targets/v1`、`candidate-catalog/v1`、`leliel-pretriage-added/v1`、`leliel-skip-decision/v1`、`leliel-pretriage-manifest/v1` の唯一の正本である。F6 はこの schema version と field を参照し、再定義してはならない。

すべての JSON artifact は UTF-8、`ensure_ascii=False`、`sort_keys=True`、区切り `(',', ':')`、末尾改行で直列化する。SHA-256 は直列化し直した値ではなく、明記された raw bytes に対して計算する。配列は以下の規則で安定化する。絶対 path、時刻、PID、環境変数、Codex の自由文は ID や hash の入力にしない。

## `candidate-catalog/v1`

これは private audit directory のみに保存する Codex の eligible set である。

```json
{"schema_version":"candidate-catalog/v1","diff_sha256":"<64 lowercase hex>","candidates":[{"candidate_id":"C-0001","path":"src/a.py","name":"run","kind":"function","language":"python","change_kind":"signature_changed","required":true}]}
```

root field は上記の三つだけ、candidate field は上記の七つだけである。`candidate_id` は path/name/kind の辞書順で `C-0001` から連番、path は repo-relative の安全な slash path、`required` は boolean である。candidate catalog raw canonical bytes の hash が Codex との照合値になる。

## `leliel-pretriage-added/v1`

```json
{"schema_version":"leliel-pretriage-added/v1","candidate_catalog_sha256":"<64 lowercase hex>","additions":[{"candidate_id":"C-0002","selection_reason":"呼出し側の認可分岐に到達するため"}]}
```

root は三 field、entry は二 field の完全一致でなければならない。`candidate_id` は catalog の eligible set に一度だけ存在し、reason は空白以外を含む文字列とする。unknown、duplicate、hash/schema 不一致、余分な field、型不正は **artifact 全体**を不採用にする。JSON 修復や部分採用はしない。

## `impact-targets/v1`

```json
{"schema_version":"impact-targets/v1","input":{"diff_sha256":"<64 lowercase hex>","changed_files":{"added":1,"existing":2,"unparseable":0}},"targets":[{"id":"T-0001","symbol":{"path":"src/a.py","name":"run","kind":"function","language":"python"},"change_kinds":["signature_changed"],"selection_sources":["ADDED","REQUIRED"],"selection_reason":[{"source":"ADDED","code":"codex_selected","detail":"影響するため"},{"source":"REQUIRED","code":"public_contract_changed","detail":"公開契約または互換対象が変更された"}],"caller_context":{"status":"evidence","reason":null,"callers":[{"path":"src/b.py","line":9,"source":"fallback","start_line":4,"end_line":14,"snippet":"...","truncated":false}]}}],"summary":{"required_candidates":1,"added_candidates":1,"legacy_candidates":0,"selected_targets":1,"caller_evidence_targets":1,"caller_skipped_targets":0},"pretriage":{"codex_status":"applied","catalog_sha256":"<64 lowercase hex>"},"leliel_skip":{"skip":false,"reasons":[]}}
```

target identity は `path/name/kind`。target はその辞書順で `T-0001` から採番する。`change_kinds` と `selection_sources` は重複なしの辞書順配列で、source は `REQUIRED`、`ADDED`、`LEGACY_FALLBACK` のいずれか、reason は source ごとに一つである。

`caller_context.status` は `evidence` か `skipped`。後者は callers を空にし、reason を `no_verified_caller`、`definition_deleted_or_unavailable`、`caller_filtered_out` のいずれかにする。caller path は tracked regular file の repo-relative path、source は `codegraph` または `fallback`、snippet は最大 11 行である。単独証拠が 6,000 UTF-8 bytes を超える時だけ truncated を true にする。

`codex_status` は `applied` または `fallback_legacy`。Codex の失敗は selection だけの fail-open であり REQUIRED は除去しない。`leliel_skip` は output context と同じ決定を保持する補助情報で、F6 が文字列推測に用いてはならない。

`impact-context.md` は evidence target だけから決定的に render する。空の場合は 0 byte とする。非空の場合は単一ファイルで `<!-- impact-context-chunk:N -->` を明示区切りにし、target/caller 境界で 4,000--6,000 UTF-8 bytes を目標に分割する。収まる最終 chunk は前段へ併合する。単独 evidence が上限を超える場合は UTF-8 を壊さず snippet を切詰め、caller の `truncated: true` と audit に残す。

## `leliel-pretriage-manifest/v1`

output directory の `manifest.json` は唯一の commit marker であり、次の小さい canonical JSON とする。

```json
{"schema_version":"leliel-pretriage-manifest/v1","generation_id":"generation-<timestamp>-<pid>-<random>","artifacts":{"impact-context.md":{"path":"generation-<timestamp>-<pid>-<random>/impact-context.md","sha256":"<64 lowercase hex>"},"leliel-skip-decision.json":{"path":"generation-<timestamp>-<pid>-<random>/leliel-skip-decision.json","sha256":"<64 lowercase hex>"},"impact-targets.json":{"path":"generation-<timestamp>-<pid>-<random>/impact-targets.json","sha256":"<64 lowercase hex>"}}}
```

root は三 field、artifact entry は `path` と `sha256` の二 field の完全一致である。generation ID は `generation-` で始まり、各 path はその generation 直下の固定成果物名と完全一致する安全な relative path である。hash は各成果物の raw bytes の SHA-256 である。

公開時は output directory の排他 lock を取得し、直下の新しい `generation-<timestamp>-<pid>-<random>/` に `impact-context.md`、`leliel-skip-decision.json`、`impact-targets.json` を全て書き終える。最後に `manifest.json` だけを `os.replace` で原子的に置換する。途中 I/O failure は旧 manifest を変更せず exit 非ゼロとし、未参照 generation は診断用に残す。既存の完成組への再公開と同じ output directory の並行 publish は lock により fail-closed となる。

consumer（`decide-skip`、`render`、F6）は manifest を読み、schema/path を検証してから記載された三成果物を regular non-symlink file として読む。**組の有効性は manifest の全 SHA-256 と各 raw bytes の一致で判定する。** 一つでも不一致、欠落、parse failure があれば途中状態の部品エラーであり、個別成果物や旧世代との混在を採用してはならない。

## `leliel-skip-decision/v1`

```json
{"schema_version":"leliel-skip-decision/v1","impact_targets_sha256":"<64 lowercase hex>","impact_context_sha256":"<64 lowercase hex>","decision":"skip","skip":true,"reasons":["new_files_only","impact_context_empty"]}
```

`impact_targets_sha256` と `impact_context_sha256` は各 input の raw bytes hash である。`new_files_only := changed_files.existing == 0`、`impact_context_empty := context bytes == 0` かつ `caller_evidence_targets == 0`。この二条件のいずれかで skip、reason は上記二値のみをこの順序で保持する。不一致、parse failure、hash/schema failure は正常 skip ではなく部品エラーである。
