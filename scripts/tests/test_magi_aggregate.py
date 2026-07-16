import hashlib
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "magi-aggregate.py"
FIXTURES = Path(__file__).resolve().parent / "fixtures"
SPEC = importlib.util.spec_from_file_location("magi_aggregate", SCRIPT)
MAGI_AGGREGATE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MAGI_AGGREGATE)


def status_for(persona, result, chunks=1, execution_status="complete"):
    data = result.read_bytes()
    records = []
    current = None
    for raw_line in data.splitlines(keepends=True):
        line = raw_line.rstrip(b"\r\n").decode("utf-8")
        match = re.fullmatch(r"=== CHUNK: (.+) ===", line)
        if match:
            if current is not None:
                body = b"".join(current.pop("lines"))
                current["body"] = body[:-1] if body.endswith(b"\n") else body
                records.append(current)
            current = {"label": match.group(1), "lines": []}
        elif current is not None:
            current["lines"].append(raw_line)
    if current is not None:
        body = b"".join(current.pop("lines"))
        current["body"] = body[:-1] if body.endswith(b"\n") else body
        records.append(current)
    empty_sha256 = hashlib.sha256(b"").hexdigest()
    status_chunks = []
    for number in range(1, chunks + 1):
        record = records[number - 1] if number <= len(records) else None
        base = {"id": f"{number:04d}", "ordinal": number,
                "source_label": record["label"] if record else f"source ({number})",
                "input_bytes": 0, "input_sha256": empty_sha256}
        if record:
            body = record["body"]
            base.update({"exit_code": 0, "marker": "complete", "output_bytes": len(body),
                         "output_sha256": hashlib.sha256(body).hexdigest(),
                         "stderr": {"path": f"status/{persona}/{number:04d}.stderr", "bytes": 0,
                                    "sha256": empty_sha256}})
        else:
            base.update({"exit_code": None, "marker": "not_run", "output_bytes": 0,
                         "output_sha256": None, "stderr": None})
        status_chunks.append(base)
    return {
        "schema_version": "magi-persona-status/v1", "run_id": "run", "diff_hash": "a" * 64,
        "persona": persona, "persona_name": persona.upper(), "model": "test", "backend": "ollama",
        "execution_status": execution_status, "started_at": "2026-01-01T00:00:00Z",
        "finished_at": "2026-01-01T00:00:01Z", "duration_ms": 1,
        "input": {"path": "diff/input.filtered.patch", "bytes": 0, "sha256": empty_sha256},
        "result": {"path": f"results/{persona}.md", "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()},
        "expected_chunks": chunks, "completed_chunks": len(records[:chunks]), "chunks": status_chunks,
    }


class MagiAggregateCliTests(unittest.TestCase):
    def make_run(self, mel_text=None, bal_text=None):
        temporary = tempfile.TemporaryDirectory()
        root = Path(temporary.name)
        for name in ("results", "status", "plan"):
            (root / name).mkdir()
        mel = root / "results/melchior.md"
        mel.write_text(mel_text or """=== CHUNK: src/a.py (1) ===
## Review
### [HIGH] src/a.py:12 — null を検査する
説明。

### [HIGH] src/a.py:12 — null を検査する
説明。

### [LOW] src/a.py:20 — ログを追加する
詳細。
## Assessment
確認済み。
<!-- MAGI_COMPLETE persona=melchior chunk=0001 -->
""", encoding="utf-8")
        bal = root / "results/balthasar.md"
        bal.write_text(bal_text or """=== CHUNK: src/a.py (1) ===
## Review
### [HIGH] src/a.py:12 — null を検査する
説明。
## Design Assessment
確認済み。
<!-- MAGI_COMPLETE persona=balthasar chunk=0001 -->
""", encoding="utf-8")
        self.write_status(root, "melchior", mel)
        self.write_status(root, "balthasar", bal)
        self.addCleanup(temporary.cleanup)
        return root

    def write_status(self, run, persona, result, **changes):
        value = status_for(persona, result)
        value.update(changes)
        (run / "status" / f"{persona}.json").write_text(json.dumps(value), encoding="utf-8")
        return value

    def parse(self, run, manifest=None, output_name="canonical.json"):
        output = run / "plan" / output_name
        result = subprocess.run(
            [sys.executable, str(SCRIPT), "parse", "--run-dir", str(run), "--manifest",
             str(manifest or FIXTURES / "common/manifest.json"), "--output", str(output)],
            text=True, capture_output=True)
        return result, output

    def merge(self, canonical, run, policy=None, audit=None, output_name="review.json"):
        output = run / "plan" / output_name
        command = [sys.executable, str(SCRIPT), "merge", "--findings", str(canonical), "--run-policy",
                   str(policy or FIXTURES / "common/policy.json"), "--output", str(output)]
        if audit:
            command.extend(["--audit", str(audit)])
        return subprocess.run(command, text=True, capture_output=True), output

    def audit_fixture(self, run, canonical, name):
        value = json.loads((FIXTURES / name / "annotations.json").read_text())
        value["canonical_sha256"] = hashlib.sha256(canonical.read_bytes()).hexdigest()
        path = run / f"{name}.json"
        path.write_text(json.dumps(value), encoding="utf-8")
        return path

    def test_parse_ok_and_exact_dedupe(self):
        run = self.make_run()
        result, output = self.parse(run)
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(output.read_text())
        self.assertEqual([item["id"] for item in data["findings"]], ["MEL-001", "MEL-002", "BAL-001"])
        self.assertEqual(data["personas"][0]["parse_status"], "ok")
        self.assertEqual(data["findings"][0]["body"], "説明。")
        self.assertEqual(data["findings"][2]["title"], "null を検査する")

    def test_example_echo_finding_is_rejected_and_marks_chunk_malformed(self):
        run = self.make_run(mel_text="""=== CHUNK: src/a.py (1) ===
## Review
### [MEDIUM] MAGI-EXAMPLE/sample.file:12 — example finding (format sample only)
This fictional example must not be accepted as a finding.

### [HIGH] src/a.py:12 — 実際の finding
実際の本文。
## Quality Assessment
確認済み。
<!-- MAGI_COMPLETE persona=melchior chunk=0001 -->
""")
        result, output = self.parse(run)
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(output.read_text())
        mel_findings = [item for item in data["findings"] if item["persona"] == "melchior"]
        normal_mel_findings = [item for item in mel_findings if item["fallback"] is None]
        self.assertEqual([item["title"] for item in normal_mel_findings], ["実際の finding"])
        self.assertFalse(any((item.get("anchor", {}).get("path") or "").startswith("MAGI-EXAMPLE/")
                             for item in mel_findings))
        self.assertNotEqual(data["personas"][0]["parse_status"], "ok")
        self.assertIn("example_echo_detected_0001", data["personas"][0]["diagnostics"])

    def test_partial_parse_adds_pr_level_fallback_and_retains_mid_body_marker(self):
        run = self.make_run(mel_text="""=== CHUNK: src/a.py (1) ===
## Review
### [HIGH] src/a.py:12 — 残す finding
前半。
<!-- MAGI_COMPLETE persona=melchior chunk=0001 -->
後半。
### [MEDIUM] ../outside.py:2 — 不正 path
本文。
## Quality Assessment
確認済み。
<!-- MAGI_COMPLETE persona=melchior chunk=0001 -->
""")
        result, output = self.parse(run)
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(output.read_text())
        mel = [item for item in data["findings"] if item["persona"] == "melchior"]
        self.assertEqual(data["personas"][0]["parse_status"], "partial")
        self.assertEqual([item["title"] for item in mel], ["残す finding", "レビュー出力要確認"])
        self.assertIn("後半。", mel[0]["body"])
        self.assertTrue(all(item["anchor"]["path"] != "../outside.py" for item in mel))
        self.assertEqual(mel[-1]["scope"], "pr")
        self.assertEqual(mel[-1]["severity"], "MEDIUM")

    def test_all_parse_failed_is_unknown_and_retains_sanitised_raw(self):
        raw = "<&" * 3000
        run = self.make_run(mel_text=raw)
        result, output = self.parse(run)
        self.assertEqual(result.returncode, 0, result.stderr)
        finding = next(item for item in json.loads(output.read_text())["findings"] if item["persona"] == "melchior")
        self.assertEqual(finding["severity"], "UNKNOWN")
        self.assertEqual(finding["fallback"]["kind"], "unstructured_output")
        self.assertEqual(finding["raw"]["sha256"], hashlib.sha256(raw.encode()).hexdigest())
        self.assertTrue(finding["raw"]["truncated"])
        self.assertLessEqual(len(finding["raw"]["excerpt_escaped"].encode("utf-8")), 4096)
        self.assertTrue(finding["raw"]["excerpt_escaped"].endswith(("&lt;", "&amp;")))

    def test_raw_excerpt_preserves_utf8_characters_at_byte_boundary(self):
        raw = "🙂" * 1025
        run = self.make_run(mel_text=raw)
        result, output = self.parse(run)
        self.assertEqual(result.returncode, 0, result.stderr)
        finding = next(item for item in json.loads(output.read_text())["findings"] if item["persona"] == "melchior")
        excerpt = finding["raw"]["excerpt_escaped"]
        self.assertEqual(excerpt, "🙂" * 1024)
        self.assertEqual(len(excerpt.encode("utf-8")), 4096)
        self.assertTrue(finding["raw"]["truncated"])
        self.assertNotIn("\ufffd", excerpt)

    def test_zero_findings_requires_assessment_and_final_marker(self):
        good = """=== CHUNK: src/a.py (1) ===
## Review
確認済み。
## Quality Assessment
No findings
<!-- MAGI_COMPLETE persona=melchior chunk=0001 -->
"""
        run = self.make_run(mel_text=good)
        result, output = self.parse(run)
        self.assertEqual(result.returncode, 0, result.stderr)
        parsed = json.loads(output.read_text())
        self.assertEqual(parsed["personas"][0]["parse_status"], "ok")
        self.assertFalse([item for item in parsed["findings"] if item["persona"] == "melchior"])
        bad = good.replace("## Quality Assessment", "## Future Compliance")
        (run / "results/melchior.md").write_text(bad, encoding="utf-8")
        self.write_status(run, "melchior", run / "results/melchior.md")
        result, output = self.parse(run, output_name="bad-zero.json")
        self.assertEqual(result.returncode, 0, result.stderr)
        failed = json.loads(output.read_text())
        self.assertEqual(failed["personas"][0]["parse_status"], "failed")
        self.assertEqual(failed["findings"][0]["fallback"]["kind"], "unstructured_output")

    def test_undocumented_no_findings_with_normal_finding_is_partial(self):
        run = self.make_run(mel_text="""=== CHUNK: src/a.py (1) ===
## Review
### [HIGH] src/a.py:12 — 保持する finding
説明。
<!-- MAGI_COMPLETE persona=melchior chunk=0001 -->
=== CHUNK: src/b.py (1) ===
## Future Compliance
No findings
<!-- MAGI_COMPLETE persona=melchior chunk=0002 -->
""")
        self.write_status(run, "melchior", run / "results/melchior.md", expected_chunks=2,
                          completed_chunks=2, chunks=status_for("melchior", run / "results/melchior.md", chunks=2)["chunks"])
        result, output = self.parse(run)
        self.assertEqual(result.returncode, 0, result.stderr)
        parsed = json.loads(output.read_text())
        mel = [item for item in parsed["findings"] if item["persona"] == "melchior"]
        self.assertEqual(parsed["personas"][0]["parse_status"], "partial")
        self.assertEqual([item["title"] for item in mel], ["保持する finding", "レビュー出力要確認"])

    def test_complete_status_with_nullable_fields_is_partial(self):
        for field in ("input", "backend", "model"):
            with self.subTest(field=field):
                run = self.make_run()
                status = json.loads((run / "status/melchior.json").read_text())
                status[field] = None
                (run / "status/melchior.json").write_text(json.dumps(status), encoding="utf-8")
                result, output = self.parse(run, output_name=field + ".json")
                self.assertEqual(result.returncode, 0, result.stderr)
                parsed = json.loads(output.read_text())
                persona = parsed["personas"][0]
                mel = [item for item in parsed["findings"] if item["persona"] == "melchior"]
                self.assertEqual(persona["parse_status"], "partial")
                self.assertIn("status_complete_nullable_invalid", persona["diagnostics"])
                self.assertEqual(mel[0]["fallback"], None)
                self.assertEqual(mel[-1]["fallback"]["kind"], "unparsed_output")

    def test_failed_not_run_status_allows_nullable_artifacts(self):
        run = self.make_run()
        result_path = run / "results/melchior.md"
        status = json.loads((run / "status/melchior.json").read_text())
        status.update({"execution_status": "failed", "input": None, "result": None,
                       "backend": None, "model": None, "completed_chunks": 0})
        status["chunks"][0].update({"exit_code": None, "marker": "not_run", "output_bytes": 0,
                                    "output_sha256": None, "stderr": None})
        result_path.unlink()
        (run / "status/melchior.json").write_text(json.dumps(status), encoding="utf-8")
        result, output = self.parse(run)
        self.assertEqual(result.returncode, 0, result.stderr)
        persona = json.loads(output.read_text())["personas"][0]
        self.assertEqual(persona["parse_status"], "failed")
        self.assertNotIn("status_complete_nullable_invalid", persona["diagnostics"])

    def test_casper_compliance_status_allows_zero_findings(self):
        run = self.make_run()
        casper = run / "results/casper.md"
        casper.write_text("""=== CHUNK: src/a.py (1) ===
## CASPER Review (Rule Compliance)
確認済み。
## Compliance Status
No findings
<!-- MAGI_COMPLETE persona=casper chunk=0001 -->
""", encoding="utf-8")
        self.write_status(run, "casper", casper)
        manifest = run / "casper-manifest.json"
        manifest.write_text(json.dumps({"schema_version": "persona-manifest/v1", "personas": [{
            "ordinal": 1, "key": "casper", "name": "CASPER", "id_prefix": "CAS"}]}), encoding="utf-8")
        result, output = self.parse(run, manifest)
        self.assertEqual(result.returncode, 0, result.stderr)
        parsed = json.loads(output.read_text())
        self.assertEqual(parsed["personas"], [{"key": "casper", "parse_status": "ok",
                                                  "execution_status": "complete", "diagnostics": []}])
        self.assertEqual(parsed["findings"], [])

    def test_consistent_partial_execution_with_successful_chunk_is_partial(self):
        run = self.make_run()
        mel = run / "results/melchior.md"
        partial_status = status_for("melchior", mel, chunks=2, execution_status="partial")
        (run / "status/melchior.json").write_text(json.dumps(partial_status), encoding="utf-8")
        result, output = self.parse(run)
        self.assertEqual(result.returncode, 0, result.stderr)
        parsed = json.loads(output.read_text())
        mel_persona = parsed["personas"][0]
        mel_findings = [item for item in parsed["findings"] if item["persona"] == "melchior"]
        self.assertEqual(mel_persona["execution_status"], "partial")
        self.assertEqual(mel_persona["parse_status"], "partial")
        self.assertNotIn("status_execution_inconsistent", mel_persona["diagnostics"])
        self.assertEqual(mel_findings[0]["fallback"], None)
        self.assertEqual(mel_findings[-1]["fallback"]["kind"], "unparsed_output")

    def test_status_chunk_integrity_mismatches_are_partial(self):
        cases = (
            ("source_label", lambda status: status["chunks"][0].update({"source_label": "other.py (1)"}),
             "result_chunk_source_label_mismatch_0001"),
            ("output_sha256", lambda status: status["chunks"][0].update({"output_sha256": "b" * 64}),
             "result_chunk_output_identity_mismatch_0001"),
            ("stderr", lambda status: status["chunks"][0].pop("stderr"), "status_chunk_fields_invalid"),
        )
        for name, mutate, diagnostic in cases:
            with self.subTest(name=name):
                run = self.make_run()
                status = json.loads((run / "status/melchior.json").read_text())
                mutate(status)
                (run / "status/melchior.json").write_text(json.dumps(status), encoding="utf-8")
                result, output = self.parse(run, output_name=name + ".json")
                self.assertEqual(result.returncode, 0, result.stderr)
                persona = json.loads(output.read_text())["personas"][0]
                self.assertEqual(persona["parse_status"], "partial")
                self.assertIn(diagnostic, persona["diagnostics"])

    def test_status_and_run_path_inconsistencies_are_not_ok(self):
        run = self.make_run()
        status = json.loads((run / "status/melchior.json").read_text())
        status["completed_chunks"] = 0
        (run / "status/melchior.json").write_text(json.dumps(status), encoding="utf-8")
        result, output = self.parse(run)
        self.assertEqual(result.returncode, 0, result.stderr)
        persona = json.loads(output.read_text())["personas"][0]
        self.assertEqual(persona["parse_status"], "partial")
        self.assertIn("status_completed_chunks_inconsistent", persona["diagnostics"])
        target = run / "real-results"
        os.rename(run / "results", target)
        os.symlink(target, run / "results")
        result, output = self.parse(run, output_name="symlink.json")
        self.assertEqual(result.returncode, 0, result.stderr)
        persona = json.loads(output.read_text())["personas"][0]
        self.assertEqual(persona["parse_status"], "failed")

    def test_five_to_six_personas_preserves_existing_ids(self):
        run = self.make_run()
        first, first_output = self.parse(run, FIXTURES / "manifest-five/manifest.json")
        second, second_output = self.parse(run, FIXTURES / "manifest-six/manifest.json", "six.json")
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(second.returncode, 0, second.stderr)
        five, six = json.loads(first_output.read_text()), json.loads(second_output.read_text())
        self.assertEqual([(item["id"], item["persona"]) for item in five["findings"] if item["persona"] in {"melchior", "balthasar"}],
                         [(item["id"], item["persona"]) for item in six["findings"] if item["persona"] in {"melchior", "balthasar"}])

    def test_five_personas_keep_finding_ids_when_leliel_is_added(self):
        run = self.make_run()
        personas = (
            ("casper", "CASPER", "CAS", "## Compliance Status"),
            ("metatron", "METATRON", "MET", "## Security Assessment"),
            ("sandalphon", "SANDALPHON", "SAN", "## Deployment Assessment"),
        )
        for persona, name, prefix, assessment in personas:
            result = run / "results" / (persona + ".md")
            result.write_text(
                f"=== CHUNK: src/{persona}.py (1) ===\n"
                "## Review\n"
                f"### [HIGH] src/{persona}.py:1 — {persona} finding\n"
                "本文。\n"
                f"{assessment}\n確認済み。\n"
                f"<!-- MAGI_COMPLETE persona={persona} chunk=0001 -->\n",
                encoding="utf-8",
            )
            self.write_status(run, persona, result)

        manifest = {
            "schema_version": "persona-manifest/v1",
            "personas": [
                {"ordinal": ordinal, "key": key, "name": name, "id_prefix": prefix}
                for ordinal, (key, name, prefix) in enumerate((
                    ("melchior", "MELCHIOR", "MEL"),
                    ("balthasar", "BALTHASAR", "BAL"),
                    ("casper", "CASPER", "CAS"),
                    ("metatron", "METATRON", "MET"),
                    ("sandalphon", "SANDALPHON", "SAN"),
                ), 1)
            ],
        }
        manifest_path = run / "manifest-five-in-test.json"
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
        first, first_output = self.parse(run, manifest_path)

        leliel = run / "results/leliel.md"
        leliel.write_text(
            "=== CHUNK: src/leliel.py (1) ===\n"
            "## Review\n"
            "### [LOW] src/leliel.py:1 — leliel finding\n"
            "本文。\n"
            "## Impact Assessment\n確認済み。\n"
            "<!-- MAGI_COMPLETE persona=leliel chunk=0001 -->\n",
            encoding="utf-8",
        )
        self.write_status(run, "leliel", leliel)
        manifest["personas"].append({"ordinal": 6, "key": "leliel", "name": "LELIEL", "id_prefix": "LEL"})
        manifest_six_path = run / "manifest-six-in-test.json"
        manifest_six_path.write_text(json.dumps(manifest), encoding="utf-8")
        second, second_output = self.parse(run, manifest_six_path, "six-in-test.json")

        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(second.returncode, 0, second.stderr)
        five = json.loads(first_output.read_text())
        six = json.loads(second_output.read_text())
        first_ids = {item["id"] for item in five["findings"]}
        second_ids = {item["id"] for item in six["findings"] if item["persona"] != "leliel"}
        self.assertEqual(first_ids, second_ids)

    def test_validate_policy_accepts_git_head_sha_for_hard_github_pr(self):
        policy = json.loads((FIXTURES / "common/policy.json").read_text())
        policy.update({"workflow": "hard", "renderer": "github", "anchor_policy": "pr",
                       "false_positive_policy": "exclude", "head_sha": "a" * 40,
                       "diff_source": {"kind": "file"}})
        self.assertIs(MAGI_AGGREGATE.validate_policy(policy), policy)

    def test_validate_policy_rejects_non_git_head_shas(self):
        policy = json.loads((FIXTURES / "common/policy.json").read_text())
        policy.update({"workflow": "hard", "renderer": "github", "anchor_policy": "pr",
                       "false_positive_policy": "exclude", "diff_source": {"kind": "file"}})
        for value in ("a" * 64, "a" * 39, "a" * 41, "A" + "a" * 39, "g" * 40):
            with self.subTest(head_sha=value):
                policy["head_sha"] = value
                with self.assertRaises(MAGI_AGGREGATE.SchemaError):
                    MAGI_AGGREGATE.validate_policy(policy)

    def test_validate_policy_accepts_none_anchor_with_null_head_sha(self):
        policy = json.loads((FIXTURES / "common/policy.json").read_text())
        self.assertIs(MAGI_AGGREGATE.validate_policy(policy), policy)

    def test_invalid_annotations_fail_open_per_entry(self):
        run = self.make_run()
        parsed, canonical = self.parse(run)
        self.assertEqual(parsed.returncode, 0, parsed.stderr)
        audit = self.audit_fixture(run, canonical, "audit-invalid")
        merged, output = self.merge(canonical, run, audit=audit)
        self.assertEqual(merged.returncode, 0, merged.stderr)
        plan = json.loads(output.read_text())
        self.assertEqual(len(plan["items"]), 3)
        self.assertEqual(plan["summary"]["audit_counts"]["invalid"], 6)
        invalid_root = run / "invalid-root.json"
        invalid_root.write_text("[]", encoding="utf-8")
        merged, output = self.merge(canonical, run, audit=invalid_root, output_name="unavailable.json")
        self.assertEqual(merged.returncode, 0, merged.stderr)
        self.assertEqual(json.loads(output.read_text())["audit"]["status"], "unavailable")

    def test_invalid_duplicate_edges_only_disable_edges(self):
        mel_text = "=== CHUNK: src/a.py (1) ===\n## Review\n" + "".join(
            f"### [MEDIUM] src/m.py:{line} — finding {line}\n本文。\n" for line in range(1, 5)
        ) + "## Quality Assessment\n確認済み。\n<!-- MAGI_COMPLETE persona=melchior chunk=0001 -->\n"
        run = self.make_run(mel_text=mel_text)
        parsed, canonical = self.parse(run)
        self.assertEqual(parsed.returncode, 0, parsed.stderr)
        audit = self.audit_fixture(run, canonical, "audit-duplicate-edges")
        merged, output = self.merge(canonical, run, audit=audit)
        self.assertEqual(merged.returncode, 0, merged.stderr)
        plan = json.loads(output.read_text())
        self.assertEqual([item["source_ids"] for item in plan["items"]], [["MEL-001"], ["MEL-002"], ["MEL-003"], ["MEL-004"], ["BAL-001"]])
        self.assertEqual(plan["summary"]["audit_counts"]["invalid_edge"], 5)

    def test_high_medium_duplicate_uses_high(self):
        run = self.make_run(mel_text="""=== CHUNK: src/a.py (1) ===
## Review
### [HIGH] src/a.py:12 — null を検査する
説明。

### [HIGH] src/a.py:12 — null を検査する
説明。

### [LOW] src/a.py:20 — ログを追加する
詳細。
## Assessment
確認済み。
<!-- MAGI_COMPLETE persona=melchior chunk=0001 -->
""".replace("[HIGH] src/a.py:12", "[MEDIUM] src/a.py:12"))
        parsed, canonical = self.parse(run)
        self.assertEqual(parsed.returncode, 0, parsed.stderr)
        merged, output = self.merge(canonical, run, audit=self.audit_fixture(run, canonical, "audit-high-medium"))
        self.assertEqual(merged.returncode, 0, merged.stderr)
        item = next(item for item in json.loads(output.read_text())["items"] if item["id"] == "BAL-001")
        self.assertEqual(item["source_ids"], ["MEL-001", "BAL-001"])
        self.assertEqual(item["severity"], "HIGH")
        self.assertEqual(item["title"], "null を検査する")
        self.assertEqual(item["personas"], ["melchior", "balthasar"])

    def test_valid_and_needs_human_group_is_not_excluded(self):
        run = self.make_run()
        parsed, canonical = self.parse(run)
        self.assertEqual(parsed.returncode, 0, parsed.stderr)
        merged, output = self.merge(canonical, run, audit=self.audit_fixture(run, canonical, "audit-valid-needs-human"))
        self.assertEqual(merged.returncode, 0, merged.stderr)
        item = next(item for item in json.loads(output.read_text())["items"] if item["id"] == "BAL-001")
        self.assertTrue(item["needs_human"])
        self.assertEqual(item["display_state"], "needs_human")

    def test_no_audit_keeps_every_finding_singleton(self):
        run = self.make_run()
        parsed, canonical = self.parse(run)
        self.assertEqual(parsed.returncode, 0, parsed.stderr)
        merged, output = self.merge(canonical, run)
        self.assertEqual(merged.returncode, 0, merged.stderr)
        plan = json.loads(output.read_text())
        self.assertEqual(plan["audit"]["status"], "absent")
        self.assertEqual([item["source_ids"] for item in plan["items"]], [["MEL-001"], ["MEL-002"], ["BAL-001"]])

    def test_all_false_positive_exclusion_has_reason_and_annotate_keeps_items(self):
        run = self.make_run()
        parsed, canonical = self.parse(run)
        self.assertEqual(parsed.returncode, 0, parsed.stderr)
        audit = self.audit_fixture(run, canonical, "audit-all-excluded")
        policy = json.loads((FIXTURES / "common/policy.json").read_text())
        policy["false_positive_policy"] = "exclude"
        policy_path = run / "exclude-policy.json"
        policy_path.write_text(json.dumps(policy), encoding="utf-8")
        merged, output = self.merge(canonical, run, policy_path, audit)
        self.assertEqual(merged.returncode, 0, merged.stderr)
        plan = json.loads(output.read_text())
        self.assertEqual(plan["items"], [])
        self.assertEqual(len(plan["excluded_findings"]), 3)
        self.assertTrue(all(item["reason_ja"] and item["raw_sha256"] for item in plan["excluded_findings"]))
        policy["false_positive_policy"] = "annotate"
        policy_path.write_text(json.dumps(policy), encoding="utf-8")
        merged, output = self.merge(canonical, run, policy_path, audit, "annotated.json")
        self.assertEqual(merged.returncode, 0, merged.stderr)
        self.assertEqual(len(json.loads(output.read_text())["items"]), 3)

    def test_byte_for_byte_deterministic_outputs_and_manifest_order(self):
        run = self.make_run()
        first, canonical = self.parse(run)
        second, canonical_two = self.parse(run, output_name="canonical-two.json")
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(canonical.read_bytes(), canonical_two.read_bytes())
        unordered = run / "unordered-manifest.json"
        manifest = json.loads((FIXTURES / "common/manifest.json").read_text())
        manifest["personas"].reverse()
        unordered.write_text(json.dumps(manifest), encoding="utf-8")
        ordered, canonical_three = self.parse(run, unordered, "canonical-unordered.json")
        self.assertEqual(ordered.returncode, 0, ordered.stderr)
        self.assertEqual(canonical.read_bytes(), canonical_three.read_bytes())
        audit = self.audit_fixture(run, canonical, "audit-high-medium")
        first, review = self.merge(canonical, run, audit=audit)
        second, review_two = self.merge(canonical, run, audit=audit, output_name="review-two.json")
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(review.read_bytes(), review_two.read_bytes())

    def test_exit_code_categories_and_merge_path_validator(self):
        run = self.make_run()
        success, canonical = self.parse(run)
        self.assertEqual(success.returncode, 0, success.stderr)
        bad_manifest = run / "bad-manifest.json"
        bad_manifest.write_text("{}", encoding="utf-8")
        schema, _ = self.parse(run, bad_manifest, "schema.json")
        self.assertEqual(schema.returncode, 2)
        broken_manifest = run / "broken-manifest.json"
        broken_manifest.write_text("{", encoding="utf-8")
        io_error, _ = self.parse(run, broken_manifest, "io.json")
        self.assertEqual(io_error.returncode, 1)
        value = json.loads(canonical.read_text())
        value["findings"][0]["anchor"]["path"] = "../escape.py"
        malformed = run / "malformed-canonical.json"
        malformed.write_text(json.dumps(value), encoding="utf-8")
        merged, _ = self.merge(malformed, run)
        self.assertEqual(merged.returncode, 2)


if __name__ == "__main__":
    unittest.main()
