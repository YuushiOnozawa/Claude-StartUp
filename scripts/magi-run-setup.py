#!/usr/bin/env python3
"""Prepare a MAGI run directory and publish setup artifacts safely."""
import argparse
import datetime
import hashlib
import json
import os
import re
import secrets
import shutil
import stat
import subprocess
import sys
import tempfile
import time
from pathlib import Path


MANIFEST_SCHEMA = "persona-manifest/v1"
POLICY_SCHEMA = "magi-run-policy/v1"
LOWER_SHA256 = re.compile(r"^[0-9a-f]{64}$")
GIT_SHA1 = re.compile(r"^[0-9a-f]{40}$")
RUN_ID = re.compile(r"^[0-9]{8}T[0-9]{6}Z-[0-9]+-[0-9a-f]{8}$")
PERSONA_KEY = re.compile(r"^[a-z][a-z0-9_-]*$")
PERSONA_PREFIX = re.compile(r"^[A-Z][A-Z0-9_]*$")
SUBDIR_NAME = re.compile(r"^[A-Za-z0-9._-]+$")
SEVERITIES = {"HIGH", "MEDIUM", "LOW", "UNKNOWN"}
MAX_RUNS = 20
MAX_AGE_SECONDS = 14 * 24 * 60 * 60


class ConfigurationError(Exception):
    pass


def need(condition, message):
    if not condition:
        raise ConfigurationError(message)


def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def canonical(value):
    return (json.dumps(value, ensure_ascii=False, sort_keys=False, separators=(",", ":"),
                       allow_nan=False) + "\n").encode("utf-8")


def reject_dotdot(path):
    need(".." not in Path(path).parts, "path must not contain '..'")


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
            raise ConfigurationError("path contains a symlink component: %s" % current)


def canonical_existing_directory(path):
    path = Path(path)
    need(path.is_absolute(), "directory path must be absolute")
    reject_dotdot(path)
    reject_symlinks(path)
    try:
        info = os.lstat(path)
    except FileNotFoundError as exc:
        raise ConfigurationError("directory does not exist: %s" % path) from exc
    need(stat.S_ISDIR(info.st_mode), "path must be a directory: %s" % path)
    return path.resolve(strict=True)


def fsync_dir(path):
    fd = os.open(path, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def open_new_no_follow(path, data, mode=0o600):
    path = Path(path)
    reject_dotdot(path)
    reject_symlinks(path.parent)
    if path.exists() or path.is_symlink():
        raise FileExistsError(str(path))
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
    fd = os.open(path, flags, mode)
    try:
        with os.fdopen(fd, "wb") as handle:
            fd = None
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
    finally:
        if fd is not None:
            os.close(fd)
    fsync_dir(path.parent)


def make_tmp(final_path):
    final_path = Path(final_path)
    for _ in range(20):
        candidate = final_path.parent / (".%s.%s.tmp" % (final_path.name, secrets.token_hex(8)))
        if not candidate.exists() and not candidate.is_symlink():
            return candidate
    raise RuntimeError("temporary file collision")


def commit_json_atomic(final_path, value):
    final_path = Path(final_path)
    data = canonical(value)
    tmp = make_tmp(final_path)
    open_new_no_follow(tmp, data)
    with tmp.open("rb") as handle:
        loaded = json.load(handle)
    need(loaded == value, "json identity mismatch before publish: %s" % final_path.name)
    os.replace(tmp, final_path)
    fsync_dir(final_path.parent)


def load_json_object(path):
    reject_dotdot(path)
    reject_symlinks(path)
    with Path(path).open("r", encoding="utf-8") as handle:
        value = json.load(handle)
    need(isinstance(value, dict), "json root must be an object: %s" % path)
    return value


# 1. diff acquisition layer
def run_capture(command, cwd, env=None):
    result = subprocess.run(command, cwd=str(cwd), env=env, input=None, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE)
    if result.returncode != 0:
        message = result.stderr.decode("utf-8", "replace").strip()
        raise RuntimeError("%s failed%s" % (" ".join(command), ": " + message if message else ""))
    return result.stdout


def acquire_raw_diff(args, repo_root):
    if args.workflow == "fast":
        staged = run_capture(["git", "-C", str(repo_root), "diff", "--staged"], repo_root)
        if staged:
            return staged, {"kind": "staged"}
        return run_capture(["git", "-C", str(repo_root), "diff", "HEAD"], repo_root), {"kind": "head"}
    need(args.pr_number is not None, "--pr-number is required for hard workflow")
    return run_capture(["gh", "pr", "diff", str(args.pr_number)], repo_root), {"kind": "file"}


def run_filter(raw_diff, args, repo_root, filter_path):
    excluded_path = None
    env = os.environ.copy()
    if args.workflow == "hard":
        excluded_path = Path(os.environ.get("TMPDIR", "/tmp")) / ("magi-filter-excluded-%s.txt" % secrets.token_hex(8))
        env["MAGI_FILTER_EXCLUDED_LIST"] = str(excluded_path)
    try:
        result = subprocess.run(["bash", str(filter_path)], cwd=str(repo_root), input=raw_diff,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
        if result.returncode != 0:
            message = result.stderr.decode("utf-8", "replace").strip()
            raise RuntimeError("magi-diff-filter.sh failed%s" % (": " + message if message else ""))
        excluded = b""
        if excluded_path is not None and excluded_path.exists():
            excluded = excluded_path.read_bytes()
        return result.stdout, excluded
    finally:
        if excluded_path is not None:
            try:
                excluded_path.unlink()
            except FileNotFoundError:
                pass


def run_review_router(raw_diff, repo_root, router_path):
    need(router_path.is_file(), "magi-review-router.py is unavailable")
    fd, diff_path = tempfile.mkstemp(prefix="magi-review-router-", suffix=".patch")
    try:
        with os.fdopen(fd, "wb") as handle:
            fd = None
            handle.write(raw_diff)
        result = subprocess.run([sys.executable, str(router_path), "--diff-file", diff_path],
                                cwd=str(repo_root), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if result.returncode != 0:
            message = result.stderr.decode("utf-8", "replace").strip()
            raise RuntimeError("magi-review-router.py failed%s" %
                               (": " + message if message else ""))
        route = json.loads(result.stdout.decode("utf-8"))
        need(isinstance(route, dict), "review route root must be an object")
        return route, result.stdout
    finally:
        if fd is not None:
            os.close(fd)
        try:
            Path(diff_path).unlink()
        except FileNotFoundError:
            pass


def finalise_review_route(route, raw_diff, filtered_diff):
    route = dict(route)
    route["raw_diff_sha256"] = sha256_bytes(raw_diff)
    route["filtered_diff_sha256"] = sha256_bytes(filtered_diff)
    return route, json.dumps(route, ensure_ascii=False, separators=(",", ":")).encode("utf-8")


def is_fixture_filtered_route(route):
    paths = route.get("path_summary", {}).get("paths", [])
    need(isinstance(paths, list), "review route path summary paths must be an array")
    fixture_path = re.compile(r"(^|/)tests?/fixtures?/")
    fixture_suffixes = {".json", ".jsonl", ".txt", ".patch", ".diff", ".csv", ".tsv",
                        ".yml", ".yaml", ".xml"}
    return bool(paths) and all(
        isinstance(path, str)
        and fixture_path.search(path)
        and Path(path.lower()).suffix in fixture_suffixes
        for path in paths
    )


# 2. environment validation and run directory creation layer
def ensure_private_directory(path, expected=None):
    path = Path(path)
    reject_dotdot(path)
    reject_symlinks(path)
    if path.exists():
        info = os.lstat(path)
        need(stat.S_ISDIR(info.st_mode), "path must be a directory: %s" % path)
    else:
        path.mkdir(mode=0o700)
    os.chmod(path, 0o700)
    resolved = path.resolve(strict=True)
    if expected is not None:
        need(resolved == Path(expected), "directory resolved outside expected location: %s" % path)
    return resolved


def generate_run_id():
    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    return "%s-%s-%s" % (now, os.getpid(), secrets.token_hex(4))


def injected_run_ids():
    value = os.environ.get("MAGI_RUN_SETUP_TEST_RUN_IDS")
    if not value:
        return []
    return value.split(":")


def select_run_id(attempt, injected):
    if attempt < len(injected):
        return injected[attempt]
    return generate_run_id()


def create_run_environment(diff_hash, extra_subdirs):
    need(LOWER_SHA256.fullmatch(diff_hash), "invalid diff hash")
    home = Path(os.environ.get("HOME", "")).expanduser()
    need(str(home), "HOME is not set")
    home_canonical = canonical_existing_directory(home.resolve(strict=True))

    cache = home_canonical / ".cache"
    magi = cache / "magi"
    runs_root = magi / "runs"
    diff_root = runs_root / diff_hash
    ensure_private_directory(cache, home_canonical / ".cache")
    ensure_private_directory(magi, home_canonical / ".cache" / "magi")
    ensure_private_directory(runs_root, home_canonical / ".cache" / "magi" / "runs")
    ensure_private_directory(diff_root, home_canonical / ".cache" / "magi" / "runs" / diff_hash)

    injected = injected_run_ids()
    last_collision = None
    for attempt in range(5):
        run_id = select_run_id(attempt, injected)
        need(RUN_ID.fullmatch(run_id), "invalid run id generated")
        run_dir = diff_root / run_id
        reject_symlinks(run_dir)
        try:
            run_dir.mkdir(mode=0o700)
        except FileExistsError as exc:
            last_collision = exc
            continue
        except OSError as exc:
            raise RuntimeError("run dir create failed: %s" % exc) from exc
        expected = home_canonical / ".cache" / "magi" / "runs" / diff_hash / run_id
        ensure_private_directory(run_dir, expected)
        create_subdirectories(run_dir, expected, extra_subdirs)
        return runs_root.resolve(strict=True), run_dir.resolve(strict=True), run_id
    raise RuntimeError("run id collision after five attempts") from last_collision


def create_subdirectories(run_dir, expected_run_dir, extra_subdirs):
    names = []
    for name in ["diff", "results", "status", *extra_subdirs]:
        if name not in names:
            need(SUBDIR_NAME.fullmatch(name) and name not in {".", ".."}, "invalid subdirectory name")
            names.append(name)
    injected = os.environ.get("MAGI_RUN_SETUP_TEST_PRECREATE_SUBDIR_SYMLINK")
    if injected:
        need(injected in names, "test symlink target must be a requested subdir")
        target = run_dir / ".precreated-subdir-target"
        target.mkdir(mode=0o700)
        (run_dir / injected).symlink_to(target, target_is_directory=True)
    for name in names:
        path = run_dir / name
        reject_symlinks(path)
        if path.exists() or path.is_symlink():
            raise ConfigurationError("run subdirectory already exists: %s" % path)
        path.mkdir(mode=0o700)
        ensure_private_directory(path, expected_run_dir / name)


# 3. artifact writing layer
def validate_manifest(value):
    need(isinstance(value, dict), "manifest root must be an object")
    need(value.get("schema_version") == MANIFEST_SCHEMA, "invalid manifest schema_version")
    personas = value.get("personas")
    need(isinstance(personas, list), "manifest personas must be an array")
    ordinals, keys, names, prefixes = set(), set(), set(), set()
    normalised = []
    for person in personas:
        need(isinstance(person, dict), "manifest persona must be an object")
        ordinal = person.get("ordinal")
        key = person.get("key")
        name = person.get("name")
        prefix = person.get("id_prefix")
        need(isinstance(ordinal, int) and not isinstance(ordinal, bool) and ordinal > 0,
             "manifest ordinal must be a positive integer")
        need(isinstance(key, str) and PERSONA_KEY.fullmatch(key), "invalid persona key")
        need(isinstance(name, str) and name and name == name.upper(), "invalid persona name")
        need(isinstance(prefix, str) and PERSONA_PREFIX.fullmatch(prefix), "invalid persona id_prefix")
        for item, values in ((ordinal, ordinals), (key, keys), (name, names), (prefix, prefixes)):
            need(item not in values, "duplicate manifest persona field")
            values.add(item)
        normalised.append({"ordinal": ordinal, "key": key, "name": name, "id_prefix": prefix})
    normalised.sort(key=lambda item: item["ordinal"])
    return {"schema_version": MANIFEST_SCHEMA, "personas": normalised}


def parse_bool(value):
    if value is None:
        return None
    if value == "true":
        return True
    if value == "false":
        return False
    raise ConfigurationError("boolean argument must be true or false")


def validate_policy(value):
    need(isinstance(value, dict), "run policy root must be an object")
    need(value.get("schema_version") == POLICY_SCHEMA, "invalid run policy schema_version")
    enums = {
        "workflow": {"fast", "hard"},
        "gate_basis": {"raw"},
        "gate_severity": SEVERITIES,
        "false_positive_policy": {"annotate", "exclude"},
        "needs_human_policy": {"label_and_block", "label"},
        "renderer": {"terminal", "github"},
        "locale": {"ja"},
        "anchor_policy": {"none", "pr"},
    }
    for field, choices in enums.items():
        need(value.get(field) in choices, "invalid run policy %s" % field)
    need(isinstance(value.get("audit_enabled"), bool) and isinstance(value.get("dedupe_enabled"), bool),
         "invalid policy boolean")
    audit_severities = value.get("audit_severities")
    need(isinstance(audit_severities, list)
         and all(item in SEVERITIES for item in audit_severities)
         and len(set(audit_severities)) == len(audit_severities), "invalid audit severities")
    completion = value.get("completion_policy")
    need(isinstance(completion, dict)
         and all(isinstance(completion.get(k), bool)
                 for k in ("require_marker", "zero_findings_requires_no_findings")),
         "invalid completion policy")
    diff = value.get("diff_source")
    need(isinstance(diff, dict) and diff.get("kind") in {"staged", "head", "file"}, "invalid diff_source")
    if value["anchor_policy"] == "pr":
        need(isinstance(value.get("head_sha"), str) and GIT_SHA1.fullmatch(value["head_sha"]),
             "invalid policy head_sha")
    else:
        need(value.get("head_sha") is None, "head_sha must be null without pr anchors")
    return value


def finalise_policy(template, workflow, diff_source, head_sha_arg, audit_enabled_arg):
    validate_policy(template)
    need(template.get("workflow") == workflow, "policy workflow does not match --workflow")
    policy = dict(template)
    policy["diff_source"] = {"kind": diff_source["kind"]}
    audit_enabled = parse_bool(audit_enabled_arg)
    if audit_enabled is not None:
        policy["audit_enabled"] = audit_enabled
    if policy["anchor_policy"] == "pr":
        need(head_sha_arg is not None, "--head-sha is required for pr anchors")
        head_sha = head_sha_arg.lower()
        need(GIT_SHA1.fullmatch(head_sha), "invalid --head-sha")
        policy["head_sha"] = head_sha
    else:
        need(head_sha_arg is None, "--head-sha is invalid without pr anchors")
        policy["head_sha"] = None
    return validate_policy(policy)


def preflight_templates(args, manifest_template, policy_template):
    validate_manifest(manifest_template)
    validate_policy(policy_template)
    need(policy_template.get("workflow") == args.workflow, "policy workflow does not match --workflow")
    if policy_template["anchor_policy"] == "pr":
        need(args.head_sha is not None, "--head-sha is required for pr anchors")
        need(GIT_SHA1.fullmatch(args.head_sha), "invalid --head-sha")
    else:
        need(args.head_sha is None, "--head-sha is invalid without pr anchors")


def save_filtered_input(run_dir, filtered):
    input_path = run_dir / "diff" / "input.filtered.patch"
    open_new_no_follow(input_path, filtered)
    if os.environ.get("MAGI_RUN_SETUP_TEST_CORRUPT_INPUT_AFTER_WRITE"):
        with input_path.open("ab") as handle:
            handle.write(b"corrupt")
    saved = input_path.read_bytes()
    if saved != filtered or sha256_bytes(saved) != sha256_bytes(filtered):
        raise RuntimeError("input identity mismatch after save")


def save_excluded_files(run_dir, excluded):
    if excluded:
        open_new_no_follow(run_dir / "diff" / "excluded-files.txt", excluded)


def save_review_route(run_dir, route_bytes):
    open_new_no_follow(run_dir / "review-route.json", route_bytes)


def maybe_age_current_run(run_dir):
    value = os.environ.get("MAGI_RUN_SETUP_TEST_CURRENT_MTIME_DAYS_AGO")
    if not value:
        return
    timestamp = time.time() - float(value) * 86400
    os.utime(run_dir, (timestamp, timestamp))


def warn(message):
    print("warning: %s" % message, file=sys.stderr)


def relative_to_root(path, root):
    try:
        return path.resolve(strict=True).relative_to(root)
    except (OSError, ValueError):
        return None


def collect_prune_runs(runs_root):
    entries = []
    if not runs_root.exists():
        return entries
    for diff_dir in runs_root.iterdir():
        try:
            diff_info = os.lstat(diff_dir)
        except OSError as exc:
            warn("prune lstat failed for %s: %s" % (diff_dir.name, exc))
            continue
        if stat.S_ISLNK(diff_info.st_mode):
            warn("prune keeps symlink diff-hash entry: %s" % diff_dir.name)
            continue
        if not stat.S_ISDIR(diff_info.st_mode):
            continue
        if not LOWER_SHA256.fullmatch(diff_dir.name):
            warn("prune keeps malformed diff-hash entry: %s" % diff_dir.name)
            continue
        for run_dir in diff_dir.iterdir():
            relative = "%s/%s" % (diff_dir.name, run_dir.name)
            try:
                run_info = os.lstat(run_dir)
            except OSError as exc:
                warn("prune lstat failed for %s: %s" % (relative, exc))
                continue
            if stat.S_ISLNK(run_info.st_mode):
                warn("prune keeps symlink run entry: %s" % relative)
                continue
            if not stat.S_ISDIR(run_info.st_mode):
                continue
            if not RUN_ID.fullmatch(run_dir.name):
                warn("prune keeps malformed run id: %s" % relative)
                continue
            resolved_relative = relative_to_root(run_dir, runs_root)
            if resolved_relative is None or str(resolved_relative) != relative:
                warn("prune keeps non-canonical run entry: %s" % relative)
                continue
            entries.append((run_info.st_mtime, relative, run_dir))
    return entries


def prune_runs(runs_root, current_run_dir, current_run_id):
    try:
        runs_root = runs_root.resolve(strict=True)
        current_relative = str(current_run_dir.resolve(strict=True).relative_to(runs_root))
        cutoff = time.time() - MAX_AGE_SECONDS
        all_runs = collect_prune_runs(runs_root)
        rankable = sorted((item for item in all_runs if item[1] != current_relative),
                          key=lambda item: item[0], reverse=True)
        candidates = []
        for index, (mtime, relative, run_dir) in enumerate(rankable, start=1):
            if mtime < cutoff or index > MAX_RUNS:
                candidates.append((relative, run_dir))
        for relative, run_dir in candidates:
            diff_component, run_component = relative.split("/", 1)
            if not LOWER_SHA256.fullmatch(diff_component) or not RUN_ID.fullmatch(run_component):
                warn("prune rejects unsafe candidate: %s" % relative)
                continue
            try:
                info = os.lstat(run_dir)
                if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode):
                    warn("prune rejects unsafe candidate: %s" % relative)
                    continue
                if str(run_dir.resolve(strict=True).relative_to(runs_root)) != relative:
                    warn("prune rejects non-canonical candidate: %s" % relative)
                    continue
                quarantine = runs_root / (".prune-%s-%s-%s" %
                                          (current_run_id, secrets.token_hex(4), run_component))
                if quarantine.exists() or quarantine.is_symlink():
                    warn("prune quarantine collision: %s" % relative)
                    continue
                run_dir.rename(quarantine)
                qinfo = os.lstat(quarantine)
                if stat.S_ISLNK(qinfo.st_mode) or not stat.S_ISDIR(qinfo.st_mode):
                    warn("prune quarantine unsafe: %s" % relative)
                    continue
                shutil.rmtree(quarantine)
            except Exception as exc:
                warn("prune failed for %s: %s" % (relative, exc))
    except Exception as exc:
        warn("prune unavailable: %s" % exc)


def publish_artifacts(args, run_dir, filtered, excluded, manifest_template, policy_template, diff_source):
    diff_hash = sha256_bytes(filtered)
    save_filtered_input(run_dir, filtered)
    save_excluded_files(run_dir, excluded)
    manifest = validate_manifest(manifest_template)
    policy = finalise_policy(policy_template, args.workflow, diff_source, args.head_sha, args.audit_enabled)
    commit_json_atomic(run_dir / "manifest.json", manifest)
    commit_json_atomic(run_dir / "run-policy.json", policy)
    maybe_age_current_run(run_dir)
    saved = (run_dir / "diff" / "input.filtered.patch").read_bytes()
    if sha256_bytes(saved) != diff_hash or len(saved) != len(filtered):
        raise RuntimeError("input identity mismatch after artifact publish")
    return {
        "path": "diff/input.filtered.patch",
        "bytes": len(saved),
        "sha256": sha256_bytes(saved),
    }


def setup_receipt(workflow, run_dir, run_id, diff_hash, diff_source, input_receipt, review_route):
    return {
        "status": "ready",
        "workflow": workflow,
        "run_dir": str(run_dir),
        "run_id": run_id,
        "diff_hash": diff_hash,
        "diff_source": diff_source,
        "review_route": review_route,
        "review_route_artifact": "review-route.json",
        "input": input_receipt,
        "manifest": "manifest.json",
        "run_policy": "run-policy.json",
    }


def routed_receipt(workflow, run_dir, run_id, diff_hash, diff_source, review_route):
    return {
        "status": "routed",
        "workflow": workflow,
        "run_dir": str(run_dir),
        "run_id": run_id,
        "diff_hash": diff_hash,
        "diff_source": diff_source,
        "review_route": review_route,
        "review_route_artifact": "review-route.json",
    }


def parse_args(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("--workflow", choices=("fast", "hard"), required=True)
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--manifest-file")
    parser.add_argument("--policy-template-file")
    parser.add_argument("--manifest-json")
    parser.add_argument("--policy-json")
    parser.add_argument("--audit-enabled", choices=("true", "false"))
    parser.add_argument("--pr-number")
    parser.add_argument("--head-sha")
    parser.add_argument("--extra-subdir", action="append", default=[])
    parser.add_argument("--no-prune", action="store_true")
    args = parser.parse_args(argv)
    need(bool(args.manifest_file) ^ bool(args.manifest_json), "provide exactly one manifest input")
    need(bool(args.policy_template_file) ^ bool(args.policy_json), "provide exactly one policy input")
    if args.head_sha is not None:
        args.head_sha = args.head_sha.lower()
        need(GIT_SHA1.fullmatch(args.head_sha), "invalid --head-sha")
    return args


def load_json_arg(path_value, json_value):
    if path_value:
        return load_json_object(Path(path_value))
    value = json.loads(json_value)
    need(isinstance(value, dict), "json argument root must be an object")
    return value


def main(argv=None):
    args = parse_args(argv or sys.argv[1:])
    repo_root = canonical_existing_directory(Path(args.repo_root).resolve(strict=True))
    filter_path = repo_root / "scripts" / "magi-diff-filter.sh"
    router_path = Path(__file__).resolve(strict=True).parent / "magi-review-router.py"
    need(filter_path.is_file(), "magi-diff-filter.sh is unavailable")
    manifest_template = load_json_arg(args.manifest_file, args.manifest_json)
    policy_template = load_json_arg(args.policy_template_file, args.policy_json)
    preflight_templates(args, manifest_template, policy_template)

    raw_diff, diff_source = acquire_raw_diff(args, repo_root)
    filtered, excluded = run_filter(raw_diff, args, repo_root, filter_path)
    route = None
    route_bytes = b""
    if filtered or raw_diff:
        router_input = filtered if filtered else raw_diff
        route, route_bytes = run_review_router(router_input, repo_root, router_path)
        route, route_bytes = finalise_review_route(route, raw_diff, filtered)
    if not filtered:
        if raw_diff and not is_fixture_filtered_route(route):
            diff_hash = sha256_bytes(filtered)
            runs_root, run_dir, run_id = create_run_environment(diff_hash, args.extra_subdir)
            save_review_route(run_dir, route_bytes)
            maybe_age_current_run(run_dir)
            if not args.no_prune:
                prune_runs(runs_root, run_dir, run_id)
            print(json.dumps(routed_receipt(args.workflow, run_dir, run_id, diff_hash, diff_source,
                                            route.get("review_route")),
                             ensure_ascii=False, separators=(",", ":")))
            return 0
        print(json.dumps({
            "status": "empty",
            "workflow": args.workflow,
            "message": "filtered diff is empty",
            "diff_source": diff_source,
        }, ensure_ascii=False, separators=(",", ":")))
        return 0

    diff_hash = sha256_bytes(filtered)
    runs_root, run_dir, run_id = create_run_environment(diff_hash, args.extra_subdir)
    input_receipt = publish_artifacts(args, run_dir, filtered, excluded, manifest_template,
                                      policy_template, diff_source)
    save_review_route(run_dir, route_bytes)
    if not args.no_prune:
        prune_runs(runs_root, run_dir, run_id)
    print(json.dumps(setup_receipt(args.workflow, run_dir, run_id, diff_hash, diff_source,
                                   input_receipt, route.get("review_route")),
                     ensure_ascii=False, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ConfigurationError as exc:
        print("configuration_error: %s" % exc, file=sys.stderr)
        raise SystemExit(2)
    except json.JSONDecodeError as exc:
        print("configuration_error: invalid json: %s" % exc, file=sys.stderr)
        raise SystemExit(2)
    except Exception as exc:
        print("error: %s" % exc, file=sys.stderr)
        raise SystemExit(1)
