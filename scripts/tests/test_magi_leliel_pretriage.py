"""Fixtures and regression tests for the dormant LELIEL pre-triage CLI."""
import importlib.util
import json
import os
import stat
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest import mock
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "magi-leliel-pretriage.py"
FIXTURES = Path(__file__).parent / "fixtures" / "leliel-pretriage"
SPEC = importlib.util.spec_from_file_location("leliel_pretriage", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class LelielPretriageTest(unittest.TestCase):
    def make_repo(self, source="def create_user(name, role):\n    return name\n", caller="create_user('a', 'user')\n"):
        temp = tempfile.TemporaryDirectory()
        root = Path(temp.name) / "repo"
        (root / "src").mkdir(parents=True)
        (root / "src" / "api.py").write_text(source, encoding="utf-8")
        (root / "src" / "caller.py").write_text(caller, encoding="utf-8")
        tracked = Path(temp.name) / "tracked.nul"
        tracked.write_bytes(b"src/api.py\0src/caller.py\0")
        return temp, root, tracked

    def run_prepare(self, patch, root, tracked, temp, added=None, environment=None):
        diff = Path(temp.name) / "input.patch"
        diff.write_bytes(Path(patch).read_bytes())
        output, audit = Path(temp.name) / "output", Path(temp.name) / "audit"
        command = [sys.executable, str(SCRIPT), "prepare", "--diff-file", str(diff), "--repo-root", str(root),
                   "--output-dir", str(output), "--audit-dir", str(audit), "--tracked-files", str(tracked)]
        if added:
            command += ["--added-response", str(added)]
        extra_environment = environment or {}
        environment = dict(os.environ)
        environment.update({"MAGI_CODEGRAPH": "definitely-not-codegraph"})
        environment.update(extra_environment)
        completed = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=environment)
        self.assertEqual(completed.returncode, 0, completed.stderr)
        return output, audit

    def artifact_for_added(self, catalog, additions):
        return json.dumps({"schema_version": MODULE.ADDED_SCHEMA,
                           "candidate_catalog_sha256": MODULE.sha256(MODULE.canonical_json(catalog)),
                           "additions": additions}).encode()

    def published(self, output):
        return MODULE.load_published_artifact_set(output / "manifest.json")

    def artifact_set(self, label):
        return {"impact-context.md": (label + "-context").encode(),
                "leliel-skip-decision.json": (label + "-decision").encode(),
                "impact-targets.json": (label + "-targets").encode()}

    def test_required_signature_and_fallback_caller(self):
        temp, root, tracked = self.make_repo()
        with temp:
            output, audit = self.run_prepare(FIXTURES / "required-signature.patch", root, tracked, temp)
            artifact = json.loads(self.published(output)["impact-targets.json"])
            self.assertEqual(artifact["pretriage"]["codex_status"], "fallback_legacy")
            target = next(item for item in artifact["targets"] if item["symbol"]["name"] == "create_user")
            self.assertIn("REQUIRED", target["selection_sources"])
            self.assertEqual(target["caller_context"]["status"], "evidence")
            self.assertLessEqual(len(target["caller_context"]["callers"]), 3)
            self.assertTrue((audit / "candidate-catalog.json").is_file())

    def test_private_and_comments_do_not_become_required(self):
        records = MODULE.parse_diff(b"""diff --git a/src/a.py b/src/a.py\n--- a/src/a.py\n+++ b/src/a.py\n@@ -1 +1 @@\n+# def public_fake(x):\n+def _private(value):\n+""")
        candidates, _ = MODULE.record_candidates(records)
        self.assertEqual(len(candidates), 1)
        self.assertFalse(candidates[0]["required"])

    def test_required_recognizers_cover_ts_go_rust_java_and_export_list(self):
        records = MODULE.parse_diff((FIXTURES / "required-languages.patch").read_bytes())
        candidates, _ = MODULE.record_candidates(records)
        required = {(item["path"], item["name"]) for item in candidates if item["required"]}
        self.assertTrue({("src/api.ts", "fetchUser"), ("src/api.ts", "token"),
                         ("src/api.ts", "export:fetchUser"), ("src/api.ts", "export:publicToken"),
                         ("src/api.go", "PublicID"), ("src/api.rs", "run"),
                         ("src/User.java", "User")} <= required)

    def test_comment_string_and_definition_callers_are_excluded(self):
        lines = ["/* create_user('x') */", "public void create_user() {}",
                 "'create_user(\"x\")'", "create_user('x')"]
        found, rejected = MODULE.scan_call_lines(lines, "create_user", "jvm")
        self.assertEqual(found, [4])
        self.assertEqual({entry["reason"] for entry in rejected}, {"comment", "definition", "string"})

    def test_inline_string_and_comment_callers_are_excluded_for_fallback_and_codegraph(self):
        lines = ['const sample = "create_user(\'x\')";', "run(); // create_user('x')", "create_user('x')"]
        found, rejected = MODULE.scan_call_lines(lines, "create_user", "javascript")
        self.assertEqual(found, [3])
        self.assertEqual({entry["line"] for entry in rejected}, {1, 2})
        temp, root, tracked = self.make_repo(caller="\n".join(lines) + "\n")
        with temp:
            candidates = [("src/caller.py", number, "codegraph") for number in (1, 2, 3)]
            self.assertEqual(MODULE.verified_caller_count(root, candidates, set(),
                                                          {"name": "create_user", "language": "javascript"}), 1)

    def test_unambiguous_public_rename_keeps_both_symbols(self):
        records = MODULE.parse_diff(b"""diff --git a/src/a.py b/src/a.py\n--- a/src/a.py\n+++ b/src/a.py\n@@ -1 +1 @@\n-def old_api(value):\n+def new_api(value):\n+""")
        candidates, _ = MODULE.record_candidates(records)
        self.assertEqual([(item["name"], item["change_kind"]) for item in candidates],
                         [("new_api", "renamed"), ("old_api", "renamed")])
        self.assertTrue(all(item["required"] for item in candidates))

    def test_invalid_added_is_all_or_nothing(self):
        catalog = {"schema_version": MODULE.CATALOG_SCHEMA, "diff_sha256": "a" * 64,
                   "candidates": [{"candidate_id": "C-0001", "path": "a.py", "name": "a", "kind": "function",
                                   "language": "python", "change_kind": "changed", "required": False}]}
        raw = json.dumps({"schema_version": MODULE.ADDED_SCHEMA,
                          "candidate_catalog_sha256": MODULE.sha256(MODULE.canonical_json(catalog)),
                          "additions": [{"candidate_id": "C-0001", "selection_reason": "ok"},
                                        {"candidate_id": "C-9999", "selection_reason": "bad"}]}).encode()
        with self.assertRaises(MODULE.InputError):
            MODULE.validate_added(raw, catalog)

    def test_codex_abnormal_responses_all_fallback_without_partial_adoption(self):
        temp, root, tracked = self.make_repo()
        with temp:
            records = MODULE.parse_diff((FIXTURES / "required-signature.patch").read_bytes())
            catalog = MODULE.candidate_catalog("a" * 64, MODULE.record_candidates(records)[0])
            valid = self.artifact_for_added(catalog, [{"candidate_id": "C-0001", "selection_reason": "ok"}])
            variants = [None, b"not json", valid.replace(MODULE.sha256(MODULE.canonical_json(catalog)).encode(), b"0" * 64),
                        self.artifact_for_added(catalog, [{"candidate_id": "C-9999", "selection_reason": "x"}]),
                        self.artifact_for_added(catalog, [{"candidate_id": "C-0001", "selection_reason": "x"}, {"candidate_id": "C-0001", "selection_reason": "y"}]),
                        valid[:-1] + b',"extra":true}']
            for number, raw in enumerate(variants):
                added = None
                if raw is not None:
                    added = Path(temp.name) / ("invalid-%d.json" % number)
                    added.write_bytes(raw)
                output, audit = self.run_prepare(FIXTURES / "required-signature.patch", root, tracked, temp, added)
                artifact = json.loads(self.published(output)["impact-targets.json"])
                self.assertEqual(artifact["pretriage"]["codex_status"], "fallback_legacy")
                self.assertTrue(any("REQUIRED" in target["selection_sources"] for target in artifact["targets"]))
                self.assertEqual(json.loads((audit / "pretriage.json").read_text())["added_count"], 0)

    def test_fake_codex_timeout_and_nonzero_fall_back(self):
        temp, root, tracked = self.make_repo()
        with temp:
            for mode, fake in (("nonzero", "fake-codex-nonzero"), ("timeout", "fake-codex-timeout")):
                output, audit = Path(temp.name) / ("out-" + mode), Path(temp.name) / ("audit-" + mode)
                environment = dict(os.environ, MAGI_CODEGRAPH="definitely-not-codegraph")
                result = subprocess.run([sys.executable, str(SCRIPT), "prepare", "--diff-file", str(FIXTURES / "required-signature.patch"),
                                         "--repo-root", str(root), "--output-dir", str(output), "--audit-dir", str(audit),
                                         "--tracked-files", str(tracked), "--codex-command", str(FIXTURES / fake),
                                         "--isolated-profile", "codex-companion-read-only/v1"], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                        env=environment, timeout=10)
                self.assertEqual(result.returncode, 0, result.stderr.decode())
                self.assertEqual(json.loads(self.published(output)["impact-targets.json"])["pretriage"]["codex_status"], "fallback_legacy")

    def test_stdin_nonreader_large_prompt_times_out_and_falls_back(self):
        temp, root, tracked = self.make_repo()
        with temp:
            diff = Path(temp.name) / "large.patch"
            diff.write_bytes(b"diff --git a/src/api.py b/src/api.py\n--- a/src/api.py\n+++ b/src/api.py\n@@ -1 +1 @@\n+" + b"x" * (70 * 1024) + b"\n")
            output, audit = Path(temp.name) / "output", Path(temp.name) / "audit"
            started = time.monotonic()
            result = subprocess.run([sys.executable, str(SCRIPT), "prepare", "--diff-file", str(diff), "--repo-root", str(root),
                                     "--output-dir", str(output), "--audit-dir", str(audit), "--tracked-files", str(tracked),
                                     "--codex-command", str(FIXTURES / "fake-codex-ignore-stdin"),
                                     "--isolated-profile", "codex-companion-read-only/v1"], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                    env=dict(os.environ, MAGI_CODEGRAPH="definitely-not-codegraph"), timeout=8)
            self.assertLess(time.monotonic() - started, 7)
            self.assertEqual(result.returncode, 0, result.stderr.decode())
            self.assertEqual(json.loads(self.published(output)["impact-targets.json"])["pretriage"]["codex_status"], "fallback_legacy")

    def test_oversized_executor_stdout_is_killed_and_falls_back(self):
        temp, root, tracked = self.make_repo()
        with temp:
            output, audit = Path(temp.name) / "output", Path(temp.name) / "audit"
            started = time.monotonic()
            result = subprocess.run([sys.executable, str(SCRIPT), "prepare", "--diff-file", str(FIXTURES / "required-signature.patch"),
                                     "--repo-root", str(root), "--output-dir", str(output), "--audit-dir", str(audit),
                                     "--tracked-files", str(tracked), "--codex-command", str(FIXTURES / "fake-codex-oversized-output"),
                                     "--isolated-profile", "codex-companion-read-only/v1"], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                    env=dict(os.environ, MAGI_CODEGRAPH="definitely-not-codegraph"), timeout=8)
            self.assertLess(time.monotonic() - started, 7)
            self.assertEqual(result.returncode, 0, result.stderr.decode())
            self.assertEqual(json.loads(self.published(output)["impact-targets.json"])["pretriage"]["codex_status"], "fallback_legacy")

    def test_new_files_only_skips(self):
        temp, root, tracked = self.make_repo(source="def public_api(value):\n    return value\n")
        with temp:
            output, _ = self.run_prepare(FIXTURES / "new-files-only.patch", root, tracked, temp)
            decision = json.loads(self.published(output)["leliel-skip-decision.json"])
            self.assertTrue(decision["skip"])
            self.assertIn("new_files_only", decision["reasons"])

    def test_decide_skip_rejects_summary_context_disagreement(self):
        temp, root, tracked = self.make_repo()
        with temp:
            output, _ = self.run_prepare(FIXTURES / "required-signature.patch", root, tracked, temp)
            manifest = json.loads((output / "manifest.json").read_text())
            context = output / manifest["artifacts"]["impact-context.md"]["path"]
            context.write_bytes(b"")
            result = subprocess.run([sys.executable, str(SCRIPT), "decide-skip", "--manifest", str(output / "manifest.json"),
                                     "--output", str(output / "decision.json")],
                                    text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            self.assertEqual(result.returncode, 2)

    def test_safe_paths_and_legacy_compatibility_shape(self):
        self.assertFalse(MODULE.safe_relative("../x"))
        self.assertFalse(MODULE.safe_relative("/x"))
        records = MODULE.parse_diff((FIXTURES / "legacy-symbols.patch").read_bytes())
        self.assertEqual([entry["name"] for entry in MODULE.legacy_candidates(records)], ["changedValue"])

    def test_legacy_unifies_with_existing_identity(self):
        records = MODULE.parse_diff((FIXTURES / "legacy-symbols.patch").read_bytes())
        candidates, _ = MODULE.record_candidates(records)
        legacy = MODULE.legacy_candidates(records, candidates)
        targets, _ = MODULE.make_targets(records, MODULE.candidate_catalog("a" * 64, candidates), [], legacy,
                                         "fallback_legacy")
        self.assertEqual(len(targets), 1)
        self.assertEqual(targets[0]["symbol"]["kind"], "variable")
        self.assertIn("LEGACY_FALLBACK", targets[0]["selection_sources"])

    def test_prompt_fence_is_dynamic_and_has_no_trailing_instruction(self):
        catalog = {"schema_version": MODULE.CATALOG_SCHEMA, "diff_sha256": "a" * 64,
                   "candidates": [{"candidate_id": "C-0001"}]}
        prompt = MODULE.build_pretriage_prompt(MODULE.canonical_json(catalog),
                                               (FIXTURES / "prompt-injection.txt").read_bytes())
        self.assertIn("``````filtered-diff-block", prompt)
        self.assertTrue(prompt.rstrip().endswith("``````"))

    def test_prepare_is_byte_deterministic(self):
        temp, root, tracked = self.make_repo()
        with temp:
            output, _ = self.run_prepare(FIXTURES / "required-signature.patch", root, tracked, temp)
            first = self.published(output)["impact-targets.json"]
            output, _ = self.run_prepare(FIXTURES / "required-signature.patch", root, tracked, temp)
            self.assertEqual(first, self.published(output)["impact-targets.json"])

    def test_codegraph_invalid_result_falls_back_after_revalidation(self):
        temp, root, tracked = self.make_repo(caller="# create_user('x')\n/* create_user('x')\n*/ create_user('x')\ncreate_user('a', 'user')\n")
        with temp, mock.patch.dict(os.environ, {"MAGI_CODEGRAPH": str(FIXTURES / "fake-codegraph"),
                                                "FAKE_CODEGRAPH_OUTPUT": "src/caller.py:1: comment\nsrc/caller.py:2: call\n"}):
            output, audit = self.run_prepare(FIXTURES / "required-signature.patch", root, tracked, temp,
                                             environment={"MAGI_CODEGRAPH": str(FIXTURES / "fake-codegraph"),
                                                          "FAKE_CODEGRAPH_OUTPUT": "src/caller.py:1: comment\nsrc/caller.py:2: block\nsrc/caller.py:3: block-end\n"})
            target = next(item for item in json.loads(self.published(output)["impact-targets.json"])["targets"]
                          if item["symbol"]["name"] == "create_user")
            self.assertEqual(target["caller_context"]["callers"][0]["source"], "fallback")
            exclusions = json.loads((audit / "pretriage.json").read_text())["callers"]
            self.assertIn("comment", {item["reason"] for item in exclusions[0]["excluded"]})

    def test_render_chunks_at_caller_boundaries_and_truncates_single_evidence(self):
        target = {"id": "T-0001", "symbol": {"path": "src/a.py", "name": "run", "kind": "function", "language": "python"},
                  "selection_sources": ["REQUIRED"], "selection_reason": [{"source": "REQUIRED", "code": "x", "detail": "reason"}],
                  "change_kinds": ["signature_changed"], "caller_context": {"status": "evidence", "reason": None, "callers": []}}
        for line in (1, 20):
            target["caller_context"]["callers"].append({"path": "src/caller.py", "line": line, "source": "fallback", "start_line": line, "end_line": line,
                                                            "snippet": "x" * 7000, "truncated": False})
        rendered = MODULE.render_context([target])
        self.assertGreaterEqual(rendered.count(b"impact-context-chunk:"), 2)
        self.assertTrue(all(caller["truncated"] for caller in target["caller_context"]["callers"]))

    def test_strict_targets_schema_rejects_missing_and_bool_counts(self):
        artifact = {"schema_version": MODULE.TARGETS_SCHEMA, "input": {"diff_sha256": "a" * 64, "changed_files": {"added": 1, "existing": True, "unparseable": 0}},
                    "targets": [], "summary": {"required_candidates": 0, "added_candidates": 0, "legacy_candidates": 0, "selected_targets": 0, "caller_evidence_targets": 0, "caller_skipped_targets": 0},
                    "pretriage": {"codex_status": "applied", "catalog_sha256": "a" * 64}, "leliel_skip": {"skip": True, "reasons": ["impact_context_empty"]}}
        with self.assertRaises(MODULE.InputError):
            MODULE.validate_targets(artifact)

    def test_delete_is_not_new_files_only(self):
        temp, root, tracked = self.make_repo()
        with temp:
            output, _ = self.run_prepare(FIXTURES / "delete-rename.patch", root, tracked, temp)
            decision = json.loads(self.published(output)["leliel-skip-decision.json"])
            self.assertNotIn("new_files_only", decision["reasons"])

    def test_root_symlink_and_overlapping_private_dirs_are_rejected(self):
        temp, root, tracked = self.make_repo()
        with temp:
            link = Path(temp.name) / "repo-link"
            link.symlink_to(root, target_is_directory=True)
            diff = FIXTURES / "required-signature.patch"
            result = subprocess.run([sys.executable, str(SCRIPT), "prepare", "--diff-file", str(diff), "--repo-root", str(link),
                                     "--output-dir", str(Path(temp.name) / "out"), "--audit-dir", str(Path(temp.name) / "out" / "audit"),
                                     "--tracked-files", str(tracked)], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            self.assertEqual(result.returncode, 2)

    def test_existing_private_directory_mode_is_not_changed(self):
        temp, root, tracked = self.make_repo()
        with temp:
            output, audit = Path(temp.name) / "output", Path(temp.name) / "audit"
            output.mkdir(mode=0o755)
            audit.mkdir(mode=0o755)
            self.run_prepare(FIXTURES / "required-signature.patch", root, tracked, temp)
            self.assertEqual(stat.S_IMODE(output.stat().st_mode), 0o755)

    def test_failed_staging_publish_keeps_generation_and_has_no_commit_marker(self):
        temp, root, tracked = self.make_repo()
        with temp, mock.patch.object(MODULE.os, "replace", side_effect=OSError("injected")):
            output = Path(temp.name) / "output"
            output.mkdir()
            with self.assertRaises(OSError):
                MODULE.publish_artifact_set(output, {"impact-context.md": b"x", "leliel-skip-decision.json": b"{}", "impact-targets.json": b"{}"})
            self.assertFalse((output / "manifest.json").exists())
            self.assertTrue(any(path.name.startswith("generation-") for path in output.iterdir()))

    def test_staging_creation_failure_releases_publish_lock(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "output"
            output.mkdir()
            with mock.patch.object(MODULE, "staging_dir", side_effect=OSError("injected staging failure")):
                with self.assertRaises(OSError):
                    MODULE.publish_artifact_set(output, self.artifact_set("failed"))
            MODULE.publish_artifact_set(output, self.artifact_set("retry"))
            self.assertEqual(self.published(output), self.artifact_set("retry"))

    def test_prepare_staging_io_failure_returns_nonzero_and_retains_stage(self):
        temp, root, tracked = self.make_repo()
        with temp:
            output, audit = Path(temp.name) / "output", Path(temp.name) / "audit"
            original_replace = MODULE.os.replace
            def fail_staging(source, destination):
                if "generation-" in str(source):
                    raise OSError("injected staging failure")
                return original_replace(source, destination)
            argv = ["prepare", "--diff-file", str(FIXTURES / "required-signature.patch"), "--repo-root", str(root),
                    "--output-dir", str(output), "--audit-dir", str(audit), "--tracked-files", str(tracked)]
            with mock.patch.object(MODULE.os, "replace", side_effect=fail_staging), \
                    mock.patch.dict(os.environ, {"MAGI_CODEGRAPH": "definitely-not-codegraph"}):
                self.assertEqual(MODULE.main(argv), 1)
            self.assertFalse((output / "manifest.json").exists())
            self.assertTrue(any(path.name.startswith("generation-") for path in output.iterdir()))

    def test_republish_mixed_generation_is_rejected_by_manifest_hashes(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "output"
            output.mkdir()
            MODULE.publish_artifact_set(output, self.artifact_set("old"))
            MODULE.publish_artifact_set(output, self.artifact_set("new"))
            manifest = json.loads((output / "manifest.json").read_text())
            target = output / manifest["artifacts"]["impact-targets.json"]["path"]
            target.write_bytes(self.artifact_set("old")["impact-targets.json"])
            with self.assertRaisesRegex(MODULE.InputError, "hash mismatch"):
                self.published(output)

    def test_publish_failure_keeps_old_manifest_generation_valid(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "output"
            output.mkdir()
            MODULE.publish_artifact_set(output, self.artifact_set("old"))
            original_replace = MODULE.os.replace
            def fail_manifest(source, destination):
                if Path(destination).name == "manifest.json":
                    raise OSError("injected manifest failure")
                return original_replace(source, destination)
            with mock.patch.object(MODULE.os, "replace", side_effect=fail_manifest):
                with self.assertRaises(OSError):
                    MODULE.publish_artifact_set(output, self.artifact_set("new"))
            self.assertEqual(self.published(output), self.artifact_set("old"))

    def test_reader_race_only_observes_hash_verified_generations(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "output"
            output.mkdir()
            MODULE.publish_artifact_set(output, self.artifact_set("old"))
            finished, failures, observed = threading.Event(), [], {self.published(output)["impact-targets.json"]}
            def writer():
                try:
                    for number in range(8):
                        MODULE.publish_artifact_set(output, self.artifact_set("new-%d" % number))
                except Exception as exc:
                    failures.append(exc)
                finally:
                    finished.set()
            thread = threading.Thread(target=writer)
            thread.start()
            while not finished.is_set():
                try:
                    observed.add(self.published(output)["impact-targets.json"])
                except Exception as exc:
                    failures.append(exc)
            thread.join(timeout=2)
            self.assertFalse(failures)
            self.assertTrue(observed)
            self.assertEqual(self.published(output)["impact-targets.json"], b"new-7-targets")

    def test_same_output_dir_parallel_runs_leave_a_complete_committed_set(self):
        temp, root, tracked = self.make_repo()
        with temp:
            diff, output, audit = FIXTURES / "required-signature.patch", Path(temp.name) / "output", Path(temp.name) / "audit"
            command = [sys.executable, str(SCRIPT), "prepare", "--diff-file", str(diff), "--repo-root", str(root),
                       "--output-dir", str(output), "--audit-dir", str(audit), "--tracked-files", str(tracked)]
            env = dict(os.environ, MAGI_CODEGRAPH="definitely-not-codegraph")
            first = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
            second = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
            first.communicate(timeout=10)
            second.communicate(timeout=10)
            self.assertIn(first.returncode, (0, 2))
            self.assertIn(second.returncode, (0, 2))
            self.assertTrue((output / "manifest.json").is_file())
            published = self.published(output)
            MODULE.validate_targets(json.loads(published["impact-targets.json"]))

    def test_help_and_unknown_argument(self):
        good = subprocess.run([sys.executable, str(SCRIPT), "render", "--help"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        bad = subprocess.run([sys.executable, str(SCRIPT), "prepare", "--unknown"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertEqual(good.returncode, 0)
        self.assertEqual(bad.returncode, 2)


if __name__ == "__main__":
    unittest.main()
