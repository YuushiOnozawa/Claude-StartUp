#!/usr/bin/env bash
# fast 分岐から review-post / GitHub mutation へ到達する辺がないことを検査する。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DISPATCH_FILE="$REPO_ROOT/skills/flow-common/references/review-dispatch.md"

usage() {
  echo "usage: check-review-fast-no-post.sh [--dispatch-file FILE] [--hard-reference FILE]" >&2
  exit 2
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --dispatch-file) [[ "$#" -ge 2 ]] || usage; DISPATCH_FILE="$2"; shift 2 ;;
    --hard-reference) [[ "$#" -ge 2 ]] || usage; HARD_REFERENCE_FILE="$2"; shift 2 ;;
    *) usage ;;
  esac
done
[[ -r "$DISPATCH_FILE" ]] || { echo "dispatch reference を読めません" >&2; exit 2; }
: "${HARD_REFERENCE_FILE:=$REPO_ROOT/skills/dev-flow-fast/references/codex-review-hard.md}"
[[ -r "$HARD_REFERENCE_FILE" ]] || { echo "hard reference を読めません" >&2; exit 2; }

python3 - "$REPO_ROOT" "$DISPATCH_FILE" "$HARD_REFERENCE_FILE" <<'PY'
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1]).resolve()
dispatch = pathlib.Path(sys.argv[2]).resolve()
hard_reference = pathlib.Path(sys.argv[3]).resolve()
hard_reference_rel = pathlib.Path("skills/dev-flow-fast/references/codex-review-hard.md")
text = dispatch.read_text(encoding="utf-8")
headings = list(re.finditer(r"^##\s+(.+?)\s*$", text, re.M))
fast = next((m for m in headings if m.group(1).strip() == "fast 正規化"), None)
hard = next((m for m in headings if m.group(1).strip() == "hard 正規化と GitHub 投稿"), None)
if fast is None or hard is None or fast.start() >= hard.start():
    print("fast/hard branch boundary を検出できません", file=sys.stderr)
    sys.exit(2)

queue = [(dispatch, text[fast.end():hard.start()])]
seen = {dispatch}
index = 0
while index < len(queue):
    path, body = queue[index]
    index += 1
    refs = set()
    for line in body.splitlines():
        # 文書参照は Read/load 指示、shell は実行コマンド上の path だけを辺にする。
        if re.search(r"\bRead\b|読み込|load", line, re.I):
            refs.update(re.findall(r"(?:skills|scripts)/[A-Za-z0-9_.//-]+\.md", line))
        if re.search(r"(?:^|[\s;&|])(?:bash|sh|source|exec)(?=[\s\"']|$)", line):
            refs.update(re.findall(r"(?:skills|scripts)/[A-Za-z0-9_.//-]+\.sh", line))
    for ref in re.findall(r"/(magi|codex)-fast\b", body):
        refs.add(f"skills/{ref}-fast/SKILL.md")
    for ref in sorted(refs):
        target = hard_reference if pathlib.Path(ref) == hard_reference_rel else (root / ref).resolve()
        try:
            target.relative_to(root)
        except ValueError:
            continue
        if target == dispatch or target in seen or not target.is_file():
            continue
        seen.add(target)
        body = target.read_text(encoding="utf-8", errors="replace")
        if target == hard_reference:
            # fast が再利用する hard の節だけを allowlist 化する。hard 全体を
            # 除外しないため、再利用節に投稿 edge が混入したら検出する。
            allowed_sections = {
                "ステップ 1: diff の取得",
                "ステップ 3: self-tamper 判定",
                "ステップ 4: Codex companion の解決",
                "ステップ 5: 5ペルソナの逐次 blind 呼び出し",
                "ステップ 6: CASPER 呼び出し（共通契約）",
                "ステップ 8: findings table 構築",
            }
            headings = list(re.finditer(r"^##\s+(.+?)\s*$", body, re.M))
            chunks = []
            for i, heading in enumerate(headings):
                if heading.group(1).strip() in allowed_sections:
                    end = headings[i + 1].start() if i + 1 < len(headings) else len(body)
                    chunks.append(body[heading.start():end])
            body = "\n".join(chunks)
        queue.append((target, body))

for path, body in queue:
    forbidden = []
    # `execution-budget.sh` などの phase 名・CLI usage の文字列は辺ではない。
    # 実行経路を示す slash/path 参照だけを forbidden edge として扱う。
    if re.search(r"/review-post\b|review-post\.(?:md|sh)\b|scripts/review[-_]post\b", body, re.I):
        forbidden.append("review-post")
    if re.search(r"\bgh\s+api\b[^\n]*\b-X\s+(?:POST|PATCH|PUT|DELETE)\b", body, re.I):
        forbidden.append("gh-api-mutation")
    if re.search(r"\bgh\s+pr\s+(?:comment|review)\b", body, re.I):
        forbidden.append("gh-pr-mutation")
    if forbidden:
        print(f"禁止 edge: {path}: {', '.join(sorted(set(forbidden)))}", file=sys.stderr)
        sys.exit(1)

fast_body = text[fast.end():hard.start()]
if not re.search(r"post_state\s*=\s*not_applicable|post_state=not_applicable", fast_body):
    print("fast branch に post_state=not_applicable の固定がありません", file=sys.stderr)
    sys.exit(1)
print(f"PASS: fast branch reachable files={len(queue)}; post/mutation edges=0")
PY
