#!/usr/bin/env python3
"""Run the development test gate and persist a machine-readable receipt."""

import argparse
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import time
from pathlib import Path


SCHEMA_VERSION = "dev-flow-test-gate/v1"
PLAN_SCHEMA_VERSION = "plan-receipt/v1"
OVERRIDE_TARGET_TESTS = {
    "scripts/magi-diff-filter.sh": ["scripts/tests/test_magi_diff_scripts.py"],
    "scripts/magi-split-hunk.sh": ["scripts/tests/test_magi_diff_scripts.py"],
}


class ConfigurationError(Exception):
    pass


class GateTimeout(Exception):
    pass


def need(condition, message):
    if not condition:
        raise ConfigurationError(message)


def rel(path):
    return Path(path).as_posix()


def reject_symlink_components(repo_root, relative_path):
    current = Path(repo_root)
    for part in Path(relative_path).parts:
        current = current / part
        try:
            info = os.lstat(current)
        except FileNotFoundError:
            break
        if stat.S_ISLNK(info.st_mode):
            raise ConfigurationError("path contains a symlink component: %s" % relative_path)


def safe_repo_relative_path(repo_root, value, field_name):
    need(isinstance(value, str) and value, "%s must contain non-empty strings" % field_name)
    path = Path(value)
    need(not path.is_absolute(), "%s must be repo-relative paths" % field_name)
    need(".." not in path.parts, "%s must not contain '..'" % field_name)
    normalised = rel(path)
    reject_symlink_components(repo_root, normalised)
    return normalised


def load_plan_receipt(path):
    with Path(path).open("r", encoding="utf-8") as handle:
        value = json.load(handle)
    need(isinstance(value, dict), "plan receipt root must be an object")
    need(value.get("schema_version") == PLAN_SCHEMA_VERSION, "invalid plan receipt schema_version")
    need(value.get("approved") is True, "plan receipt must be approved")
    target_files = value.get("target_files")
    need(isinstance(target_files, list), "plan receipt target_files must be a list")
    return value


def derive_test_candidates(target_file):
    path = Path(target_file)
    candidates = []
    if len(path.parts) == 2 and path.parts[0] == "scripts":
        stem = path.stem
        if path.suffix == ".py":
            candidates.append("scripts/tests/test_%s.py" % stem.replace("-", "_"))
        elif path.suffix == ".sh":
            candidates.append("scripts/test-%s.sh" % stem)
    candidates.extend(OVERRIDE_TARGET_TESTS.get(target_file, []))
    return candidates


def add_unique(items, value):
    if value not in items:
        items.append(value)


def derive_target_tests(repo_root, target_files):
    derived = []
    unavailable = []
    for target_file in target_files:
        for candidate in derive_test_candidates(target_file):
            if (repo_root / candidate).is_file():
                add_unique(derived, candidate)
            else:
                add_unique(unavailable, candidate)
    return derived, unavailable


def parse_name_status(value):
    paths = []
    for line in value.splitlines():
        fields = line.split("\t")
        if not fields:
            continue
        if fields[0].startswith("R") and len(fields) >= 3:
            add_unique(paths, fields[1])
            add_unique(paths, fields[2])
        elif len(fields) >= 2:
            add_unique(paths, fields[1])
    return paths


def run_capture(command, cwd):
    result = subprocess.run(
        command,
        cwd=str(cwd),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if result.returncode != 0:
        raise RuntimeError("%s failed: %s" % (" ".join(command), result.stderr.strip()))
    return result.stdout


def acquire_diff(repo_root):
    return run_capture(["git", "-C", str(repo_root), "diff", "HEAD"], repo_root)


def acquire_name_status(repo_root):
    return run_capture(["git", "-C", str(repo_root), "diff", "--name-status", "HEAD"], repo_root)


def run_review_router(repo_root, diff_text):
    router = repo_root / "scripts" / "magi-review-router.py"
    need(router.is_file(), "magi-review-router.py is unavailable")
    fd, diff_path = tempfile.mkstemp(prefix="dev-flow-review-route-", suffix=".patch")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            fd = None
            handle.write(diff_text)
        result = subprocess.run(
            [sys.executable, str(router), "--diff-file", diff_path],
            cwd=str(repo_root),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        if result.returncode != 0:
            raise RuntimeError("magi-review-router.py failed: %s" % result.stderr.strip())
        route = json.loads(result.stdout)
        need(isinstance(route, dict), "review route root must be an object")
        return route.get("review_route")
    finally:
        if fd is not None:
            os.close(fd)
        try:
            Path(diff_path).unlink()
        except FileNotFoundError:
            pass


def initial_receipt(args, repo_root, receipt_rel):
    return {
        "schema_version": SCHEMA_VERSION,
        "status": "running",
        "review_route": None,
        "commands": [],
        "environment": {
            "repo_root": str(repo_root),
            "attempt": args.attempt,
            "python": sys.executable,
            "cwd": os.getcwd(),
        },
        "timeout": {
            "seconds": args.timeout_seconds,
            "timed_out": False,
        },
        "derived_target_tests": [],
        "unavailable": {
            "count": 0,
            "files": [],
            "tools": [],
        },
        "baseline": {
            "targeted_tests": [],
            "required_suite": [],
        },
        "current": {
            "targeted_tests": [],
            "required_suite": [],
            "regressions": [],
            "pre_existing_failures": [],
        },
        "scope_violations": {
            "files": [],
            "reason": None,
        },
        "receipt": receipt_rel,
    }


def update_unavailable(receipt):
    unavailable = receipt["unavailable"]
    unavailable["count"] = len(unavailable.get("files", [])) + len(unavailable.get("tools", []))


def write_receipt(path, receipt):
    update_unavailable(receipt)
    path.write_text(
        json.dumps(receipt, ensure_ascii=False, sort_keys=True, indent=2) + "\n",
        encoding="utf-8",
    )


def artifact_path(repo_root, receipt_dir, prefix, stream_name, text):
    logs_dir = receipt_dir / "command-logs"
    logs_dir.mkdir(parents=True, exist_ok=True)
    path = logs_dir / ("%s-%s.txt" % (prefix, stream_name))
    path.write_text(text or "", encoding="utf-8")
    return rel(path.relative_to(repo_root))


def command_result_path(path):
    return rel(Path(path))


def remaining_seconds(deadline):
    return max(0.0, deadline - time.monotonic())


def mark_pending(receipt, kind, command, cwd):
    receipt["commands"].append(
        {
            "kind": kind,
            "command": command,
            "cwd": str(cwd),
            "status": "pending",
            "returncode": None,
        }
    )


def run_logged(receipt, repo_root, receipt_dir, deadline, kind, command, cwd, env=None):
    timeout = remaining_seconds(deadline)
    if timeout <= 0:
        mark_pending(receipt, kind, command, cwd)
        raise GateTimeout("timeout before %s" % kind)
    index = len(receipt["commands"]) + 1
    entry = {
        "kind": kind,
        "command": command,
        "cwd": str(cwd),
        "status": "running",
        "returncode": None,
    }
    receipt["commands"].append(entry)
    try:
        result = subprocess.run(
            command,
            cwd=str(cwd),
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired as exc:
        stdout = exc.stdout or ""
        stderr = exc.stderr or ""
        if isinstance(stdout, bytes):
            stdout = stdout.decode("utf-8", "replace")
        if isinstance(stderr, bytes):
            stderr = stderr.decode("utf-8", "replace")
        entry["status"] = "timeout"
        entry["stdout_artifact"] = artifact_path(repo_root, receipt_dir, "%03d-%s" % (index, kind), "stdout", stdout)
        entry["stderr_artifact"] = artifact_path(repo_root, receipt_dir, "%03d-%s" % (index, kind), "stderr", stderr)
        raise GateTimeout("%s timed out" % kind) from exc
    entry["returncode"] = result.returncode
    entry["status"] = "completed" if result.returncode == 0 else "fail"
    if result.stdout:
        entry["stdout_artifact"] = artifact_path(repo_root, receipt_dir, "%03d-%s" % (index, kind), "stdout", result.stdout)
    if result.stderr:
        entry["stderr_artifact"] = artifact_path(repo_root, receipt_dir, "%03d-%s" % (index, kind), "stderr", result.stderr)
    return result


def test_kind_for_path(path):
    if path.startswith("scripts/tests/") and path.endswith(".py"):
        return "targeted_python_test"
    if path.startswith("scripts/test-") and path.endswith(".sh"):
        return "targeted_shell_test"
    return "targeted_test"


def command_for_test(root, _receipt_dir, path):
    if path.startswith("scripts/tests/") and path.endswith(".py"):
        return ["python3", str(root / path)]
    if path.startswith("scripts/test-") and path.endswith(".sh"):
        return ["bash", path]
    return ["bash", path]


def result_entry(path, result):
    return {
        "path": path,
        "status": "pass" if result.returncode == 0 else "fail",
        "returncode": result.returncode,
    }


def run_targeted_tests(receipt, repo_root, receipt_dir, deadline, root, target_tests):
    results = []
    for path in target_tests:
        result = run_logged(
            receipt,
            repo_root,
            receipt_dir,
            deadline,
            test_kind_for_path(path),
            command_for_test(root, receipt_dir, path),
            root,
        )
        results.append(result_entry(path, result))
    return results


def required_shell_tests(root):
    scripts_dir = root / "scripts"
    return sorted(rel(path.relative_to(root)) for path in scripts_dir.glob("test-*.sh"))


def run_required_suite(receipt, repo_root, receipt_dir, deadline, root):
    results = []
    python_command = ["python3", "-m", "unittest", "discover", "-s", "scripts/tests", "-p", "test_*.py"]
    result = run_logged(receipt, repo_root, receipt_dir, deadline, "required_python_suite", python_command, root)
    results.append(result_entry("scripts/tests:test_*.py", result))
    for path in required_shell_tests(root):
        result = run_logged(receipt, repo_root, receipt_dir, deadline, "required_shell_suite", ["bash", path], root)
        results.append(result_entry(path, result))
    return results


def result_map(entries):
    return {entry["path"]: entry["status"] for entry in entries}


def classify_current_results(receipt):
    baseline = {}
    baseline.update(result_map(receipt["baseline"]["targeted_tests"]))
    baseline.update(result_map(receipt["baseline"]["required_suite"]))
    current_entries = receipt["current"]["targeted_tests"] + receipt["current"]["required_suite"]
    for entry in current_entries:
        if entry["status"] != "fail":
            continue
        path = entry["path"]
        if baseline.get(path) == "fail":
            add_unique(receipt["current"]["pre_existing_failures"], path)
        else:
            add_unique(receipt["current"]["regressions"], path)


def run_health_checks(receipt, repo_root, receipt_dir, deadline, shell_targets):
    failed = False
    for path in shell_targets:
        result = run_logged(receipt, repo_root, receipt_dir, deadline, "bash_n", ["bash", "-n", path], repo_root)
        if result.returncode != 0:
            failed = True
    if not shell_targets:
        return failed
    shellcheck = shutil.which("shellcheck")
    if not shellcheck:
        add_unique(receipt["unavailable"]["tools"], "shellcheck")
        return failed
    for path in shell_targets:
        result = run_logged(receipt, repo_root, receipt_dir, deadline, "shellcheck", ["shellcheck", path], repo_root)
        if result.returncode != 0:
            failed = True
    return failed


def create_baseline_worktree(receipt, repo_root, receipt_dir, deadline):
    baseline_path = Path(tempfile.gettempdir()) / ("dev-flow-test-gate-baseline-%d-%d" % (os.getpid(), int(time.time() * 1000)))
    if baseline_path.exists():
        shutil.rmtree(baseline_path)
    result = run_logged(
        receipt,
        repo_root,
        receipt_dir,
        deadline,
        "baseline_worktree_add",
        ["git", "-C", str(repo_root), "worktree", "add", "--detach", str(baseline_path), "HEAD"],
        repo_root,
    )
    if result.returncode != 0:
        raise ConfigurationError("git worktree add failed for baseline worktree: returncode=%d" % result.returncode)
    return baseline_path


def remove_baseline_worktree(repo_root, baseline_path):
    if baseline_path is None:
        return
    subprocess.run(
        ["git", "-C", str(repo_root), "worktree", "remove", "--force", str(baseline_path)],
        cwd=str(repo_root),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if baseline_path.exists():
        shutil.rmtree(baseline_path)


def validate_changed_paths(repo_root, changed_paths):
    safe = []
    for changed in changed_paths:
        safe.append(safe_repo_relative_path(repo_root, changed, "changed_files"))
    return safe


def configuration_error_receipt(receipt, message):
    receipt["status"] = "configuration_error"
    receipt["scope_violations"]["reason"] = message


def parse_args(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--plan-receipt", required=True)
    parser.add_argument("--attempt", type=int, default=1)
    parser.add_argument("--timeout-seconds", type=int, default=120)
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(argv or sys.argv[1:])
    repo_root = Path(args.repo_root).resolve(strict=True)
    receipt_dir = repo_root / "test-gate" / ("attempt-%d" % args.attempt)
    receipt_dir.mkdir(parents=True, exist_ok=True)
    receipt_path = receipt_dir / "receipt.json"
    receipt_rel = rel(receipt_path.relative_to(repo_root))
    receipt = initial_receipt(args, repo_root, receipt_rel)
    deadline = time.monotonic() + args.timeout_seconds
    baseline_path = None

    try:
        plan = load_plan_receipt(args.plan_receipt)
        target_files = [
            safe_repo_relative_path(repo_root, value, "target_files")
            for value in plan["target_files"]
        ]
        derived_target_tests, unavailable_tests = derive_target_tests(repo_root, target_files)
        receipt["derived_target_tests"] = derived_target_tests
        receipt["unavailable"]["files"] = unavailable_tests

        name_status = acquire_name_status(repo_root)
        diff_text = acquire_diff(repo_root)
        receipt["review_route"] = run_review_router(repo_root, diff_text)

        allowlist = set(target_files) | set(derived_target_tests)
        changed_paths = validate_changed_paths(repo_root, parse_name_status(name_status))
        violations = [path for path in changed_paths if path not in allowlist]
        receipt["scope_violations"]["files"] = violations
        if violations:
            receipt["status"] = "scope_violation"
            receipt["scope_violations"]["reason"] = "changed files are outside target_files and derived_target_tests"
            write_receipt(receipt_path, receipt)
            print("status=scope_violation violations=%d receipt=%s" % (len(violations), receipt_rel))
            return 1

        if receipt["review_route"] == "codex":
            receipt["status"] = "skip"
            receipt["commands"] = []
            write_receipt(receipt_path, receipt)
            print("status=skip review_route=codex receipt=%s" % receipt_rel)
            return 0

        shell_targets = [path for path in target_files if path.endswith(".sh") and (repo_root / path).is_file()]
        health_failed = run_health_checks(receipt, repo_root, receipt_dir, deadline, shell_targets)
        if health_failed:
            receipt["status"] = "fail"
            write_receipt(receipt_path, receipt)
            print("status=fail health_check=fail unavailable_count=%d receipt=%s" % (receipt["unavailable"]["count"], receipt_rel))
            return 1

        baseline_path = create_baseline_worktree(receipt, repo_root, receipt_dir, deadline)
        receipt["baseline"]["targeted_tests"] = run_targeted_tests(
            receipt, repo_root, receipt_dir, deadline, baseline_path, derived_target_tests
        )
        receipt["baseline"]["required_suite"] = run_required_suite(
            receipt, repo_root, receipt_dir, deadline, baseline_path
        )
        receipt["current"]["targeted_tests"] = run_targeted_tests(
            receipt, repo_root, receipt_dir, deadline, repo_root, derived_target_tests
        )
        receipt["current"]["required_suite"] = run_required_suite(
            receipt, repo_root, receipt_dir, deadline, repo_root
        )
        classify_current_results(receipt)
        receipt["status"] = "fail" if receipt["current"]["regressions"] else "pass"
        write_receipt(receipt_path, receipt)
        print(
            "status=%s review_route=%s unavailable_count=%d regressions=%d receipt=%s"
            % (
                receipt["status"],
                receipt["review_route"],
                receipt["unavailable"]["count"],
                len(receipt["current"]["regressions"]),
                receipt_rel,
            )
        )
        return 1 if receipt["status"] == "fail" else 0
    except GateTimeout:
        receipt["status"] = "timeout"
        receipt["timeout"]["timed_out"] = True
        if not any(entry.get("status") == "pending" for entry in receipt["commands"]):
            mark_pending(receipt, "pending", ["remaining gate commands"], repo_root)
        write_receipt(receipt_path, receipt)
        print("status=timeout receipt=%s" % receipt_rel)
        return 1
    except (ConfigurationError, json.JSONDecodeError, OSError) as exc:
        configuration_error_receipt(receipt, "target_files configuration error: %s" % exc)
        write_receipt(receipt_path, receipt)
        print("status=configuration_error receipt=%s" % receipt_rel)
        return 2
    except Exception as exc:
        receipt["status"] = "fail"
        receipt["error"] = str(exc)
        write_receipt(receipt_path, receipt)
        print("status=fail error=%s receipt=%s" % (exc, receipt_rel))
        return 1
    finally:
        remove_baseline_worktree(repo_root, baseline_path)


if __name__ == "__main__":
    raise SystemExit(main())
