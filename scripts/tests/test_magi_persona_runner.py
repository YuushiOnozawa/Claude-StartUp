import hashlib
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "magi-persona-runner.py"
FIXTURE_ROOT = ROOT / "scripts" / "tests" / "fixtures" / "magi-persona-runner"
FAKE_RUNNER = ROOT / "scripts" / "tests" / "fixtures" / "fake-ollama-runner.sh"


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def one_file_diff(path="src/example.py", lines=4):
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


def two_chunk_diff():
    return one_file_diff("src/first.py", 210) + one_file_diff("src/second.py", 210)


class MagiPersonaRunnerTests(unittest.TestCase):
    def setUp(self):
        FAKE_RUNNER.chmod(FAKE_RUNNER.stat().st_mode | stat.S_IXUSR)

    def make_repo_root(self, root):
        repo_root = root / "repo"
        shutil.copytree(FIXTURE_ROOT, repo_root)
        scripts = repo_root / "scripts"
        scripts.mkdir()
        shutil.copy2(ROOT / "scripts" / "magi-split-hunk.sh", scripts / "magi-split-hunk.sh")
        return repo_root

    def make_run_dir(self, root, data):
        diff_hash = sha256(data)
        run_dir = root / diff_hash / "20260712T120000Z-12345"
        (run_dir / "diff").mkdir(parents=True)
        (run_dir / "results").mkdir()
        (run_dir / "status").mkdir()
        (run_dir / "diff" / "input.filtered.patch").write_bytes(data)
        return run_dir

    def env_for(self, run_dir, persona="melchior", extra=None):
        env = {
            **os.environ,
            "MAGI_RUN_DIR": str(run_dir),
            "MAGI_INPUT_FILE": str(run_dir / "diff" / "input.filtered.patch"),
            "MAGI_RESULT_FILE": str(run_dir / "results" / ("%s.md" % persona)),
            "MAGI_STATUS_FILE": str(run_dir / "status" / ("%s.json" % persona)),
            "MAGI_QUIET": "1",
            "PERSONA_NAME": persona.upper(),
            "MAGI_OLLAMA_RUNNER": str(FAKE_RUNNER),
        }
        if extra:
            env.update(extra)
        return env

    def run_persona(self, root, persona="melchior", data=None, env_extra=None, repo_root=None):
        data = data if data is not None else one_file_diff()
        repo_root = repo_root or self.make_repo_root(root)
        run_dir = self.make_run_dir(root, data)
        command = [sys.executable, str(SCRIPT), persona, "--repo-root", str(repo_root)]
        result = subprocess.run(command, text=True, capture_output=True,
                                env=self.env_for(run_dir, persona, env_extra))
        status_path = run_dir / "status" / ("%s.json" % persona)
        status = json.loads(status_path.read_text(encoding="utf-8")) if status_path.exists() else None
        return result, run_dir, status

    def test_success_publishes_complete_result(self):
        with tempfile.TemporaryDirectory() as name:
            output = (
                "## MELCHIOR Review (Code Quality & Bugs)\n\n"
                "## Quality Assessment\nNo findings\n"
                "<!-- MAGI_COMPLETE persona=melchior chunk=0001 -->\n"
            )
            result, run_dir, status = self.run_persona(Path(name), env_extra={"FAKE_OLLAMA_OUTPUT": output})
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(status["execution_status"], "complete")
            self.assertEqual(status["completed_chunks"], 1)
            self.assertEqual(status["chunks"][0]["marker"], "complete")
            self.assertEqual(json.loads(result.stdout)["result"]["path"], "results/melchior.md")
            self.assertIn("MAGI_COMPLETE persona=melchior chunk=0001",
                          (run_dir / "results" / "melchior.md").read_text(encoding="utf-8"))

    def test_markerless_assessment_fallback_completes_chunk(self):
        with tempfile.TemporaryDirectory() as name:
            output = (
                "## MELCHIOR Review (Code Quality & Bugs)\n\n"
                "## Quality Assessment\nNo findings\n"
            )
            result, _, status = self.run_persona(Path(name), env_extra={"FAKE_OLLAMA_OUTPUT": output})
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(status["execution_status"], "complete")
            self.assertEqual(status["chunks"][0]["marker"], "missing")
            self.assertEqual(status["chunks"][0]["exit_code"], 0)

    def test_fail_fast_marks_remaining_chunks_not_run(self):
        with tempfile.TemporaryDirectory() as name:
            result, _, status = self.run_persona(
                Path(name),
                data=two_chunk_diff(),
                env_extra={"FAKE_OLLAMA_OUTPUT": "incomplete body\n", "FAKE_OLLAMA_EXIT": "1"},
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(status["execution_status"], "failed")
            self.assertEqual(status["expected_chunks"], 2)
            self.assertEqual(status["chunks"][0]["exit_code"], 1)
            self.assertEqual(status["chunks"][1]["marker"], "not_run")
            self.assertIsNone(status["chunks"][1]["exit_code"])

    def test_symlink_component_in_run_dir_is_configuration_error(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            repo_root = self.make_repo_root(root)
            data = one_file_diff()
            real_run = self.make_run_dir(root / "real", data)
            link_parent = root / "links"
            link_parent.mkdir()
            link_run = link_parent / "run"
            link_run.symlink_to(real_run, target_is_directory=True)
            result = subprocess.run(
                [sys.executable, str(SCRIPT), "melchior", "--repo-root", str(repo_root)],
                text=True, capture_output=True, env=self.env_for(link_run),
            )
            self.assertEqual(result.returncode, 2)
            self.assertIn("configuration_error", result.stderr)

    def test_result_file_mismatch_is_configuration_error(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            repo_root = self.make_repo_root(root)
            run_dir = self.make_run_dir(root, one_file_diff())
            env = self.env_for(run_dir)
            env["MAGI_RESULT_FILE"] = str(run_dir / "results" / "wrong.md")
            result = subprocess.run([sys.executable, str(SCRIPT), "melchior", "--repo-root", str(repo_root)],
                                    text=True, capture_output=True, env=env)
            self.assertEqual(result.returncode, 2)
            self.assertIn("configuration_error", result.stderr)

    def test_missing_status_file_env_is_configuration_error(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            repo_root = self.make_repo_root(root)
            run_dir = self.make_run_dir(root, one_file_diff())
            env = self.env_for(run_dir)
            env["MAGI_STATUS_FILE"] = ""
            result = subprocess.run([sys.executable, str(SCRIPT), "melchior", "--repo-root", str(repo_root)],
                                    text=True, capture_output=True, env=env)
            self.assertEqual(result.returncode, 2)
            self.assertIn("configuration_error", result.stderr)

    def test_header_render_failure_is_configuration_error(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            repo_root = self.make_repo_root(root)
            task = repo_root / "skills" / "melchior" / "references" / "task-instruction.md"
            task.write_text(task.read_text(encoding="utf-8") + "\n## Review Header\n`## Duplicate`\n",
                            encoding="utf-8")
            run_dir = self.make_run_dir(root, one_file_diff())
            result = subprocess.run([sys.executable, str(SCRIPT), "melchior", "--repo-root", str(repo_root)],
                                    text=True, capture_output=True, env=self.env_for(run_dir))
            self.assertEqual(result.returncode, 2)
            self.assertIn("configuration_error", result.stderr)

    def test_change_summary_is_injected_into_system_text(self):
        with tempfile.TemporaryDirectory() as name:
            system_log = Path(name) / "system.log"
            output = "## Quality Assessment\nNo findings\n<!-- MAGI_COMPLETE persona=melchior chunk=0001 -->\n"
            result, _, _ = self.run_persona(
                Path(name),
                env_extra={
                    "FAKE_OLLAMA_OUTPUT": output,
                    "MAGI_CHANGE_SUMMARY": "intentional refactor",
                    "FAKE_OLLAMA_SYSTEM_LOG": str(system_log),
                },
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            system_text = system_log.read_text(encoding="utf-8")
            self.assertIn("---CHANGE_SUMMARY---", system_text)
            self.assertIn("intentional refactor", system_text)
            self.assertIn("意図は証拠であって免罪符ではない", system_text)

    def test_leliel_impact_context_is_before_chunk_input(self):
        with tempfile.TemporaryDirectory() as name:
            prompt_log = Path(name) / "prompt.log"
            output = "## Impact Assessment\nNo findings\n<!-- MAGI_COMPLETE persona=leliel chunk=0001 -->\n"
            result, _, _ = self.run_persona(
                Path(name),
                persona="leliel",
                env_extra={
                    "FAKE_OLLAMA_OUTPUT": output,
                    "MAGI_IMPACT_CONTEXT": "CALLGRAPH_CONTEXT",
                    "FAKE_OLLAMA_PROMPT_LOG": str(prompt_log),
                },
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            prompt = prompt_log.read_text(encoding="utf-8")
            task_start = prompt.index("---TASK_DATA_START---")
            impact = prompt.index("---IMPACT_CONTEXT---")
            chunk = prompt.index("---CHUNK_INPUT---")
            diff = prompt.index("diff --git")
            self.assertLess(task_start, impact)
            self.assertLess(impact, chunk)
            self.assertLess(chunk, diff)


if __name__ == "__main__":
    unittest.main()
