import json
import os
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "magi-hard-poster.py"
HEAD_SHA = "a" * 40


def make_plan(**changes):
    anchor = {"path": "src/example.py", "line": 12, "side": None,
              "start_line": None, "start_side": None, "head_sha": None}
    pr_anchor = {"path": None, "line": None, "side": None,
                 "start_line": None, "start_side": None, "head_sha": None}
    plan = {
        "schema_version": "review-plan/v1",
        "canonical_sha256": "b" * 64,
        "run_policy": {
            "schema_version": "run-policy/v1", "workflow": "hard", "gate_basis": "raw",
            "gate_severity": "HIGH", "false_positive_policy": "annotate",
            "needs_human_policy": "label", "renderer": "github", "locale": "ja",
            "anchor_policy": "pr", "head_sha": HEAD_SHA, "audit_enabled": True,
            "dedupe_enabled": True, "audit_severities": ["HIGH", "MEDIUM"],
            "completion_policy": {"require_marker": True, "zero_findings_requires_no_findings": True},
            "diff_source": {"kind": "head"},
        },
        "audit": {"status": "applied", "sha256": "c" * 64, "diagnostics": []},
        "items": [
            {"id": "MEL-001", "representative_id": "MEL-001", "source_ids": ["MEL-001"],
             "personas": ["melchior"], "severity": "HIGH", "source_severities": [{"id": "MEL-001", "severity": "HIGH"}],
             "title": "英語の finding", "body": "Please check this value.", "anchor": anchor,
             "verdicts": [], "display_state": "postable", "needs_human": False},
            {"id": "BAL-001", "representative_id": "BAL-001", "source_ids": ["BAL-001"],
             "personas": ["balthasar"], "severity": "MEDIUM", "source_severities": [{"id": "BAL-001", "severity": "MEDIUM"}],
             "title": "日本語の finding", "body": "値を確認してください。", "anchor": {**anchor, "line": 20},
             "verdicts": [{"id": "BAL-001", "verdict": "needs_human", "reason_ja": "確認が必要"}],
             "display_state": "needs_human", "needs_human": True},
            {"id": "CAS-002", "representative_id": "CAS-002", "source_ids": ["CAS-002"],
             "personas": ["casper"], "severity": "LOW", "source_severities": [{"id": "CAS-002", "severity": "LOW"}],
             "title": "PR 全体の finding", "body": "PR 全体を確認してください。", "anchor": pr_anchor,
             "verdicts": [], "display_state": "postable", "needs_human": False},
        ],
        "excluded_findings": [{"id": "CAS-001", "persona": "casper", "title": "除外 finding",
                               "reason_ja": "誤検知", "raw_sha256": "d" * 64,
                               "annotation_verdict": "false_positive"}],
        "summary": {"raw_counts": {"HIGH": 1, "MEDIUM": 1},
                    "grouped_counts": {"HIGH:postable": 1, "MEDIUM:needs_human": 1},
                    "audit_counts": {"supplied": 2, "applied": 2, "invalid": 0},
                    "review_incomplete": False},
    }
    for key, value in changes.items():
        plan[key] = value
    return plan


def make_post_plan():
    return {"schema_version": "post-plan/v1", "head_sha": HEAD_SHA,
            "summary_body": "summary <!-- magi-summary: @%s -->" % HEAD_SHA,
            "entries": [
                {"id": "MEL-001", "marker": "<!-- magi-finding: MEL-001@%s -->" % HEAD_SHA,
                 "severity": "HIGH", "personas": ["melchior"], "source_ids": ["MEL-001"],
                 "title_ja": "指摘", "body_ja": "本文", "anchor": {"path": "src/a.py", "line": 12,
                 "side": "RIGHT", "commit_id": HEAD_SHA}, "scope": "inline", "needs_human": False,
                 "translation_status": "native"},
                {"id": "BAL-001", "marker": "<!-- magi-finding: BAL-001@%s -->" % HEAD_SHA,
                 "severity": "MEDIUM", "personas": ["balthasar"], "source_ids": ["BAL-001"],
                 "title_ja": "別の指摘", "body_ja": "別本文", "anchor": None, "scope": "pr",
                 "needs_human": True, "translation_status": "native"},
            ]}


class MagiHardPosterTests(unittest.TestCase):
    def write_json(self, path, value):
        path.write_text(json.dumps(value, ensure_ascii=False), encoding="utf-8")

    def build(self, root, plan=None, translations=None, profile_verification=None):
        review = root / "review.json"
        output = root / "post.json"
        self.write_json(review, plan or make_plan())
        command = [sys.executable, str(SCRIPT), "build", "--review-plan", str(review), "--output", str(output)]
        if translations is not None:
            translated = root / "translations.json"
            self.write_json(translated, translations)
            command += ["--translations", str(translated)]
        if profile_verification is not None:
            profile = root / "profile-verification.json"
            self.write_json(profile, profile_verification)
            command += ["--profile-verification", str(profile)]
        result = subprocess.run(command, text=True, capture_output=True)
        return result, output

    def write_fake_gh(self, root, mode="success"):
        fake = root / "fake-gh.py"
        fake.write_text('''#!/usr/bin/env python3
import json, os, sys
record = os.environ["FAKE_GH_RECORD"]
with open(record, "a", encoding="utf-8") as f:
    f.write(json.dumps(sys.argv[1:], ensure_ascii=False) + "\\n")
args = sys.argv[1:]
if "--slurp" in args:
    print("unknown flag: --slurp", file=sys.stderr); raise SystemExit(1)
if "--jq" in args and "repos/OWNER/REPO/pulls/7" in args:
    print(os.environ.get("FAKE_GH_HEAD", "''' + HEAD_SHA + '''")); raise SystemExit(0)
if "--method" in args and "GET" in args and os.environ.get("FAKE_GH_MODE") == "listing-failure":
    raise SystemExit(1)
if "--method" in args and "GET" in args and "--jq" in args and os.environ.get("FAKE_GH_MODE") == "existing" and "repos/OWNER/REPO/issues/7/comments" in args:
    for comment in [{"id": 88, "body": "old <!-- magi-finding: MEL-001@''' + HEAD_SHA + ''' -->"},
                    {"id": 99, "body": "old <!-- magi-summary: @''' + HEAD_SHA + ''' -->"}]:
        print(json.dumps(comment))
elif "--method" in args and "GET" in args and "--jq" in args and ("repos/OWNER/REPO/issues/7/comments" in args or "repos/OWNER/REPO/pulls/7/comments" in args):
    pass
if "--method" in args and "POST" in args and os.environ.get("FAKE_GH_MODE") == "fallback" and "repos/OWNER/REPO/pulls/7/comments" in args:
    print("unprocessable", file=sys.stderr); raise SystemExit(1)
if "--method" in args and "POST" in args:
    comment_id = 101 if "repos/OWNER/REPO/issues/7/comments" in args and "summary" in " ".join(args) else 102
    print(json.dumps({"id": comment_id, "html_url": "https://example.test/comment/%d" % comment_id}))
if "--method" in args and "PATCH" in args:
    print(json.dumps({"id": 99, "html_url": "https://example.test/comment/99"}))
''', encoding="utf-8")
        fake.chmod(fake.stat().st_mode | stat.S_IXUSR)
        return fake

    def post(self, root, mode="success", dry_run=False, head=HEAD_SHA):
        post_plan = root / "post.json"
        results = root / "results.jsonl"
        self.write_json(post_plan, make_post_plan())
        record = root / "gh.log"
        fake = self.write_fake_gh(root, mode)
        env = {**os.environ, "FAKE_GH_RECORD": str(record), "FAKE_GH_MODE": mode, "FAKE_GH_HEAD": head}
        command = [sys.executable, str(SCRIPT), "post", "--post-plan", str(post_plan), "--pr", "7",
                   "--repo", "OWNER/REPO", "--results", str(results), "--gh", str(fake)]
        if dry_run:
            command.append("--dry-run")
        result = subprocess.run(command, text=True, capture_output=True, env=env)
        calls = [json.loads(line) for line in record.read_text(encoding="utf-8").splitlines()] if record.exists() else []
        lines = results.read_text(encoding="utf-8").splitlines() if results.exists() else []
        return result, calls, [json.loads(line) for line in lines]

    def test_build_is_deterministic_and_keeps_marker_at_body_end(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            first, output = self.build(root)
            self.assertEqual(first.returncode, 0, first.stderr)
            first_bytes = output.read_bytes()
            second, _ = self.build(root)
            self.assertEqual(second.returncode, 0, second.stderr)
            self.assertEqual(first_bytes, output.read_bytes())
            data = json.loads(first_bytes)
            entry = data["entries"][0]
            self.assertEqual(entry["marker"], "<!-- magi-finding: MEL-001@%s -->" % HEAD_SHA)
            self.assertTrue(entry["body_ja"].endswith(entry["marker"]))

    def test_build_labels_human_and_translation_states(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            result, output = self.build(root, translations={"MEL-001": {"title_ja": "翻訳題", "body_ja": "翻訳本文"}})
            self.assertEqual(result.returncode, 0, result.stderr)
            entries = {item["id"]: item for item in json.loads(output.read_text())["entries"]}
            self.assertEqual(entries["MEL-001"]["translation_status"], "translated")
            self.assertIn("翻訳本文", entries["MEL-001"]["body_ja"])
            self.assertIn("⚠ 要人判断", entries["BAL-001"]["body_ja"])
            self.assertEqual(entries["BAL-001"]["translation_status"], "native")

    def test_build_turns_null_anchor_into_pr_scope_entry(self):
        with tempfile.TemporaryDirectory() as name:
            result, output = self.build(Path(name))
            self.assertEqual(result.returncode, 0, result.stderr)
            entries = {item["id"]: item for item in json.loads(output.read_text())["entries"]}
            self.assertEqual(entries["CAS-002"]["scope"], "pr")
            self.assertIsNone(entries["CAS-002"]["anchor"])

    def test_aggregate_merge_output_round_trips_through_build(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            null_anchor = {"path": None, "line": None, "side": None,
                           "start_line": None, "start_side": None, "head_sha": None}
            canonical = {
                "schema_version": "canonical-findings/v1",
                "manifest": {"schema_version": "persona-manifest/v1", "personas": [
                    {"ordinal": 1, "key": "casper", "name": "CASPER", "id_prefix": "CAS"}]},
                "personas": [{"key": "casper", "parse_status": "failed",
                               "execution_status": "failed", "diagnostics": []}],
                "findings": [{"id": "CAS-001", "persona": "casper", "severity": "UNKNOWN", "scope": "pr",
                              "title": "構造化されていない出力", "body": "出力を確認してください。",
                              "raw": {"sha256": "d" * 64, "bytes": 0, "excerpt_escaped": "", "truncated": False},
                              "source": {"result_path": "results/casper.md", "result_sha256": "d" * 64,
                                         "chunk_ordinals": []}, "anchor": null_anchor,
                              "fallback": {"kind": "unstructured_output", "reason_ja": "出力を確認してください。"}}],
                "summary": {"raw_counts": {"UNKNOWN": 1}, "parse_status_counts": {"failed": 1},
                            "review_incomplete": True},
            }
            policy = {"schema_version": "magi-run-policy/v1", "workflow": "hard", "gate_basis": "raw",
                      "gate_severity": "HIGH", "false_positive_policy": "annotate",
                      "needs_human_policy": "label", "renderer": "github", "locale": "ja",
                      "anchor_policy": "pr", "head_sha": HEAD_SHA, "audit_enabled": True,
                      "dedupe_enabled": True, "audit_severities": ["HIGH", "MEDIUM"],
                      "completion_policy": {"require_marker": True, "zero_findings_requires_no_findings": True},
                      "diff_source": {"kind": "head"}}
            canonical_path, policy_path = root / "canonical.json", root / "policy.json"
            merged_path = root / "review.json"
            self.write_json(canonical_path, canonical)
            self.write_json(policy_path, policy)
            merged = subprocess.run([sys.executable, str(ROOT / "scripts" / "magi-aggregate.py"), "merge",
                                     "--findings", str(canonical_path), "--run-policy", str(policy_path),
                                     "--output", str(merged_path)], text=True, capture_output=True)
            self.assertEqual(merged.returncode, 0, merged.stderr)
            built, output = self.build(root, json.loads(merged_path.read_text(encoding="utf-8")))
            self.assertEqual(built.returncode, 0, built.stderr)
            entry = json.loads(output.read_text(encoding="utf-8"))["entries"][0]
            self.assertEqual(entry["scope"], "pr")
            self.assertIsNone(entry["anchor"])

    def test_build_pending_is_labeled_and_native_text_is_detected(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            plan = make_plan()
            plan["items"][1]["title"] = "English title"
            plan["items"][1]["body"] = "English body"
            plan["items"][1]["needs_human"] = False
            plan["items"][1]["display_state"] = "postable"
            result, output = self.build(root, plan)
            self.assertEqual(result.returncode, 0, result.stderr)
            entries = {item["id"]: item for item in json.loads(output.read_text())["entries"]}
            self.assertEqual(entries["MEL-001"]["translation_status"], "pending")
            self.assertEqual(entries["BAL-001"]["translation_status"], "pending")
            self.assertIn("⚠ 要人判断（未翻訳）", entries["MEL-001"]["body_ja"])
            self.assertIn("> ⚠ 翻訳に失敗したため原文を掲載しています。内容を人が確認してください。",
                          entries["MEL-001"]["body_ja"])

    def test_build_rejects_bad_translations_and_false_positive(self):
        cases = [
            {"MEL-001": {"title_ja": "", "body_ja": "翻訳"}},
            {"MEL-001": {"title_ja": "<!-- x", "body_ja": "翻訳"}},
            {"BAL-001": {"title_ja": "翻訳", "body_ja": "翻訳"}},
        ]
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            for translations in cases:
                result, _ = self.build(root, translations=translations)
                self.assertEqual(result.returncode, 2, result.stderr)
            plan = make_plan(items=[{**make_plan()["items"][0], "display_state": "annotated_false_positive"}])
            result, _ = self.build(root, plan)
            self.assertEqual(result.returncode, 2, result.stderr)

    def test_build_rejects_fast_workflow_and_summary_contains_exclusion_log(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            plan = make_plan()
            plan["run_policy"]["workflow"] = "fast"
            result, _ = self.build(root, plan)
            self.assertEqual(result.returncode, 2, result.stderr)
            plan["run_policy"]["workflow"] = "hard"
            result, output = self.build(root, plan)
            self.assertEqual(result.returncode, 0, result.stderr)
            summary = json.loads(output.read_text())["summary_body"]
            self.assertIn("<details>", summary)
            self.assertIn("- CAS-001 [casper] 除外 finding: 誤検知 (raw:%s)" % ("d" * 64), summary)

    def test_build_appends_profile_verification_when_supplied(self):
        with tempfile.TemporaryDirectory() as name:
            profile = {"schema_version": "profile-verification/v1",
                       "status": "invalid", "annotation_eligible": True,
                       "profile_verified": False,
                       "network_isolation": "not_supported_by_codex_companion_1.0.5",
                       "failed_checks": ["post_run_tree_changed"]}
            result, output = self.build(Path(name), profile_verification=profile)
            self.assertEqual(result.returncode, 0, result.stderr)
            summary = json.loads(output.read_text(encoding="utf-8"))["summary_body"]
            self.assertIn("annotation_profile: invalid (eligible=True, verified=False)", summary)
            self.assertIn("network_isolation: not_supported_by_codex_companion_1.0.5", summary)
            self.assertIn("failed_checks: post_run_tree_changed", summary)

    def test_post_head_drift_stops_all_api_posts(self):
        with tempfile.TemporaryDirectory() as name:
            result, calls, lines = self.post(Path(name), head="e" * 40)
            self.assertEqual(result.returncode, 3, result.stderr)
            self.assertEqual(lines, [])
            self.assertEqual([call for call in calls if "--method" in call], [])

    def test_post_skips_existing_marker_idempotently(self):
        with tempfile.TemporaryDirectory() as name:
            result, calls, lines = self.post(Path(name), mode="existing")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn({"id": "MEL-001", "action": "skipped_existing"},
                          [{"id": item["id"], "action": item["action"]} for item in lines])
            self.assertIn({"id": "summary", "action": "skipped_existing"},
                          [{"id": item["id"], "action": item["action"]} for item in lines])
            self.assertTrue(any("repos/OWNER/REPO/issues/comments/99" in call for call in calls) is False)
            self.assertFalse(any("MEL-001" in call and "--method" in call for call in calls))

    def test_post_listing_failure_stops_before_any_post(self):
        with tempfile.TemporaryDirectory() as name:
            result, calls, lines = self.post(Path(name), mode="listing-failure")
            self.assertEqual(result.returncode, 1)
            self.assertIn("comment listing failed", result.stderr)
            self.assertEqual(lines, [])
            self.assertFalse(any("POST" in call for call in calls))

    def test_post_falls_back_on_422_and_patches_failure_summary(self):
        with tempfile.TemporaryDirectory() as name:
            result, calls, lines = self.post(Path(name), mode="fallback")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual([item["id"] for item in lines], ["summary", "MEL-001", "BAL-001", "summary-update"])
            self.assertEqual(lines[1]["action"], "fallback_issue_comment")
            patch_calls = [call for call in calls if "--method" in call and "PATCH" in call]
            self.assertEqual(len(patch_calls), 1)
            self.assertEqual(patch_calls[0][1], "repos/OWNER/REPO/issues/comments/101")
            self.assertIn("body=summary <!-- magi-summary: @%s -->\n\n> ⚠ anchor 失敗/退避: 1 件、投稿失敗: 0 件" % HEAD_SHA,
                          patch_calls[0])
            self.assertTrue(all("--repo" not in call for call in calls))
            get_calls = [call for call in calls if "GET" in call]
            self.assertEqual(len(get_calls), 2)
            self.assertTrue(all("-F" in call and "per_page=100" in call for call in get_calls))

    def test_post_results_are_jsonl_in_posting_order(self):
        with tempfile.TemporaryDirectory() as name:
            result, _, lines = self.post(Path(name))
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual([item["id"] for item in lines], ["summary", "MEL-001", "BAL-001"])
            self.assertTrue(all(item["action"] == "posted" for item in lines))
            self.assertTrue(all("url" in item and "at" in item for item in lines))

    def test_post_dry_run_does_not_invoke_gh_and_prints_plan(self):
        with tempfile.TemporaryDirectory() as name:
            result, calls, lines = self.post(Path(name), dry_run=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(calls, [])
            self.assertEqual(lines, [])
            self.assertIn("MEL-001", result.stdout)
            self.assertIn("summary", result.stdout)


if __name__ == "__main__":
    unittest.main()
