#!/usr/bin/env python3
"""Build and safely publish the MAGI hard-review plan."""
import argparse
import datetime
import json
import os
import re
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

MAX_INPUT = 16 * 1024 * 1024
MAX_RESPONSE = 512 * 1024
SHA1 = re.compile(r"^[0-9a-f]{40}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
JAPANESE = re.compile(r"[\u3040-\u30ff]")
MARKER = re.compile(r"^<!-- magi-finding: [A-Za-z0-9][A-Za-z0-9._-]*@[0-9a-f]{40} -->$")


class InputError(Exception):
    pass


def canonical(value):
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"),
                       allow_nan=False) + "\n").encode("utf-8")


def reject_symlinks(path):
    path = Path(path).absolute()
    current = Path(path.anchor)
    for part in path.parts[1:]:
        current /= part
        try:
            info = os.lstat(current)
        except FileNotFoundError:
            break
        if stat.S_ISLNK(info.st_mode):
            raise InputError("path contains a symlink component")


def read_regular(path, limit=MAX_INPUT):
    reject_symlinks(path)
    try:
        fd = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
    except OSError as exc:
        raise InputError("input must be a regular file") from exc
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_size > limit:
            raise InputError("input is not a permitted regular file")
        data = b""
        while len(data) <= limit:
            chunk = os.read(fd, min(65536, limit + 1 - len(data)))
            if not chunk:
                return data
            data += chunk
        raise InputError("input exceeds byte limit")
    finally:
        os.close(fd)


def load_json(path, limit=MAX_INPUT):
    try:
        value = json.loads(read_regular(path, limit).decode("utf-8", "strict"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise InputError("invalid JSON") from exc
    if not isinstance(value, dict):
        raise InputError("JSON root must be an object")
    return value


def private_dir(path):
    path = Path(path).absolute()
    reject_symlinks(path)
    if not path.is_dir():
        raise InputError("parent must be a directory")
    if stat.S_ISLNK(os.lstat(path).st_mode):
        raise InputError("parent must not be a symlink")
    return path


def atomic_write(path, data):
    path = Path(path)
    parent = private_dir(path.parent)
    reject_symlinks(path)
    fd, tmp = tempfile.mkstemp(prefix="." + path.name + ".", suffix=".tmp", dir=parent)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "wb") as handle:
            handle.write(data); handle.flush(); os.fsync(handle.fileno())
        os.replace(tmp, path)
        dfd = os.open(parent, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
        try: os.fsync(dfd)
        finally: os.close(dfd)
    except Exception:
        try: os.unlink(tmp)
        except OSError: pass
        raise


def need(condition, message):
    if not condition:
        raise InputError(message)


def validate_plan(plan):
    need(plan.get("schema_version") == "review-plan/v1", "invalid review plan schema")
    policy = plan.get("run_policy")
    need(isinstance(policy, dict) and policy.get("workflow") == "hard", "hard workflow is required")
    need(policy.get("anchor_policy") == "pr" and isinstance(policy.get("head_sha"), str)
         and SHA1.fullmatch(policy["head_sha"]), "invalid PR head_sha")
    need(isinstance(plan.get("items"), list) and isinstance(plan.get("summary"), dict), "invalid review plan")
    for item in plan["items"]:
        need(isinstance(item, dict), "invalid review item")
        need(isinstance(item.get("id"), str) and isinstance(item.get("title"), str)
             and isinstance(item.get("body"), str), "invalid review item text")
        need(item.get("display_state") in {"postable", "needs_human"}, "item is not postable")
        need(item.get("needs_human") is (item["display_state"] == "needs_human"), "invalid needs_human state")
        anchor = item.get("anchor")
        if anchor is not None:
            need(isinstance(anchor, dict) and isinstance(anchor.get("path"), str)
                 and isinstance(anchor.get("line"), int) and anchor["line"] > 0
                 and anchor.get("side") in {"LEFT", "RIGHT"}
                 and anchor.get("head_sha") == policy["head_sha"], "invalid review anchor")
        need(not any(v.get("verdict") == "false_positive" for v in item.get("verdicts", [])
                     if isinstance(v, dict)), "annotated false positive is not postable")
    for item in plan.get("excluded_findings", []):
        need(isinstance(item, dict), "invalid excluded finding")


def translation_for(translations, identifier, title, body):
    if translations is not None and identifier in translations:
        value = translations[identifier]
        need(isinstance(value, dict) and isinstance(value.get("title_ja"), str)
             and isinstance(value.get("body_ja"), str) and value["title_ja"] and value["body_ja"],
             "invalid translation")
        need("<!--" not in value["title_ja"] and "<!--" not in value["body_ja"], "marker in translation")
        need(not JAPANESE.search(body), "translation supplied for native text")
        return value["title_ja"], value["body_ja"], "translated"
    if JAPANESE.search(body):
        return title, body, "native"
    return title, body, "pending"


def build(args):
    plan = load_json(args.review_plan)
    validate_plan(plan)
    translations = load_json(args.translations) if args.translations else None
    if translations is not None:
        need(all(isinstance(k, str) for k in translations), "invalid translations")
    sha = plan["run_policy"]["head_sha"]
    entries = []
    for item in plan["items"]:
        title, body, status = translation_for(translations, item["id"], item["title"], item["body"])
        marker = "<!-- magi-finding: %s@%s -->" % (item["id"], sha)
        need(MARKER.fullmatch(marker), "invalid finding id")
        warning = "⚠ 要人判断" if item["needs_human"] else ""
        if status == "pending":
            warning = "⚠ 要人判断（未翻訳）"
            print("warning: %s is pending translation" % item["id"], file=sys.stderr)
        if warning:
            title = warning + " — " + title
            body = warning + "\n\n" + body
            if status == "pending":
                body += "\n\nEnglish body"
        scope = "inline" if item["anchor"] else "pr"
        anchor = {"path": item["anchor"]["path"], "line": item["anchor"]["line"],
                  "side": item["anchor"]["side"], "commit_id": sha} if scope == "inline" else None
        entries.append({"id": item["id"], "marker": marker, "severity": item.get("severity"),
                        "personas": item.get("personas", []), "source_ids": item.get("source_ids", []),
                        "title_ja": title, "body_ja": body.rstrip() + "\n\n" + marker,
                        "anchor": anchor, "scope": scope, "needs_human": bool(item["needs_human"]),
                        "translation_status": status})
    summary = plan["summary"]
    excluded = plan.get("excluded_findings", [])
    details = ""
    if excluded:
        rows = "\n".join("- %s: %s (%s)" % (x.get("id", ""), x.get("reason_ja", ""), x.get("raw_sha256", "")) for x in excluded)
        details = "\n<details><summary>除外された finding</summary>\n\n%s\n</details>" % rows
    needs = [x["id"] for x in entries if x["needs_human"]]
    summary_body = ("<!-- magi-summary: @%s -->\n" % sha + "## MAGI hard review\n"
                    + "raw_counts: %s\ngrouped_counts: %s\n" % (json.dumps(summary.get("raw_counts", {}), ensure_ascii=False, sort_keys=True), json.dumps(summary.get("grouped_counts", {}), ensure_ascii=False, sort_keys=True))
                    + "needs_human: %s\naudit: %s%s" % (", ".join(needs) or "none", plan.get("audit", {}).get("status", "unknown"), details))
    output = {"schema_version": "post-plan/v1", "head_sha": sha, "summary_body": summary_body, "entries": entries}
    atomic_write(args.output, canonical(output))


def gh_call(gh, argv, timeout=30):
    try:
        result = subprocess.run([gh] + argv, capture_output=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise RuntimeError("gh invocation failed") from exc
    raw = result.stdout
    if len(raw) > MAX_RESPONSE:
        raise RuntimeError("gh response too large")
    try:
        decoded = raw.decode("utf-8", "strict")
    except UnicodeDecodeError as exc:
        raise RuntimeError("gh response is not UTF-8") from exc
    return result.returncode, decoded, result.stderr.decode("utf-8", "replace")[:4096]


def append_result(path, value):
    path = Path(path)
    private_dir(path.parent); reject_symlinks(path)
    try:
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_APPEND | getattr(os, "O_NOFOLLOW", 0), 0o600)
        with os.fdopen(fd, "a", encoding="utf-8") as handle:
            handle.write(json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n"); handle.flush(); os.fsync(handle.fileno())
    except OSError as exc:
        raise RuntimeError("results append failed") from exc


def parse_response(text):
    try: return json.loads(text)
    except (json.JSONDecodeError, TypeError): return None


def post(args):
    plan = load_json(args.post_plan)
    need(plan.get("schema_version") == "post-plan/v1" and SHA1.fullmatch(plan.get("head_sha", "")), "invalid post plan")
    need(isinstance(plan.get("entries"), list) and isinstance(plan.get("summary_body"), str), "invalid post plan")
    if args.dry_run:
        print(json.dumps(plan, ensure_ascii=False, sort_keys=True, indent=2)); return
    gh = args.gh
    repo_path = "repos/%s" % args.repo
    rc, out, _ = gh_call(gh, ["api", "%s/pulls/%s" % (repo_path, args.pr), "--jq", ".head.sha"])
    if rc or out.strip() != plan["head_sha"]:
        if rc: raise RuntimeError("HEAD lookup failed")
        raise SystemExit(3)
    comments = []
    for endpoint in ("issues/%s/comments" % args.pr, "pulls/%s/comments" % args.pr):
        rc, out, _ = gh_call(gh, ["api", "%s/%s" % (repo_path, endpoint), "--method", "GET",
                                  "--paginate", "--slurp", "-F", "per_page=100"])
        if rc: continue
        value = parse_response(out)
        if isinstance(value, list): comments.extend(value if not (value and isinstance(value[0], list)) else sum(value, []))
    markers = {entry["marker"] for entry in plan["entries"] if any(entry["marker"] in str(c.get("body", "")) for c in comments if isinstance(c, dict))}
    summary_marker = "<!-- magi-summary: @%s -->" % plan["head_sha"]
    failures = []
    degraded = False
    fallback_count = 0
    failed_count = 0
    summary_comment_id = next((c.get("id") for c in comments
                               if isinstance(c, dict) and summary_marker in str(c.get("body", ""))), None)
    if summary_comment_id is not None:
        append_result(args.results, {"id": "summary", "action": "skipped_existing", "url": "", "at": datetime.datetime.now(datetime.timezone.utc).isoformat()})
    else:
        rc, out, err = gh_call(gh, ["api", "%s/issues/%s/comments" % (repo_path, args.pr), "--method", "POST", "-f", "body=" + plan["summary_body"]])
        value = parse_response(out); url = value.get("html_url", "") if isinstance(value, dict) else ""
        summary_comment_id = value.get("id") if isinstance(value, dict) else None
        action = "posted" if not rc and isinstance(value, dict) else "failed"
        if action == "failed":
            failures.append("summary")
            failed_count += 1
        append_result(args.results, {"id": "summary", "action": action, "url": url, "at": datetime.datetime.now(datetime.timezone.utc).isoformat()})
    for entry in plan["entries"]:
        if entry["marker"] in markers:
            append_result(args.results, {"id": entry["id"], "action": "skipped_existing", "url": "", "at": datetime.datetime.now(datetime.timezone.utc).isoformat()}); continue
        if entry.get("scope") == "inline" and entry.get("anchor"):
            cmd = ["api", "%s/pulls/%s/comments" % (repo_path, args.pr), "--method", "POST", "-f", "body=" + entry["body_ja"], "-f", "path=" + entry["anchor"]["path"], "-F", "line=%s" % entry["anchor"]["line"], "-f", "side=" + entry["anchor"]["side"], "-f", "commit_id=" + plan["head_sha"]]
        else:
            cmd = ["api", "%s/issues/%s/comments" % (repo_path, args.pr), "--method", "POST", "-f", "body=" + entry["body_ja"]]
        rc, out, err = gh_call(gh, cmd); value = parse_response(out)
        action = "posted"; url = value.get("html_url", "") if isinstance(value, dict) else ""
        if rc and entry.get("scope") == "inline" and ("422" in err or "unprocessable" in err.lower()):
            degraded = True
            rc, out, _ = gh_call(gh, ["api", "%s/issues/%s/comments" % (repo_path, args.pr), "--method", "POST", "-f", "body=" + entry["body_ja"]])
            value = parse_response(out); action = "fallback_issue_comment"; url = value.get("html_url", "") if isinstance(value, dict) else ""
            if not rc and isinstance(value, dict):
                fallback_count += 1
        if rc or not isinstance(value, dict):
            action = "failed"; failures.append(entry["id"]); failed_count += 1
        append_result(args.results, {"id": entry["id"], "action": action, "url": url, "at": datetime.datetime.now(datetime.timezone.utc).isoformat()})
    if fallback_count or failed_count:
        suffix = "\n\n> ⚠ anchor 失敗/退避: %d 件、投稿失敗: %d 件" % (fallback_count, failed_count)
        if summary_comment_id is None:
            print("warning: summary comment id unavailable; skipping summary PATCH", file=sys.stderr)
            append_result(args.results, {"id": "summary-update", "action": "skipped_no_id", "url": "", "at": datetime.datetime.now(datetime.timezone.utc).isoformat()})
        else:
            patch_body = plan["summary_body"] + suffix
            rc, out, _ = gh_call(gh, ["api", "%s/issues/comments/%s" % (repo_path, summary_comment_id),
                                      "--method", "PATCH", "-f", "body=" + patch_body])
            value = parse_response(out)
            action = "posted" if not rc and isinstance(value, dict) else "failed"
            url = value.get("html_url", "") if isinstance(value, dict) else ""
            append_result(args.results, {"id": "summary-update", "action": action, "url": url,
                                         "at": datetime.datetime.now(datetime.timezone.utc).isoformat()})


def main(argv=None):
    parser = argparse.ArgumentParser(); sub = parser.add_subparsers(dest="command", required=True)
    b = sub.add_parser("build"); b.add_argument("--review-plan", required=True); b.add_argument("--output", required=True); b.add_argument("--translations")
    p = sub.add_parser("post"); p.add_argument("--post-plan", required=True); p.add_argument("--pr", required=True); p.add_argument("--repo", required=True); p.add_argument("--results", required=True); p.add_argument("--gh", default="gh"); p.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)
    try: return build(args) if args.command == "build" else post(args)
    except SystemExit: raise
    except InputError as exc: print("input error: %s" % exc, file=sys.stderr); return 2
    except (OSError, RuntimeError) as exc: print("I/O error: %s" % exc, file=sys.stderr); return 1


if __name__ == "__main__":
    sys.exit(main())
