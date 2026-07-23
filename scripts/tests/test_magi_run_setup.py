import hashlib
import importlib.util
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from types import SimpleNamespace


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "magi-run-setup.py"
FILTER = ROOT / "scripts" / "magi-diff-filter.sh"
AGGREGATE_SCRIPT = ROOT / "scripts" / "magi-aggregate.py"

SPEC = importlib.util.spec_from_file_location("magi_aggregate", AGGREGATE_SCRIPT)
MAGI_AGGREGATE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MAGI_AGGREGATE)


VALID_HEAD_SHA = "0123456789abcdef0123456789abcdef01234567"
RUN_ID_1 = "20260723T010203Z-1111-a1b2c3d4"
RUN_ID_2 = "20260723T010204Z-1111-b1b2c3d4"
RUN_ID_3 = "20260723T010205Z-1111-c1b2c3d4"
RUN_ID_4 = "20260723T010206Z-1111-d1b2c3d4"
RUN_ID_5 = "20260723T010207Z-1111-e1b2c3d4"


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def one_file_diff(path="src/example.py", lines=2):
    body = [
        "diff --git a/%s b/%s\n" % (path, path),
        "index 1111111..2222222 100644\n",
        "--- a/%s\n" % path,
        "+++ b/%s\n" % path,
        "@@ -1,%d +1,%d @@\n" % (lines, lines),
    ]
    for index in range(lines):
        body.append("-old_%04d\n" % index)
        body.append("+new_%04d\n" % index)
    return "".join(body).encode("utf-8")


def excluded_fixture_diff(path="tests/fixtures/data.json"):
    return (
        "diff --git a/%s b/%s\n"
        "index 1111111..2222222 100644\n"
        "--- a/%s\n"
        "+++ b/%s\n"
        "@@ -1 +1 @@\n"
        "-{\"old\":true}\n"
        "+{\"new\":true}\n"
    ) % (path, path, path, path)


def manifest_value():
    return {
        "schema_version": "persona-manifest/v1",
        "personas": [
            {"ordinal": 1, "key": "melchior", "name": "MELCHIOR", "id_prefix": "MEL"},
            {"ordinal": 2, "key": "balthasar", "name": "BALTHASAR", "id_prefix": "BAL"},
        ],
    }


def policy_value(workflow="fast", anchor_policy="none", head_sha=None, diff_kind="staged"):
    return {
        "schema_version": "magi-run-policy/v1",
        "workflow": workflow,
        "gate_basis": "raw",
        "gate_severity": "HIGH",
        "audit_enabled": workflow == "hard",
        "audit_severities": ["HIGH", "MEDIUM"],
        "false_positive_policy": "annotate",
        "needs_human_policy": "label_and_block",
        "dedupe_enabled": True,
        "renderer": "terminal",
        "locale": "ja",
        "anchor_policy": anchor_policy,
        "completion_policy": {"require_marker": True, "zero_findings_requires_no_findings": True},
        "diff_source": {"kind": diff_kind},
        "head_sha": head_sha,
    }


class MagiRunSetupTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.case = self.prepare_case(Path(self.temporary.name))

    def prepare_case(self, root):
        case = SimpleNamespace(
            root=root,
            home=root / "home",
            repo=root / "repo",
            bin=root / "bin",
        )
        case.home.mkdir()
        (case.repo / "scripts").mkdir(parents=True)
        shutil.copy2(FILTER, case.repo / "scripts" / "magi-diff-filter.sh")
        case.bin.mkdir()
        self.write_fake_git(case)
        self.write_fake_gh(case)
        return case

    def write_script(self, path, text):
        path.write_text(text, encoding="utf-8")
        path.chmod(path.stat().st_mode | stat.S_IXUSR)

    def write_fake_git(self, case):
        self.write_script(
            case.bin / "git",
            """#!/usr/bin/env bash
set -eu
if [ "${1:-}" = "-C" ]; then
  shift 2
fi
if [ "${1:-}" = "diff" ]; then
  shift
  if [ "${1:-}" = "--staged" ] || [ "${1:-}" = "--cached" ]; then
    [ -n "${MAGI_TEST_STAGED_DIFF:-}" ] && cat "$MAGI_TEST_STAGED_DIFF"
    exit 0
  fi
  if [ "${1:-}" = "HEAD" ] || [ "$#" -eq 0 ]; then
    [ -n "${MAGI_TEST_HEAD_DIFF:-}" ] && cat "$MAGI_TEST_HEAD_DIFF"
    exit 0
  fi
fi
printf 'unexpected git args:' >&2
printf ' %s' "$@" >&2
printf '\\n' >&2
exit 99
""",
        )

    def write_fake_gh(self, case):
        self.write_script(
            case.bin / "gh",
            """#!/usr/bin/env bash
set -eu
if [ "${1:-}" = "pr" ] && [ "${2:-}" = "diff" ]; then
  [ -n "${MAGI_TEST_GH_DIFF:-}" ] && cat "$MAGI_TEST_GH_DIFF"
  exit 0
fi
printf 'unexpected gh args:' >&2
printf ' %s' "$@" >&2
printf '\\n' >&2
exit 99
""",
        )

    def write_bytes(self, case, name, data):
        path = case.root / name
        path.write_bytes(data)
        return path

    def run_setup(
        self,
        workflow="fast",
        case=None,
        staged_diff=None,
        head_diff=None,
        gh_diff=None,
        manifest=None,
        policy=None,
        head_sha=None,
        extra_args=None,
        env_extra=None,
    ):
        case = case or self.case
        manifest_path = case.root / "manifest.json"
        policy_path = case.root / "policy.json"
        manifest_path.write_text(json.dumps(manifest or manifest_value()), encoding="utf-8")
        if policy is None:
            if workflow == "hard":
                policy = policy_value("hard", anchor_policy="pr", head_sha=head_sha or VALID_HEAD_SHA, diff_kind="file")
            else:
                policy = policy_value("fast", anchor_policy="none", head_sha=None, diff_kind="staged")
        policy_path.write_text(json.dumps(policy), encoding="utf-8")

        staged_path = self.write_bytes(case, "staged.patch", staged_diff or b"")
        head_path = self.write_bytes(case, "head.patch", head_diff or b"")
        gh_path = self.write_bytes(case, "gh.patch", gh_diff or b"")
        env = {
            **os.environ,
            "HOME": str(case.home),
            "PATH": "%s%s%s" % (case.bin, os.pathsep, os.environ.get("PATH", "")),
            "MAGI_TEST_STAGED_DIFF": str(staged_path),
            "MAGI_TEST_HEAD_DIFF": str(head_path),
            "MAGI_TEST_GH_DIFF": str(gh_path),
        }
        if env_extra:
            env.update(env_extra)

        command = [
            sys.executable,
            str(SCRIPT),
            "--workflow",
            workflow,
            "--repo-root",
            str(case.repo),
            "--manifest-file",
            str(manifest_path),
            "--policy-template-file",
            str(policy_path),
        ]
        if workflow == "hard":
            command.extend(["--pr-number", "339"])
        if head_sha is not None:
            command.extend(["--head-sha", head_sha])
        if extra_args:
            command.extend(extra_args)
        return subprocess.run(command, text=True, capture_output=True, env=env)

    def parse_stdout_object(self, result):
        decoder = json.JSONDecoder()
        value, end = decoder.raw_decode(result.stdout)
        self.assertEqual(result.stdout[end:].strip(), "")
        self.assertIsInstance(value, dict)
        self.assertNotIn("warning", result.stdout.lower())
        return value

    def assert_ready_receipt_matches_saved_input(self, result, kind):
        self.assertEqual(result.returncode, 0, result.stderr)
        receipt = self.parse_stdout_object(result)
        self.assertEqual(receipt["status"], "ready")
        self.assertEqual(receipt["diff_source"]["kind"], kind)
        run_dir = Path(receipt["run_dir"])
        saved = run_dir / "diff" / "input.filtered.patch"
        self.assertTrue(saved.is_file())
        saved_bytes = saved.read_bytes()
        self.assertEqual(receipt["diff_hash"], sha256(saved_bytes))
        self.assertEqual(receipt["input"]["sha256"], sha256(saved_bytes))
        self.assertEqual(receipt["input"]["bytes"], len(saved_bytes))
        self.assertEqual(receipt["input"]["path"], "diff/input.filtered.patch")
        return receipt, run_dir

    def iter_run_dirs(self, case=None):
        case = case or self.case
        runs = case.home / ".cache" / "magi" / "runs"
        if not runs.exists():
            return []
        return [path for path in runs.glob("*/*") if path.is_dir() and not path.is_symlink()]

    def test_fast_prefers_staged_diff_and_reports_hash_from_saved_input(self):
        result = self.run_setup(staged_diff=one_file_diff("src/staged.py"), head_diff=one_file_diff("src/head.py"))

        receipt, _ = self.assert_ready_receipt_matches_saved_input(result, "staged")
        self.assertEqual(receipt["workflow"], "fast")

    def test_fast_falls_back_to_head_diff_when_staged_is_empty(self):
        result = self.run_setup(staged_diff=b"", head_diff=one_file_diff("src/head.py"))

        receipt, run_dir = self.assert_ready_receipt_matches_saved_input(result, "head")
        self.assertEqual(receipt["workflow"], "fast")
        self.assertTrue(run_dir.exists())

    def test_empty_filtered_diff_does_not_create_run_dir_for_fast_and_hard(self):
        for workflow in ("fast", "hard"):
            with self.subTest(workflow=workflow):
                with tempfile.TemporaryDirectory() as name:
                    case = self.prepare_case(Path(name))
                    filtered_empty = excluded_fixture_diff().encode("utf-8")
                    result = self.run_setup(
                        workflow=workflow,
                        case=case,
                        staged_diff=filtered_empty,
                        head_diff=filtered_empty,
                        gh_diff=filtered_empty,
                        head_sha=VALID_HEAD_SHA if workflow == "hard" else None,
                    )
                    self.assertEqual(result.returncode, 0, result.stderr)
                    receipt = self.parse_stdout_object(result)
                    self.assertEqual(receipt["status"], "empty")
                    self.assertEqual(self.iter_run_dirs(case), [])

    def test_hard_persists_filter_excluded_files(self):
        kept = one_file_diff("src/kept.py")
        excluded = excluded_fixture_diff().encode("utf-8")
        result = self.run_setup(workflow="hard", gh_diff=excluded + kept, head_sha=VALID_HEAD_SHA)

        _, run_dir = self.assert_ready_receipt_matches_saved_input(result, "file")
        excluded_path = run_dir / "diff" / "excluded-files.txt"
        self.assertEqual(excluded_path.read_text(encoding="utf-8").splitlines(), ["tests/fixtures/data.json"])

    def test_manifest_and_run_policy_are_valid_json_for_fast_and_hard(self):
        for workflow in ("fast", "hard"):
            with self.subTest(workflow=workflow):
                with tempfile.TemporaryDirectory() as name:
                    case = self.prepare_case(Path(name))
                    result = self.run_setup(
                        workflow=workflow,
                        case=case,
                        staged_diff=one_file_diff(),
                        gh_diff=one_file_diff(),
                        head_sha=VALID_HEAD_SHA if workflow == "hard" else None,
                    )
                    receipt, run_dir = self.assert_ready_receipt_matches_saved_input(
                        result, "file" if workflow == "hard" else "staged"
                    )
                    manifest = json.loads((run_dir / receipt["manifest"]).read_text(encoding="utf-8"))
                    policy = json.loads((run_dir / receipt["run_policy"]).read_text(encoding="utf-8"))
                    self.assertEqual(MAGI_AGGREGATE.validate_manifest(manifest), manifest)
                    self.assertEqual(MAGI_AGGREGATE.validate_policy(policy), policy)
                    self.assertEqual(policy["workflow"], workflow)
                    self.assertEqual(policy["diff_source"]["kind"], receipt["diff_source"]["kind"])

    def test_hard_rejects_invalid_or_missing_head_sha_for_pr_anchors(self):
        cases = [
            ("bad-head-sha", "not-a-sha", policy_value("hard", anchor_policy="pr", head_sha=VALID_HEAD_SHA, diff_kind="file")),
            ("missing-head-sha", None, policy_value("hard", anchor_policy="pr", head_sha=None, diff_kind="file")),
        ]
        for label, head_sha, policy in cases:
            with self.subTest(label=label):
                result = self.run_setup(
                    workflow="hard",
                    gh_diff=one_file_diff(),
                    policy=policy,
                    head_sha=head_sha,
                )
                self.assertEqual(result.returncode, 2)
                self.assertIn("configuration_error", result.stderr)

    def test_fast_rejects_head_sha_in_none_anchor_policy(self):
        policy = policy_value("fast", anchor_policy="none", head_sha=VALID_HEAD_SHA, diff_kind="staged")
        result = self.run_setup(staged_diff=one_file_diff(), policy=policy)

        self.assertEqual(result.returncode, 2)
        self.assertIn("configuration_error", result.stderr)

    def test_path_safety_rejects_symlink_components(self):
        diff = one_file_diff()
        diff_hash = sha256(diff)
        cases = [
            ("cache", lambda c: self.symlink_component(c.home / ".cache")),
            ("magi", lambda c: self.symlink_component(c.home / ".cache" / "magi")),
            ("runs", lambda c: self.symlink_component(c.home / ".cache" / "magi" / "runs")),
            ("diff-hash", lambda c: self.symlink_component(c.home / ".cache" / "magi" / "runs" / diff_hash)),
            ("run-dir", lambda c: self.symlink_component(c.home / ".cache" / "magi" / "runs" / diff_hash / RUN_ID_1)),
            ("subdir", lambda c: None),
        ]
        for label, prepare in cases:
            with self.subTest(label=label):
                with tempfile.TemporaryDirectory() as name:
                    case = self.prepare_case(Path(name))
                    prepare(case)
                    env_extra = {"MAGI_RUN_SETUP_TEST_RUN_IDS": RUN_ID_1}
                    if label == "subdir":
                        env_extra["MAGI_RUN_SETUP_TEST_PRECREATE_SUBDIR_SYMLINK"] = "diff"
                    result = self.run_setup(
                        case=case,
                        staged_diff=diff,
                        env_extra=env_extra,
                    )
                    self.assertEqual(result.returncode, 2)
                    self.assertIn("configuration_error", result.stderr)

    def symlink_component(self, path):
        real = path.parent / ("%s-real" % path.name)
        path.parent.mkdir(parents=True, exist_ok=True)
        real.mkdir(parents=True, exist_ok=True)
        path.symlink_to(real, target_is_directory=True)

    def test_exclusive_create_retries_only_existing_run_id_collisions(self):
        diff = one_file_diff()
        diff_hash = sha256(diff)
        existing = self.case.home / ".cache" / "magi" / "runs" / diff_hash / RUN_ID_1
        existing.mkdir(parents=True)
        result = self.run_setup(
            staged_diff=diff,
            env_extra={"MAGI_RUN_SETUP_TEST_RUN_IDS": "%s:%s" % (RUN_ID_1, RUN_ID_2)},
        )

        receipt, run_dir = self.assert_ready_receipt_matches_saved_input(result, "staged")
        self.assertEqual(receipt["run_id"], RUN_ID_2)
        self.assertEqual(run_dir.name, RUN_ID_2)

    def test_exclusive_create_fails_after_five_run_id_collisions(self):
        diff = one_file_diff()
        diff_hash = sha256(diff)
        for run_id in (RUN_ID_1, RUN_ID_2, RUN_ID_3, RUN_ID_4, RUN_ID_5):
            (self.case.home / ".cache" / "magi" / "runs" / diff_hash / run_id).mkdir(parents=True)
        result = self.run_setup(
            staged_diff=diff,
            env_extra={"MAGI_RUN_SETUP_TEST_RUN_IDS": ":".join([RUN_ID_1, RUN_ID_2, RUN_ID_3, RUN_ID_4, RUN_ID_5])},
        )

        self.assertEqual(result.returncode, 1)
        self.assertIn("run id collision", result.stderr.lower())

    def test_input_identity_mismatch_after_save_is_fatal(self):
        result = self.run_setup(
            staged_diff=one_file_diff(),
            env_extra={"MAGI_RUN_SETUP_TEST_CORRUPT_INPUT_AFTER_WRITE": "1"},
        )

        self.assertEqual(result.returncode, 1)
        self.assertIn("input identity", result.stderr.lower())

    def make_existing_run(self, run_id, days_ago=1, diff_hash=None, case=None):
        case = case or self.case
        diff_hash = diff_hash or ("a" * 64)
        run = case.home / ".cache" / "magi" / "runs" / diff_hash / run_id
        (run / "diff").mkdir(parents=True)
        (run / "diff" / "input.filtered.patch").write_bytes(one_file_diff("src/old.py"))
        timestamp = time.time() - days_ago * 86400
        os.utime(run, (timestamp, timestamp))
        return run

    def test_prune_removes_old_age_and_count_overflow_runs_only(self):
        old_by_age = self.make_existing_run("20260701T010101Z-1111-aaaabbbb", days_ago=15, diff_hash="a" * 64)
        old_by_count = self.make_existing_run("20260702T010101Z-1111-bbbbcccc", days_ago=3, diff_hash="b" * 64)
        kept_recent = []
        for index in range(20):
            run = self.make_existing_run(
                "202607%02dT010101Z-1111-%08x" % (index + 3, index + 1),
                days_ago=1 + index / 1000,
                diff_hash=("%064x" % (index + 10)),
            )
            kept_recent.append(run)

        result = self.run_setup(staged_diff=one_file_diff(), env_extra={"MAGI_RUN_SETUP_TEST_RUN_IDS": RUN_ID_1})

        _, current = self.assert_ready_receipt_matches_saved_input(result, "staged")
        self.assertFalse(old_by_age.exists())
        self.assertFalse(old_by_count.exists())
        for run in kept_recent:
            self.assertTrue(run.exists(), str(run))
        self.assertTrue(current.exists())

    def test_prune_never_removes_current_run(self):
        result = self.run_setup(
            staged_diff=one_file_diff(),
            env_extra={
                "MAGI_RUN_SETUP_TEST_RUN_IDS": RUN_ID_1,
                "MAGI_RUN_SETUP_TEST_CURRENT_MTIME_DAYS_AGO": "30",
            },
        )

        _, current = self.assert_ready_receipt_matches_saved_input(result, "staged")
        self.assertTrue(current.exists())

    def test_prune_warns_and_keeps_unsafe_or_malformed_candidates(self):
        runs = self.case.home / ".cache" / "magi" / "runs"
        bad_hash_run = runs / "not-a-hash" / "20260701T010101Z-1111-aaaabbbb"
        bad_hash_run.mkdir(parents=True)
        bad_run_id = self.make_existing_run("bad-run-id", days_ago=30, diff_hash="c" * 64)
        outside = self.case.root / "outside"
        outside.mkdir()
        symlink_run = runs / ("d" * 64) / "20260701T010101Z-1111-ddddeeee"
        symlink_run.parent.mkdir(parents=True)
        symlink_run.symlink_to(outside, target_is_directory=True)
        symlink_hash = runs / ("e" * 64)
        symlink_hash.symlink_to(outside, target_is_directory=True)

        result = self.run_setup(staged_diff=one_file_diff(), env_extra={"MAGI_RUN_SETUP_TEST_RUN_IDS": RUN_ID_1})

        self.assertEqual(result.returncode, 0, result.stderr)
        self.parse_stdout_object(result)
        self.assertIn("warning", result.stderr.lower())
        self.assertTrue(bad_hash_run.exists())
        self.assertTrue(bad_run_id.exists())
        self.assertTrue(symlink_run.is_symlink())
        self.assertTrue(symlink_hash.is_symlink())

    def test_stdout_is_exactly_one_json_object(self):
        result = self.run_setup(staged_diff=one_file_diff(), env_extra={"MAGI_RUN_SETUP_TEST_RUN_IDS": RUN_ID_1})

        self.assertEqual(result.returncode, 0, result.stderr)
        receipt = self.parse_stdout_object(result)
        self.assertEqual(receipt["status"], "ready")

    def test_code_only_diff_records_magi_review_route_on_ready_receipt(self):
        diff = one_file_diff("src/review_target.py")
        result = self.run_setup(staged_diff=diff, env_extra={"MAGI_RUN_SETUP_TEST_RUN_IDS": RUN_ID_1})

        receipt, run_dir = self.assert_ready_receipt_matches_saved_input(result, "staged")
        self.assertEqual(receipt["review_route"], "magi")
        route_artifact = json.loads((run_dir / "review-route.json").read_text(encoding="utf-8"))
        self.assertEqual(route_artifact["schema_version"], "magi-review-route/v1")
        self.assertEqual(route_artifact["review_route"], "magi")
        self.assertEqual(route_artifact["raw_diff_sha256"], sha256(diff))
        self.assertEqual(route_artifact["filtered_diff_sha256"], sha256(diff))
        self.assertEqual(route_artifact["path_summary"]["paths"], ["src/review_target.py"])

    def test_dockerfile_only_diff_records_magi_review_route(self):
        diff = one_file_diff("Dockerfile")
        result = self.run_setup(staged_diff=diff, env_extra={"MAGI_RUN_SETUP_TEST_RUN_IDS": RUN_ID_1})

        receipt, run_dir = self.assert_ready_receipt_matches_saved_input(result, "staged")
        self.assertEqual(receipt["review_route"], "magi")
        route_artifact = json.loads((run_dir / "review-route.json").read_text(encoding="utf-8"))
        self.assertEqual(route_artifact["review_route"], "magi")
        self.assertEqual(route_artifact["path_summary"]["unknown_paths"], ["Dockerfile"])
        self.assertIn("implementation_adjacent_unknown_only", route_artifact["matched_rules"])

    def test_mixed_filtered_code_routes_to_magi_after_prompt_paths_are_removed(self):
        kept = one_file_diff("src/app.py")
        removed = one_file_diff("skills/example/SKILL.md")
        raw = kept + removed
        result = self.run_setup(staged_diff=raw, env_extra={"MAGI_RUN_SETUP_TEST_RUN_IDS": RUN_ID_1})

        receipt, run_dir = self.assert_ready_receipt_matches_saved_input(result, "staged")
        self.assertEqual(receipt["review_route"], "magi")
        route_artifact = json.loads((run_dir / "review-route.json").read_text(encoding="utf-8"))
        self.assertEqual(route_artifact["review_route"], "magi")
        self.assertEqual(route_artifact["raw_diff_sha256"], sha256(raw))
        self.assertEqual(route_artifact["filtered_diff_sha256"], sha256(kept))
        self.assertEqual(route_artifact["path_summary"]["paths"], ["src/app.py"])

    def test_docs_only_filtered_empty_diff_creates_route_only_run(self):
        diff = one_file_diff("skills/example/SKILL.md")
        result = self.run_setup(staged_diff=diff, env_extra={"MAGI_RUN_SETUP_TEST_RUN_IDS": RUN_ID_1})

        self.assertEqual(result.returncode, 0, result.stderr)
        receipt = self.parse_stdout_object(result)
        self.assertEqual(receipt["status"], "routed")
        self.assertEqual(receipt["review_route"], "codex")
        self.assertEqual(receipt["diff_hash"], sha256(b""))
        run_dir = Path(receipt["run_dir"])
        self.assertTrue(run_dir.is_dir())
        self.assertEqual(run_dir.parent.name, sha256(b""))

        route_artifact = json.loads((run_dir / "review-route.json").read_text(encoding="utf-8"))
        self.assertEqual(route_artifact["schema_version"], "magi-review-route/v1")
        self.assertEqual(route_artifact["review_route"], "codex")
        self.assertEqual(route_artifact["raw_diff_sha256"], sha256(diff))
        self.assertEqual(route_artifact["filtered_diff_sha256"], sha256(b""))
        self.assertEqual(route_artifact["path_summary"]["paths"], ["skills/example/SKILL.md"])
        self.assertFalse((run_dir / "manifest.json").exists())
        self.assertFalse((run_dir / "run-policy.json").exists())
        self.assertFalse((run_dir / "diff" / "input.filtered.patch").exists())

    def test_magi_infrastructure_script_and_test_mix_records_manual_confirm_route(self):
        diff = one_file_diff("scripts/magi-persona-runner.py") + one_file_diff(
            "scripts/tests/test_magi_persona_runner.py"
        )
        result = self.run_setup(staged_diff=diff, env_extra={"MAGI_RUN_SETUP_TEST_RUN_IDS": RUN_ID_1})

        self.assertEqual(result.returncode, 0, result.stderr)
        receipt = self.parse_stdout_object(result)
        self.assertEqual(receipt["review_route"], "manual_confirm")
        run_dir = Path(receipt["run_dir"])
        route_artifact = json.loads((run_dir / "review-route.json").read_text(encoding="utf-8"))
        self.assertEqual(route_artifact["schema_version"], "magi-review-route/v1")
        self.assertEqual(route_artifact["review_route"], "manual_confirm")
        self.assertEqual(
            route_artifact["path_summary"]["magi_infrastructure_scripts"],
            ["scripts/magi-persona-runner.py"],
        )
        self.assertEqual(
            route_artifact["path_summary"]["magi_infrastructure_tests"],
            ["scripts/tests/test_magi_persona_runner.py"],
        )

    def test_empty_raw_and_filtered_diff_keeps_existing_empty_contract(self):
        result = self.run_setup(staged_diff=b"", head_diff=b"", env_extra={"MAGI_RUN_SETUP_TEST_RUN_IDS": RUN_ID_1})

        self.assertEqual(result.returncode, 0, result.stderr)
        receipt = self.parse_stdout_object(result)
        self.assertEqual(receipt["status"], "empty")
        self.assertEqual(receipt["workflow"], "fast")
        self.assertEqual(receipt["diff_source"]["kind"], "head")
        self.assertEqual(self.iter_run_dirs(), [])

    def test_review_route_artifact_preserves_router_schema_fields(self):
        diff = one_file_diff("src/calculator.py")
        expected_fields = {
            "schema_version",
            "review_route",
            "magi_skipped",
            "reason",
            "fallback",
            "confidence",
            "matched_rules",
            "path_summary",
            "raw_diff_sha256",
            "filtered_diff_sha256",
            "decision_source",
        }
        result = self.run_setup(staged_diff=diff, env_extra={"MAGI_RUN_SETUP_TEST_RUN_IDS": RUN_ID_1})

        receipt, run_dir = self.assert_ready_receipt_matches_saved_input(result, "staged")
        route_artifact = json.loads((run_dir / "review-route.json").read_text(encoding="utf-8"))
        self.assertTrue(expected_fields <= set(route_artifact))
        self.assertEqual(route_artifact["schema_version"], "magi-review-route/v1")
        self.assertEqual(route_artifact["review_route"], receipt["review_route"])
        self.assertEqual(route_artifact["magi_skipped"], False)
        self.assertIsNone(route_artifact["fallback"])
        self.assertGreaterEqual(route_artifact["confidence"], 0)
        self.assertLessEqual(route_artifact["confidence"], 1)
        self.assertEqual(route_artifact["raw_diff_sha256"], sha256(diff))
        self.assertEqual(route_artifact["filtered_diff_sha256"], sha256(diff))
        self.assertEqual(route_artifact["decision_source"], "path_metadata")

    def test_route_only_run_rejects_symlinked_filtered_empty_hash_directory(self):
        diff = one_file_diff("skills/example/SKILL.md")
        empty_hash_dir = self.case.home / ".cache" / "magi" / "runs" / sha256(b"")
        self.symlink_component(empty_hash_dir)
        result = self.run_setup(staged_diff=diff, env_extra={"MAGI_RUN_SETUP_TEST_RUN_IDS": RUN_ID_1})

        self.assertEqual(result.returncode, 2)
        self.assertIn("configuration_error", result.stderr)


if __name__ == "__main__":
    unittest.main()
