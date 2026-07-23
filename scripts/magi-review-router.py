#!/usr/bin/env python3
"""Route a review diff to MAGI, Codex, or manual confirmation."""

import argparse
import hashlib
import json
import re
import shlex
import sys
from pathlib import Path


SCHEMA_VERSION = "magi-review-route/v1"
DECISION_SOURCE = "path_metadata"
CODE_EXTENSIONS = frozenset((
    ".c", ".cc", ".cpp", ".cs", ".go", ".java", ".js", ".jsx", ".kt", ".mjs",
    ".php", ".py", ".rb", ".rs", ".sh", ".swift", ".ts", ".tsx",
))
META_EXTENSIONS = frozenset((".json", ".md", ".yaml", ".yml"))
IMPLEMENTATION_ADJACENT_UNKNOWN_BASENAMES = frozenset((
    "dockerfile", "makefile", "rakefile", "gemfile", "procfile", "justfile",
))
IMPLEMENTATION_ADJACENT_UNKNOWN_EXTENSIONS = frozenset((
    ".css", ".dockerfile", ".hcl", ".html", ".less", ".sass", ".scss", ".sql", ".tf", ".tfvars",
))
DIFF_HEADER = re.compile(r"^diff --git a/(.+) b/(.+)$")
BINARY_HEADER = re.compile(r"^Binary files a/(.+) and b/(.+) differ$")


def sha256_bytes(value):
    return hashlib.sha256(value).hexdigest()


def strip_git_prefix(path):
    path = path.strip()
    if path in {"/dev/null", "dev/null"}:
        return None
    if path.startswith(("a/", "b/")):
        path = path[2:]
    if path in {"/dev/null", "dev/null", ""}:
        return None
    return path


def add_path(paths, seen, path):
    path = strip_git_prefix(path)
    if path is None or path in seen:
        return
    seen.add(path)
    paths.append(path)


def parse_diff_header(line):
    try:
        tokens = shlex.split(line[len("diff --git "):])
    except ValueError:
        tokens = []
    if len(tokens) >= 2:
        return tokens[0], tokens[1]
    match = DIFF_HEADER.match(line)
    if match:
        return match.group(1), match.group(2)
    return None, None


def parse_metadata_paths(diff_text):
    paths = []
    seen = set()
    in_hunk = False
    for line in diff_text.splitlines():
        if line.startswith("diff --git "):
            in_hunk = False
            old_path, new_path = parse_diff_header(line)
            if old_path:
                add_path(paths, seen, old_path)
            if new_path:
                add_path(paths, seen, new_path)
            continue
        if line.startswith("@@ "):
            in_hunk = True
            continue
        if in_hunk:
            continue
        if line.startswith("+++ "):
            add_path(paths, seen, line[4:].split("\t", 1)[0])
            continue
        if line.startswith("rename from "):
            add_path(paths, seen, line[len("rename from "):])
            continue
        if line.startswith("rename to "):
            add_path(paths, seen, line[len("rename to "):])
            continue
        match = BINARY_HEADER.match(line)
        if match:
            add_path(paths, seen, match.group(1))
            add_path(paths, seen, match.group(2))
    return paths


def path_parts(path):
    return [part for part in path.replace("\\", "/").split("/") if part]


def is_skill_reference_path(parts):
    return len(parts) >= 3 and parts[0] == "skills" and parts[2] == "references"


def is_agent_markdown(parts):
    return len(parts) == 2 and parts[0] == "agents" and parts[1].lower().endswith(".md")


def is_meta_path(path):
    lowered = path.lower()
    parts = path_parts(lowered)
    basename = parts[-1] if parts else lowered
    suffix = Path(lowered).suffix
    if lowered.startswith("docs/traceability/"):
        return True
    if "accepted_tradeoffs" in lowered or "accepted-tradeoffs" in lowered:
        return True
    if is_skill_reference_path(parts):
        return True
    if is_agent_markdown(parts):
        return True
    if basename in {"agents.md", "claude.md", "skill.md"}:
        return True
    return suffix in META_EXTENSIONS


def is_code_path(path):
    return Path(path.lower()).suffix in CODE_EXTENSIONS


def is_implementation_adjacent_unknown_path(path):
    lowered = path.lower()
    basename = Path(lowered).name
    return (
        basename in IMPLEMENTATION_ADJACENT_UNKNOWN_BASENAMES
        or Path(lowered).suffix in IMPLEMENTATION_ADJACENT_UNKNOWN_EXTENSIONS
    )


def is_magi_infrastructure_path(path):
    lowered = path.lower()
    return (
        lowered.startswith("skills/magi-")
        or lowered.startswith("skills/magi-common/")
        or lowered.startswith("scripts/magi-")
        or lowered.startswith("scripts/tests/test_magi_")
        or lowered.startswith("scripts/test-magi-")
    )


def is_magi_infrastructure_script(path):
    lowered = path.lower()
    return lowered.startswith("scripts/magi-") and is_code_path(lowered)


def is_magi_infrastructure_test(path):
    lowered = path.lower()
    return (
        lowered.startswith("scripts/tests/test_magi_")
        or lowered.startswith("scripts/test-magi-")
    ) and is_code_path(lowered)


def classify_paths(paths):
    summary = {
        "total_paths": len(paths),
        "paths": paths,
        "code_paths": [],
        "meta_paths": [],
        "unknown_paths": [],
        "magi_infrastructure_paths": [],
        "magi_infrastructure_scripts": [],
        "magi_infrastructure_tests": [],
    }
    for path in paths:
        if is_code_path(path):
            summary["code_paths"].append(path)
        elif is_meta_path(path):
            summary["meta_paths"].append(path)
        else:
            summary["unknown_paths"].append(path)
        if is_magi_infrastructure_path(path):
            summary["magi_infrastructure_paths"].append(path)
        if is_magi_infrastructure_script(path):
            summary["magi_infrastructure_scripts"].append(path)
        if is_magi_infrastructure_test(path):
            summary["magi_infrastructure_tests"].append(path)
    summary["code_count"] = len(summary["code_paths"])
    summary["meta_count"] = len(summary["meta_paths"])
    summary["unknown_count"] = len(summary["unknown_paths"])
    summary["magi_infrastructure_count"] = len(summary["magi_infrastructure_paths"])
    return summary


def route_from_summary(summary):
    code_count = summary["code_count"]
    meta_count = summary["meta_count"]
    unknown_count = summary["unknown_count"]
    total = summary["total_paths"]
    if total == 0:
        return None, 1.0, "empty diff has no changed paths", ["empty_diff"]
    if summary["magi_infrastructure_scripts"] and summary["magi_infrastructure_tests"]:
        return (
            "manual_confirm",
            0.65,
            "MAGI infrastructure implementation and test paths are mixed",
            ["magi_infrastructure_script_test_mix"],
        )
    if code_count == 0:
        implementation_unknown_paths = [
            path for path in summary["unknown_paths"]
            if is_implementation_adjacent_unknown_path(path)
        ]
        if implementation_unknown_paths and meta_count == 0:
            return (
                "magi",
                0.7,
                "implementation-adjacent unclassified paths require MAGI review",
                ["implementation_adjacent_unknown_only"],
            )
        if implementation_unknown_paths:
            return (
                "manual_confirm",
                0.6,
                "implementation-adjacent unclassified paths are mixed with metadata",
                ["implementation_adjacent_unknown_mixed"],
            )
        if unknown_count and meta_count == 0:
            return (
                "manual_confirm",
                0.55,
                "unclassified paths require manual routing confirmation",
                ["unknown_only"],
            )
        return "codex", 0.85, "metadata and documentation paths do not require MAGI", ["codex_meta_only"]
    if meta_count == 0:
        return "magi", 0.85, "implementation code paths dominate the diff", ["code_only"]
    if code_count >= meta_count * 2:
        return "magi", 0.75, "implementation code paths clearly outnumber metadata paths", ["code_dominant"]
    if meta_count >= code_count * 2:
        return "codex", 0.75, "metadata paths clearly outnumber implementation code paths", ["meta_dominant"]
    return "manual_confirm", 0.55, "implementation and metadata paths are balanced", ["balanced_mixed_diff"]


def build_receipt(raw_diff):
    diff_text = raw_diff.decode("utf-8", "replace")
    paths = parse_metadata_paths(diff_text)
    summary = classify_paths(paths)
    route, confidence, reason, matched_rules = route_from_summary(summary)
    diff_hash = sha256_bytes(raw_diff)
    return {
        "schema_version": SCHEMA_VERSION,
        "review_route": route,
        "magi_skipped": route != "magi",
        "reason": reason,
        "fallback": None,
        "confidence": confidence,
        "matched_rules": matched_rules,
        "path_summary": summary,
        "raw_diff_sha256": diff_hash,
        "filtered_diff_sha256": None,
        "decision_source": DECISION_SOURCE,
    }


def parse_args(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("--diff-file", required=True)
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(argv or sys.argv[1:])
    raw_diff = Path(args.diff_file).read_bytes()
    print(json.dumps(build_receipt(raw_diff), ensure_ascii=False, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print("error: %s" % exc, file=sys.stderr)
        raise SystemExit(1)
