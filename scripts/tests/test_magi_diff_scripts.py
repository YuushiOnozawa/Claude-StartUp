import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
FILTER = ROOT / "scripts" / "magi-diff-filter.sh"
SPLIT_HUNK = ROOT / "scripts" / "magi-split-hunk.sh"


def diff_for(path, added_lines):
    return (
        f"diff --git a/{path} b/{path}\n"
        f"index 1111111..2222222 100644\n"
        f"--- a/{path}\n"
        f"+++ b/{path}\n"
        f"@@ -1 +1,{len(added_lines)} @@\n"
        + "".join(f"+{line}\n" for line in added_lines)
    )


class MagiDiffFilterTests(unittest.TestCase):
    def run_filter(self, diff, excluded_list=None):
        environment = dict(os.environ)
        if excluded_list is None:
            environment.pop("MAGI_FILTER_EXCLUDED_LIST", None)
        else:
            environment["MAGI_FILTER_EXCLUDED_LIST"] = str(excluded_list)
        return subprocess.run(
            ["bash", str(FILTER)], input=diff, text=True, capture_output=True, env=environment
        )

    def test_filters_fixture_data_files_but_keeps_non_data_and_non_fixture_files(self):
        diff = "".join((
            diff_for("scripts/tests/fixtures/foo.json", ["fixture"]),
            diff_for("scripts/tests/fixtures/fake-codex", ["#!/bin/sh"]),
            diff_for("scripts/config.json", ["config"]),
            diff_for("src/tests/fixtures/nested/data.patch", ["patch"]),
            diff_for("src/test/fixture/data.yml", ["yaml"]),
            diff_for("src/test/fixtures/data.xml", ["xml"]),
        ))
        result = self.run_filter(diff)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("b/scripts/tests/fixtures/foo.json", result.stdout)
        self.assertNotIn("+fixture\n", result.stdout)
        self.assertIn("b/scripts/tests/fixtures/fake-codex", result.stdout)
        self.assertIn("+#!/bin/sh\n", result.stdout)
        self.assertIn("b/scripts/config.json", result.stdout)
        self.assertIn("+config\n", result.stdout)
        for path, line in (("src/tests/fixtures/nested/data.patch", "+patch\n"),
                           ("src/test/fixture/data.yml", "+yaml\n"),
                           ("src/test/fixtures/data.xml", "+xml\n")):
            self.assertNotIn(f"b/{path}", result.stdout)
            self.assertNotIn(line, result.stdout)

    def test_keeps_legacy_roleplay_exclusions(self):
        diff = "".join((
            diff_for("skills/foo/SKILL.md", ["skill"]),
            diff_for("CLAUDE.md", ["claude"]),
            diff_for("skills/agents/reviewer.md", ["agent"]),
            diff_for("skills/references/guide.md", ["reference"]),
            diff_for("src/keep.py", ["kept"]),
        ))
        result = self.run_filter(diff)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("b/src/keep.py", result.stdout)
        self.assertIn("+kept\n", result.stdout)
        for line in ("+skill\n", "+claude\n", "+agent\n", "+reference\n"):
            self.assertNotIn(line, result.stdout)

    def test_writes_excluded_fixture_paths_once_and_unset_filter_creates_no_file(self):
        diff = diff_for("scripts/tests/fixtures/foo.json", ["fixture"]) + diff_for(
            "scripts/tests/fixtures/bar.csv", ["csv"]
        )
        with tempfile.TemporaryDirectory() as temporary:
            excluded = Path(temporary) / "excluded.txt"
            configured = self.run_filter(diff, excluded)
            self.assertEqual(configured.returncode, 0, configured.stderr)
            self.assertEqual(excluded.read_text(),
                             "scripts/tests/fixtures/foo.json\nscripts/tests/fixtures/bar.csv\n")

            before = set(Path(temporary).iterdir())
            unset = self.run_filter(diff)
            after = set(Path(temporary).iterdir())
            self.assertEqual(unset.returncode, 0, unset.stderr)
            self.assertEqual(unset.stdout, configured.stdout)
            self.assertEqual(before, after)


class MagiSplitHunkTests(unittest.TestCase):
    def run_split(self, diff, max_lines=None):
        command = ["bash", str(SPLIT_HUNK)]
        if max_lines is not None:
            command.append(str(max_lines))
        return subprocess.run(command, input=diff, text=True, capture_output=True)

    def test_packs_three_small_files_into_one_composite_chunk(self):
        paths = ["src/one.py", "src/two.py", "src/three.py"]
        diff = "".join(diff_for(path, [f"line-{i}" for i in range(5)]) for path in paths)
        result = self.run_split(diff, 400)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.count("=== CHUNK:"), 1)
        self.assertIn("=== CHUNK: src/one.py +2 files (1) ===", result.stdout)
        for path in paths:
            self.assertEqual(result.stdout.count(f"diff --git a/{path} b/{path}"), 1)

    def test_starts_new_chunk_when_packing_would_exceed_budget(self):
        diff = diff_for("src/one.py", [f"line-{i}" for i in range(8)]) + diff_for(
            "src/two.py", [f"line-{i}" for i in range(8)]
        )
        result = self.run_split(diff, 10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.count("=== CHUNK:"), 2)
        self.assertIn("=== CHUNK: src/one.py (1) ===", result.stdout)
        self.assertIn("=== CHUNK: src/two.py (1) ===", result.stdout)

    def test_splits_large_single_file_by_hunks_and_keeps_its_labels(self):
        path = "src/large.py"
        diff = (
            f"diff --git a/{path} b/{path}\nindex 1111111..2222222 100644\n"
            f"--- a/{path}\n+++ b/{path}\n"
            "@@ -1,2 +1,4 @@\n+one\n+two\n"
            "@@ -10,2 +12,4 @@\n+three\n+four\n"
        )
        result = self.run_split(diff, 3)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.count("=== CHUNK:"), 2)
        self.assertIn(f"=== CHUNK: {path} (1) ===", result.stdout)
        self.assertIn(f"=== CHUNK: {path} (2) ===", result.stdout)
        self.assertEqual(result.stdout.count(f"diff --git a/{path} b/{path}"), 2)

    def test_single_file_input_keeps_legacy_chunk_label(self):
        path = "src/only.py"
        result = self.run_split(diff_for(path, ["one", "two"]), 200)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f"=== CHUNK: {path} (1) ===", result.stdout)
        self.assertNotIn("+1 files", result.stdout)


if __name__ == "__main__":
    unittest.main()
