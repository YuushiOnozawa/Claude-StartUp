import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path
from types import SimpleNamespace


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "dev-flow-test-gate.py"
ROUTER = ROOT / "scripts" / "magi-review-router.py"


def diff_for(path, added_lines=None):
    added_lines = added_lines or ["changed"]
    return (
        "diff --git a/%s b/%s\n"
        "index 1111111..2222222 100644\n"
        "--- a/%s\n"
        "+++ b/%s\n"
        "@@ -1 +1,%d @@\n" % (path, path, path, path, len(added_lines))
        + "".join("+%s\n" % line for line in added_lines)
    )


def rename_diff(old_path, new_path):
    return (
        "diff --git a/%s b/%s\n"
        "similarity index 100%%\n"
        "rename from %s\n"
        "rename to %s\n" % (old_path, new_path, old_path, new_path)
    )


class DevFlowTestGateTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.case = self.prepare_case(Path(self.temporary.name))

    def prepare_case(self, root, shellcheck="pass"):
        case = SimpleNamespace(
            root=root,
            home=root / "home",
            repo=root / "repo",
            bin=root / "bin",
        )
        case.home.mkdir()
        (case.repo / "scripts" / "tests").mkdir(parents=True)
        case.bin.mkdir()
        shutil.copy2(ROUTER, case.repo / "scripts" / "magi-review-router.py")
        self.write_executable(case.bin / "git", self.fake_git_source())
        self.write_executable(case.bin / "gh", "#!/bin/sh\nexit 0\n")
        self.symlink_tool(case.bin / "python3", Path(sys.executable))
        self.symlink_tool(case.bin / "python", Path(sys.executable))
        self.symlink_tool(case.bin / "bash", Path(shutil.which("bash") or "/bin/bash"))
        if shellcheck == "pass":
            self.write_executable(case.bin / "shellcheck", "#!/bin/sh\nexit 0\n")
        elif shellcheck == "fail":
            self.write_executable(
                case.bin / "shellcheck",
                "#!/bin/sh\nprintf 'SC9999: forced shellcheck failure\\n' >&2\nexit 1\n",
            )
        return case

    def symlink_tool(self, link, target):
        try:
            link.symlink_to(target)
        except FileExistsError:
            pass

    def write_executable(self, path, text):
        path.write_text(text, encoding="utf-8")
        path.chmod(path.stat().st_mode | stat.S_IXUSR)

    def fake_git_source(self):
        return textwrap.dedent(
            """\
            #!%s
            import os
            import shutil
            import sys
            from pathlib import Path

            args = sys.argv[1:]
            cwd = Path(os.getcwd())
            if len(args) >= 2 and args[0] == "-C":
                cwd = Path(args[1])
                args = args[2:]

            def write(value):
                sys.stdout.write(value)
                if value and not value.endswith("\\n"):
                    sys.stdout.write("\\n")

            def derive_name_only(value):
                paths = []
                for line in value.splitlines():
                    fields = line.split("\\t")
                    if not fields:
                        continue
                    if fields[0].startswith("R") and len(fields) >= 3:
                        paths.extend(fields[1:3])
                    elif len(fields) >= 2:
                        paths.append(fields[1])
                return "\\n".join(paths)

            if args[:1] == ["diff"]:
                name_status = os.environ.get("MAGI_TEST_NAME_STATUS", "")
                if "--name-status" in args:
                    write(name_status)
                    raise SystemExit(0)
                if "--name-only" in args:
                    write(os.environ.get("MAGI_TEST_NAME_ONLY", derive_name_only(name_status)))
                    raise SystemExit(0)
                write(os.environ.get("MAGI_TEST_DIFF", ""))
                raise SystemExit(0)

            if args[:2] == ["worktree", "add"]:
                destination = None
                for item in args[2:]:
                    if item == "HEAD" or item.startswith("-"):
                        continue
                    destination = Path(item)
                    break
                if destination is None:
                    print("missing worktree destination", file=sys.stderr)
                    raise SystemExit(99)
                if destination.exists():
                    shutil.rmtree(destination)
                ignore = shutil.ignore_patterns(".git", "test-gate")
                shutil.copytree(cwd, destination, ignore=ignore)
                marker = destination / ".force-test-fail"
                baseline_mode = os.environ.get("MAGI_TEST_BASELINE_MODE", "pass")
                if baseline_mode == "pass":
                    try:
                        marker.unlink()
                    except FileNotFoundError:
                        pass
                elif baseline_mode == "fail":
                    marker.write_text("fail\\n", encoding="utf-8")
                raise SystemExit(0)

            if args[:2] == ["worktree", "remove"]:
                target = Path(args[-1])
                if target.exists():
                    shutil.rmtree(target)
                raise SystemExit(0)

            if args[:2] == ["rev-parse", "--show-toplevel"]:
                write(str(cwd))
                raise SystemExit(0)

            if args[:1] == ["rev-parse"]:
                write("0123456789abcdef0123456789abcdef01234567")
                raise SystemExit(0)

            if args[:2] == ["status", "--porcelain"]:
                write(os.environ.get("MAGI_TEST_STATUS", ""))
                raise SystemExit(0)

            if args[:1] == ["ls-files"]:
                files = []
                for path in cwd.rglob("*"):
                    if path.is_file() and "test-gate" not in path.parts:
                        files.append(str(path.relative_to(cwd)))
                write("\\n".join(sorted(files)))
                raise SystemExit(0)

            print("unexpected git args: " + " ".join(args), file=sys.stderr)
            raise SystemExit(99)
            """
            % sys.executable
        )

    def write_plan(self, target_files, approved=True, case=None):
        case = case or self.case
        path = case.root / "plan-receipt.json"
        path.write_text(
            json.dumps(
                {
                    "schema_version": "plan-receipt/v1",
                    "approved": approved,
                    "target_files": target_files,
                }
            ),
            encoding="utf-8",
        )
        return path

    def write_file(self, relative_path, text="", case=None, executable=False):
        case = case or self.case
        path = case.repo / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        if executable:
            path.chmod(path.stat().st_mode | stat.S_IXUSR)
        return path

    def write_python_test(self, relative_path, mode="pass", case=None):
        body = "import unittest\n\n\nclass GeneratedTest(unittest.TestCase):\n"
        if mode == "marker":
            body += (
                "    def test_marker_controls_result(self):\n"
                "        from pathlib import Path\n"
                "        self.assertFalse(Path.cwd().joinpath(\".force-test-fail\").exists())\n"
            )
        elif mode == "slow":
            body += (
                "    def test_slow(self):\n"
                "        import time\n"
                "        time.sleep(3)\n"
            )
        else:
            body += "    def test_passes(self):\n        self.assertTrue(True)\n"
        body += "\n\nif __name__ == '__main__':\n    unittest.main()\n"
        return self.write_file(relative_path, body, case=case)

    def write_shell_test(self, relative_path, exit_code=0, case=None):
        return self.write_file(
            relative_path,
            "#!/usr/bin/env bash\nexit %d\n" % exit_code,
            case=case,
            executable=True,
        )

    def run_gate(
        self,
        target_files,
        *,
        changed_files=None,
        name_status=None,
        diff=None,
        attempt=1,
        timeout_seconds=120,
        case=None,
        env_extra=None,
    ):
        case = case or self.case
        if changed_files is None:
            changed_files = target_files
        if name_status is None:
            name_status = "".join("M\t%s\n" % path for path in changed_files)
        if diff is None:
            diff = "".join(diff_for(path) for path in changed_files)
        plan = self.write_plan(target_files, case=case)
        env = {
            **os.environ,
            "HOME": str(case.home),
            "PATH": str(case.bin),
            "MAGI_TEST_NAME_STATUS": name_status,
            "MAGI_TEST_DIFF": diff,
            "MAGI_TEST_REPO_ROOT": str(case.repo),
        }
        if env_extra:
            env.update(env_extra)
        result = subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                "--repo-root",
                str(case.repo),
                "--plan-receipt",
                str(plan),
                "--attempt",
                str(attempt),
                "--timeout-seconds",
                str(timeout_seconds),
            ],
            text=True,
            capture_output=True,
            env=env,
        )
        return result

    def load_receipt(self, attempt=1, case=None):
        case = case or self.case
        path = case.repo / "test-gate" / ("attempt-%d" % attempt) / "receipt.json"
        self.assertTrue(path.is_file(), "missing receipt artifact: %s" % path)
        receipt = json.loads(path.read_text(encoding="utf-8"))
        self.assertEqual(receipt["schema_version"], "dev-flow-test-gate/v1")
        self.assertIn("status", receipt)
        self.assertIn("review_route", receipt)
        self.assertIn("commands", receipt)
        self.assertIn("environment", receipt)
        self.assertIn("timeout", receipt)
        self.assertIn("derived_target_tests", receipt)
        self.assertIn("unavailable", receipt)
        self.assertIn("baseline", receipt)
        self.assertIn("current", receipt)
        self.assertIn("scope_violations", receipt)
        return receipt

    def assert_gate_passed(self, result, case=None):
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(result.stdout.strip())
        receipt = self.load_receipt(case=case)
        self.assertEqual(receipt["status"], "pass")
        return receipt

    def assert_gate_failed(self, result, case=None):
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(result.stdout.strip() or result.stderr.strip())
        return self.load_receipt(case=case)

    def test_magi_review_router_change_derives_matching_targeted_test(self):
        self.write_python_test("scripts/tests/test_magi_review_router.py")

        result = self.run_gate(["scripts/magi-review-router.py"])

        receipt = self.assert_gate_passed(result)
        self.assertEqual(receipt["review_route"], "magi")
        self.assertEqual(receipt["derived_target_tests"], ["scripts/tests/test_magi_review_router.py"])

    def test_magi_diff_filter_change_derives_shell_test_and_override_python_test(self):
        self.write_file("scripts/magi-diff-filter.sh", "#!/usr/bin/env bash\nexit 0\n", executable=True)
        self.write_shell_test("scripts/test-magi-diff-filter.sh")
        self.write_python_test("scripts/tests/test_magi_diff_scripts.py")

        result = self.run_gate(["scripts/magi-diff-filter.sh"])

        receipt = self.assert_gate_passed(result)
        self.assertEqual(
            receipt["derived_target_tests"],
            ["scripts/test-magi-diff-filter.sh", "scripts/tests/test_magi_diff_scripts.py"],
        )

    def test_magi_split_hunk_change_derives_override_python_test(self):
        self.write_file("scripts/magi-split-hunk.sh", "#!/usr/bin/env bash\nexit 0\n", executable=True)
        self.write_python_test("scripts/tests/test_magi_diff_scripts.py")

        result = self.run_gate(["scripts/magi-split-hunk.sh"])

        receipt = self.assert_gate_passed(result)
        self.assertEqual(receipt["derived_target_tests"], ["scripts/tests/test_magi_diff_scripts.py"])

    def test_missing_matching_test_is_recorded_as_unavailable_without_failing_by_itself(self):
        self.write_file("scripts/foo.py", "print('hello')\n")

        result = self.run_gate(["scripts/foo.py"])

        receipt = self.assert_gate_passed(result)
        self.assertIn("unavailable_count=1", result.stdout)
        self.assertEqual(receipt["unavailable"]["count"], 1)
        self.assertEqual(receipt["unavailable"]["files"], ["scripts/tests/test_foo.py"])

    def test_codex_metadata_route_skips_test_gate_and_writes_skip_receipt(self):
        self.write_file("docs/traceability/review.md", "# note\n")

        result = self.run_gate(["docs/traceability/review.md"])

        self.assertEqual(result.returncode, 0, result.stderr)
        receipt = self.load_receipt()
        self.assertEqual(receipt["status"], "skip")
        self.assertEqual(receipt["review_route"], "codex")
        self.assertEqual(receipt["commands"], [])

    def test_manual_confirm_route_runs_targeted_tests_and_required_suite(self):
        self.write_file("scripts/magi-persona-runner.py", "print('runner')\n")
        self.write_python_test("scripts/tests/test_magi_persona_runner.py")

        result = self.run_gate(
            ["scripts/magi-persona-runner.py", "scripts/tests/test_magi_persona_runner.py"],
            diff=diff_for("scripts/magi-persona-runner.py")
            + diff_for("scripts/tests/test_magi_persona_runner.py"),
        )

        receipt = self.assert_gate_passed(result)
        self.assertEqual(receipt["review_route"], "manual_confirm")
        self.assertIn("targeted_tests", receipt["current"])
        self.assertIn("required_suite", receipt["current"])

    def test_current_only_targeted_test_failure_is_classified_as_regression(self):
        self.write_python_test("scripts/tests/test_magi_review_router.py", mode="marker")
        self.write_file(".force-test-fail", "fail\n")

        result = self.run_gate(["scripts/magi-review-router.py"], env_extra={"MAGI_TEST_BASELINE_MODE": "pass"})

        receipt = self.assert_gate_failed(result)
        self.assertEqual(receipt["status"], "fail")
        self.assertIn("scripts/tests/test_magi_review_router.py", receipt["current"]["regressions"])
        self.assertNotIn("scripts/tests/test_magi_review_router.py", receipt["current"]["pre_existing_failures"])

    def test_baseline_and_current_targeted_test_failure_is_pre_existing_failure(self):
        self.write_python_test("scripts/tests/test_magi_review_router.py", mode="marker")
        self.write_file(".force-test-fail", "fail\n")

        result = self.run_gate(["scripts/magi-review-router.py"], env_extra={"MAGI_TEST_BASELINE_MODE": "fail"})

        receipt = self.assert_gate_passed(result)
        self.assertIn("scripts/tests/test_magi_review_router.py", receipt["current"]["pre_existing_failures"])
        self.assertNotIn("scripts/tests/test_magi_review_router.py", receipt["current"]["regressions"])

    def test_bash_syntax_failure_stops_gate_and_persists_syntax_log(self):
        self.write_file("scripts/magi-diff-filter.sh", "if true; then\n", executable=True)
        self.write_shell_test("scripts/test-magi-diff-filter.sh")
        self.write_python_test("scripts/tests/test_magi_diff_scripts.py")

        result = self.run_gate(["scripts/magi-diff-filter.sh"])

        receipt = self.assert_gate_failed(result)
        self.assertEqual(receipt["status"], "fail")
        bash_n = [entry for entry in receipt["commands"] if entry.get("kind") == "bash_n"]
        self.assertTrue(bash_n)
        log_path = self.case.repo / bash_n[0]["stderr_artifact"]
        self.assertTrue(log_path.is_file())
        self.assertIn("syntax", log_path.read_text(encoding="utf-8").lower())

    def test_shellcheck_failure_is_recorded_as_gate_failure_when_shellcheck_exists(self):
        self.temporary.cleanup()
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.case = self.prepare_case(Path(self.temporary.name), shellcheck="fail")
        self.write_file("scripts/magi-diff-filter.sh", "#!/usr/bin/env bash\nexit 0\n", executable=True)
        self.write_shell_test("scripts/test-magi-diff-filter.sh")
        self.write_python_test("scripts/tests/test_magi_diff_scripts.py")

        result = self.run_gate(["scripts/magi-diff-filter.sh"])

        receipt = self.assert_gate_failed(result)
        shellcheck = [entry for entry in receipt["commands"] if entry.get("kind") == "shellcheck"]
        self.assertTrue(shellcheck)
        self.assertEqual(shellcheck[0]["status"], "fail")

    def test_missing_shellcheck_is_unavailable_but_does_not_fail_gate(self):
        self.temporary.cleanup()
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.case = self.prepare_case(Path(self.temporary.name), shellcheck="missing")
        self.write_file("scripts/magi-diff-filter.sh", "#!/usr/bin/env bash\nexit 0\n", executable=True)
        self.write_shell_test("scripts/test-magi-diff-filter.sh")
        self.write_python_test("scripts/tests/test_magi_diff_scripts.py")

        result = self.run_gate(["scripts/magi-diff-filter.sh"])

        receipt = self.assert_gate_passed(result)
        self.assertIn("shellcheck", receipt["unavailable"]["tools"])
        self.assertEqual(receipt["unavailable"]["count"], 1)

    def test_changed_file_outside_plan_targets_stops_as_scope_violation(self):
        self.write_python_test("scripts/tests/test_magi_review_router.py")
        self.write_file("scripts/unplanned.py", "print('nope')\n")

        result = self.run_gate(
            ["scripts/magi-review-router.py"],
            changed_files=["scripts/magi-review-router.py", "scripts/unplanned.py"],
        )

        receipt = self.assert_gate_failed(result)
        self.assertEqual(receipt["status"], "scope_violation")
        self.assertIn("scripts/unplanned.py", receipt["scope_violations"]["files"])

    def test_derived_target_tests_are_added_to_scope_allowlist(self):
        self.write_python_test("scripts/tests/test_magi_review_router.py")

        result = self.run_gate(
            ["scripts/magi-review-router.py"],
            changed_files=["scripts/magi-review-router.py", "scripts/tests/test_magi_review_router.py"],
            name_status="M\tscripts/magi-review-router.py\nA\tscripts/tests/test_magi_review_router.py\n",
        )

        receipt = self.assert_gate_passed(result)
        self.assertEqual(receipt["scope_violations"]["files"], [])
        self.assertEqual(receipt["derived_target_tests"], ["scripts/tests/test_magi_review_router.py"])

    def test_rename_requires_old_and_new_path_to_be_allowed(self):
        self.write_python_test("scripts/tests/test_new_name.py")
        allowed = self.run_gate(
            ["scripts/old_name.py", "scripts/new_name.py"],
            name_status="R100\tscripts/old_name.py\tscripts/new_name.py\n",
            diff=rename_diff("scripts/old_name.py", "scripts/new_name.py"),
        )
        self.assert_gate_passed(allowed)

        with tempfile.TemporaryDirectory() as name:
            case = self.prepare_case(Path(name))
            self.write_python_test("scripts/tests/test_new_name.py", case=case)
            outside = self.run_gate(
                ["scripts/new_name.py"],
                name_status="R100\tscripts/old_name.py\tscripts/new_name.py\n",
                diff=rename_diff("scripts/old_name.py", "scripts/new_name.py"),
                case=case,
            )
            receipt = self.assert_gate_failed(outside, case=case)
            self.assertEqual(receipt["status"], "scope_violation")
            self.assertIn("scripts/old_name.py", receipt["scope_violations"]["files"])

    def test_unsafe_plan_target_paths_are_rejected_before_execution(self):
        real = self.case.repo / "real"
        real.mkdir()
        (self.case.repo / "linked").symlink_to(real, target_is_directory=True)
        cases = [
            [str(self.case.repo / "scripts" / "magi-review-router.py")],
            ["../outside.py"],
            ["linked/file.py"],
        ]
        for target_files in cases:
            with self.subTest(target_files=target_files):
                with tempfile.TemporaryDirectory() as name:
                    case = self.prepare_case(Path(name))
                    real = case.repo / "real"
                    real.mkdir()
                    (case.repo / "linked").symlink_to(real, target_is_directory=True)
                    result = self.run_gate(target_files, case=case)
                    receipt = self.assert_gate_failed(result, case=case)
                    self.assertEqual(receipt["status"], "configuration_error")
                    self.assertIn("target_files", receipt["scope_violations"]["reason"])

    def test_required_suite_runs_separately_from_targeted_tests(self):
        self.write_python_test("scripts/tests/test_magi_review_router.py")
        self.write_python_test("scripts/tests/test_magi_diff_scripts.py")

        result = self.run_gate(["scripts/magi-review-router.py"])

        receipt = self.assert_gate_passed(result)
        self.assertIn("targeted_tests", receipt["baseline"])
        self.assertIn("required_suite", receipt["baseline"])
        self.assertIn("targeted_tests", receipt["current"])
        self.assertIn("required_suite", receipt["current"])
        self.assertNotEqual(receipt["current"]["targeted_tests"], receipt["current"]["required_suite"])

    def test_gate_timeout_records_completed_and_pending_commands(self):
        self.write_python_test("scripts/tests/test_magi_review_router.py", mode="slow")

        result = self.run_gate(["scripts/magi-review-router.py"], timeout_seconds=1)

        receipt = self.assert_gate_failed(result)
        self.assertEqual(receipt["status"], "timeout")
        self.assertTrue(receipt["timeout"]["timed_out"])
        statuses = [entry["status"] for entry in receipt["commands"]]
        self.assertIn("completed", statuses)
        self.assertIn("pending", statuses)


if __name__ == "__main__":
    unittest.main()
