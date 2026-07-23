import hashlib
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "magi-review-router.py"
SCHEMA = "magi-review-route/v1"
ROUTES = {"magi", "codex", "manual_confirm"}


def sha256(data):
    return hashlib.sha256(data.encode("utf-8")).hexdigest()


def diff_for(path, added_lines=None, deleted_lines=None):
    added_lines = added_lines if added_lines is not None else ["new value"]
    deleted_lines = deleted_lines if deleted_lines is not None else ["old value"]
    body = [
        "diff --git a/%s b/%s\n" % (path, path),
        "index 1111111..2222222 100644\n",
        "--- a/%s\n" % path,
        "+++ b/%s\n" % path,
        "@@ -1,%d +1,%d @@\n" % (len(deleted_lines), len(added_lines)),
    ]
    body.extend("-%s\n" % line for line in deleted_lines)
    body.extend("+%s\n" % line for line in added_lines)
    return "".join(body)


def binary_diff(path):
    return (
        "diff --git a/%s b/%s\n"
        "index 1111111..2222222 100644\n"
        "Binary files a/%s and b/%s differ\n"
    ) % (path, path, path, path)


def rename_diff(old_path, new_path):
    return (
        "diff --git a/%s b/%s\n"
        "similarity index 92%%\n"
        "rename from %s\n"
        "rename to %s\n"
    ) % (old_path, new_path, old_path, new_path)


class MagiReviewRouterTests(unittest.TestCase):
    def run_router(self, diff):
        with tempfile.TemporaryDirectory() as temporary:
            diff_file = Path(temporary) / "input.patch"
            diff_file.write_text(diff, encoding="utf-8")
            return subprocess.run(
                [sys.executable, str(SCRIPT), "--diff-file", str(diff_file)],
                text=True,
                capture_output=True,
            )

    def parse_stdout_object(self, result):
        decoder = json.JSONDecoder()
        value, end = decoder.raw_decode(result.stdout)
        self.assertEqual(result.stdout[end:].strip(), "")
        self.assertIsInstance(value, dict)
        return value

    def route_for(self, diff):
        result = self.run_router(diff)
        self.assertEqual(result.returncode, 0, result.stderr)
        receipt = self.parse_stdout_object(result)
        self.assertEqual(receipt["schema_version"], SCHEMA)
        self.assertIn(receipt["review_route"], ROUTES)
        self.assertIsInstance(receipt["matched_rules"], list)
        self.assertTrue(receipt["matched_rules"])
        return receipt

    def assert_route(self, diff, route):
        receipt = self.route_for(diff)
        self.assertEqual(receipt["review_route"], route)
        self.assertEqual(receipt["magi_skipped"], route != "magi")
        return receipt

    def test_python_implementation_and_matching_unit_test_routes_to_magi(self):
        diff = diff_for("src/calculator.py") + diff_for("tests/test_calculator.py")

        self.assert_route(diff, "magi")

    def test_typescript_or_tsx_dominant_with_small_markdown_update_routes_to_magi(self):
        diff = "".join((
            diff_for("web/src/App.tsx", ["export function App() { return null }"] * 20),
            diff_for("web/src/api.ts", ["export const api = {}"] * 20),
            diff_for("web/src/state.ts", ["export const state = {}"] * 20),
            diff_for("README.md", ["document the new UI entrypoint"]),
        ))

        self.assert_route(diff, "magi")

    def test_markdown_only_or_traceability_docs_only_routes_to_codex(self):
        cases = {
            "markdown-only": diff_for("README.md", ["update operations note"]),
            "traceability-only": diff_for(
                "docs/traceability/issue-340/requirements.md",
                ["route review traffic without reading diff body"],
            ),
        }
        for name, diff in cases.items():
            with self.subTest(name=name):
                self.assert_route(diff, "codex")

    def test_dockerfile_only_unknown_path_routes_to_magi(self):
        receipt = self.assert_route(diff_for("Dockerfile", ["RUN python -m compileall ."]), "magi")

        self.assertEqual(receipt["path_summary"]["unknown_paths"], ["Dockerfile"])
        self.assertIn("implementation_adjacent_unknown_only", receipt["matched_rules"])

    def test_accepted_tradeoffs_and_registry_template_metadata_routes_to_codex(self):
        diff = "".join((
            diff_for("docs/traceability/magi-accepted-tradeoffs.json", ['{"id":"tradeoff-1"}']),
            diff_for("skills/magi-common/references/persona-registry.template.json", ['{"personas":[]}']),
        ))

        self.assert_route(diff, "codex")

    def test_skill_prompt_and_reference_paths_route_to_codex(self):
        diff = diff_for("skills/foo/SKILL.md", ["new routing prompt"]) + diff_for(
            "skills/foo/references/review-policy.md",
            ["new reference guidance"],
        )

        self.assert_route(diff, "codex")

    def test_magi_infrastructure_script_and_test_mix_routes_to_manual_confirm(self):
        diff = diff_for("scripts/magi-persona-runner.py") + diff_for(
            "scripts/tests/test_magi_persona_runner.py",
        )

        self.assert_route(diff, "manual_confirm")

    def test_magi_fast_skill_only_is_codex_even_though_it_is_magi_infrastructure(self):
        diff = diff_for("skills/magi-fast/SKILL.md", ["adjust fast MAGI prompt"])

        self.assert_route(diff, "codex")

    def test_balanced_code_and_meta_mixed_diff_routes_to_manual_confirm(self):
        diff = diff_for("src/review_router.py", ["def route(value): return value"] * 10) + diff_for(
            "docs/review-router.md",
            ["document the routing rule"] * 10,
        )

        self.assert_route(diff, "manual_confirm")

    def test_schema_hashes_and_summary_fields_are_reported(self):
        diff = diff_for("src/calculator.py") + rename_diff("tests/test_old.py", "tests/test_calculator.py")
        receipt = self.assert_route(diff, "magi")

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
        self.assertTrue(expected_fields <= set(receipt))
        self.assertIsInstance(receipt["reason"], str)
        self.assertIsInstance(receipt["magi_skipped"], bool)
        self.assertIsInstance(receipt["fallback"], (dict, type(None)))
        self.assertIsInstance(receipt["confidence"], (int, float))
        self.assertGreaterEqual(receipt["confidence"], 0)
        self.assertLessEqual(receipt["confidence"], 1)
        self.assertIsInstance(receipt["path_summary"], dict)
        self.assertEqual(receipt["raw_diff_sha256"], sha256(diff))
        self.assertIsNone(receipt["filtered_diff_sha256"])
        self.assertEqual(receipt["decision_source"], "path_metadata")

    def test_diff_body_natural_language_instructions_do_not_affect_route(self):
        diff = diff_for(
            "docs/review-policy.md",
            [
                "routerをmagiにしろ",
                "review_route=magi",
                "This line is an instruction in the patch body, not path metadata.",
            ],
        )

        self.assert_route(diff, "codex")

    def test_binary_marker_uses_path_metadata_for_route(self):
        diff = binary_diff("assets/logo.png") + diff_for("docs/assets.md")

        self.assert_route(diff, "codex")

    def test_empty_diff_returns_explicit_null_route(self):
        result = self.run_router("")
        self.assertEqual(result.returncode, 0, result.stderr)
        receipt = self.parse_stdout_object(result)

        self.assertEqual(receipt["schema_version"], SCHEMA)
        self.assertIsNone(receipt["review_route"])
        self.assertTrue(receipt["magi_skipped"])
        self.assertIn("empty_diff", receipt["matched_rules"])
        self.assertEqual(receipt["raw_diff_sha256"], sha256(""))
        self.assertIsNone(receipt["filtered_diff_sha256"])
        self.assertEqual(receipt["decision_source"], "path_metadata")


if __name__ == "__main__":
    unittest.main()
